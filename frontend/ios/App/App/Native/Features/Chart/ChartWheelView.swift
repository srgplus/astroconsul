import SwiftUI

/// One body on the wheel: where it is, and what to draw for it.
struct ChartWheelBody: Identifiable, Hashable {
    let id: String
    let longitude: Double
    var isRetrograde = false

    var glyph: String { AstroGlyph.object(id) }
    /// Planets ride the outer row of their pair, points the inner one.
    var isPlanet: Bool { Zodiac.isPlanet(id) }
}

/// How one aspect's line is drawn: no hue, only weight and rhythm.
///
/// The web ring gives each aspect a colour, but the web draws on white. This
/// card floats over a sky that is blue, green, orange or red depending on the
/// day's TII, so a green sextile line vanishes over a green sky and an orange
/// square over an orange one. Worse, those are the *same* four hues the app
/// already spends on the TII zones, so one orange would mean two unrelated
/// things on one screen.
///
/// So the ink is the palette's — white over the sky, dark ink on a surface —
/// and the aspect is carried the way an instrument face carries it:
///
/// - **Solid is hard, broken is soft.** Conjunction, opposition and square are
///   unbroken; trine is a long dash and sextile a dot. Friction reads as a
///   continuous line, flow as an interrupted one.
/// - **Weight ranks within the family.** Conjunction is the heaviest line on
///   the wheel and sextile the lightest.
/// - **Orb sets the ink.** A partile aspect is at full strength and one at the
///   edge of orb is half — which the coloured version could not say at all, and
///   is the thing you actually want to see first.
struct AspectStyle: Equatable {

    let dash: [CGFloat]
    let width: CGFloat
    let ink: Double

    static func named(_ aspect: String) -> AspectStyle {
        styles[aspect.lowercased()] ?? styles["sextile"]!
    }

    /// Ink for an aspect this far from exact. Falls off to a little over half
    /// by 6°, which is where the engine's orbs end for most pairs.
    static func ink(orb: Double) -> Double {
        1 - min(abs(orb), 6) / 6 * 0.45
    }

    private static let styles: [String: AspectStyle] = [
        "conjunction": AspectStyle(dash: [], width: 1.5, ink: 0.95),
        "opposition": AspectStyle(dash: [], width: 1.1, ink: 0.85),
        "square": AspectStyle(dash: [], width: 0.8, ink: 0.8),
        "trine": AspectStyle(dash: [6, 3.5], width: 1.1, ink: 0.8),
        "sextile": AspectStyle(dash: [0.5, 3], width: 0.9, ink: 0.7),
    ]
}

/// The birth chart, drawn as a dial.
///
/// Deliberately not a transcription of the web wheel. That one is a document:
/// curved sign names, hover tooltips, everything legible at desktop width. On
/// a phone the same rings have to read at a glance, so this follows the
/// instrument faces in Weather instead — fine ticks around the rim, upright
/// glyphs, hairlines, and no text that has to be chased around a curve.
///
/// Up to five rings: the zodiac, then a pair for the natal bodies and a pair
/// for the transiting ones, each pair being planets outside and special points
/// inside. Both switches off leaves two, which is what a phone can hold.
///
/// The web's hover tooltip has no phone equivalent, so a glyph or a line is
/// tapped instead and named in the caption under the wheel. The card owns that
/// caption, which is why `selection` is a binding rather than state.
///
/// One `Canvas` rather than a stack of shape views: seventy ticks, two dozen
/// dividers, three dozen glyphs and a hundred aspect lines as separate views is
/// a layout pass the phone does not need to do.
struct ChartWheelView: View {

    let chart: ChartWheelData
    @Binding var selection: ChartWheelSelection?
    /// A tap that landed between the rings, in the empty middle, or anywhere
    /// else that names nothing. Handed up so the card can treat its wheel's
    /// empty surface as the way into the full-screen one; left nil — which is
    /// what the full-screen wheel does — an empty tap clears the selection.
    var onTapEmpty: (() -> Void)?

    @Environment(\.transitPalette) private var palette

    /// `@State`, not `let`: a stored property on a `View` is rebuilt every
    /// time SwiftUI rebuilds the struct, and a generator that new has not
    /// warmed the Taptic Engine, so the first tap after any redraw would be
    /// silent.
    @State private var haptics = UISelectionFeedbackGenerator()

    var body: some View {
        GeometryReader { proxy in
            let layout = WheelLayout(size: proxy.size, chart: chart)

            Canvas(rendersAsynchronously: false) { context, _ in
                draw(layout, in: context)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { tap in
                    select(layout.hit(tap.location))
                }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Birth chart wheel")
    }

    private func select(_ hit: ChartWheelSelection?) {
        // Nothing under the finger, and somewhere for that to go: on the card
        // this is the largest target on the panel and it means "show me this
        // properly". The selection is carried across rather than cleared, so
        // whatever was picked out is still named on the screen that opens.
        if hit == nil, let onTapEmpty {
            onTapEmpty()
            return
        }

        // Tapping the same thing again lets go of it, so the caption can be
        // cleared without hunting for empty space between the rings.
        let next = hit == selection ? nil : hit
        if next != nil { haptics.selectionChanged() }
        withAnimation(.easeOut(duration: 0.15)) { selection = next }
    }

    // MARK: - Drawing

    private func draw(_ layout: WheelLayout, in context: GraphicsContext) {
        drawZodiac(layout, in: context)
        drawBands(layout, ring: layout.natalRing, labelsHouses: true, in: context)

        if chart.showsTransits {
            drawBands(layout, ring: layout.transitRing, labelsHouses: false, in: context)
        }

        drawGlyphs(layout, in: context)
        drawAxes(layout, in: context)

        // Last, so the lines lie over every ring they cross.
        drawAspects(layout, in: context)
    }

    // MARK: - Zodiac ring

    /// The rim, inverted: a dark band with light ink on it, the way the web
    /// chart's is. It is the one part of the wheel that does not follow the
    /// palette — it makes its own contrast rather than borrowing the sky's.
    private func drawZodiac(_ layout: WheelLayout, in context: GraphicsContext) {
        let metrics = layout.metrics
        let center = layout.center

        context.stroke(
            circle(center: center, radius: metrics.zodiacMid),
            with: .color(.black.opacity(0.62)),
            lineWidth: metrics.zodiacBand
        )

        // Degree ticks: one every 5°, a full-height brighter one on each sign
        // boundary. This is the part that makes it read as an instrument.
        for step in 0..<72 {
            let angle = chart.angle(of: Double(step) * 5)
            let isBoundary = step % 6 == 0
            let length = isBoundary ? metrics.zodiacBand : metrics.tick

            var path = Path()
            path.move(to: WheelMath.point(center: center, radius: metrics.zodiacOuter, angle: angle))
            path.addLine(to: WheelMath.point(center: center, radius: metrics.zodiacOuter - length, angle: angle))
            context.stroke(
                path,
                with: .color(.white.opacity(isBoundary ? 0.5 : 0.28)),
                lineWidth: isBoundary ? 1 : 0.75
            )
        }

        for index in 0..<12 {
            draw(
                Zodiac.glyphs[index],
                font: glyph(metrics.signGlyph),
                color: .white.opacity(0.92),
                at: WheelMath.point(
                    center: center,
                    radius: metrics.zodiacMid,
                    angle: chart.angle(of: Double(index) * 30 + 15)
                ),
                in: context
            )
        }
    }

    // MARK: - Body rings

    /// The two bands of one pair, their outlines, and the house dividers and
    /// numbers that cross them.
    private func drawBands(
        _ layout: WheelLayout,
        ring: WheelLayout.Ring,
        labelsHouses: Bool,
        in context: GraphicsContext
    ) {
        let center = layout.center

        context.stroke(
            circle(center: center, radius: ring.mid),
            with: .color(palette.primary.opacity(0.07)),
            lineWidth: ring.outer - ring.inner
        )
        hairline(context, center: center, radius: ring.outer)
        hairline(context, center: center, radius: ring.inner)

        if !chart.hidesSpecialPoints {
            context.stroke(
                circle(center: center, radius: ring.pointsMid),
                with: .color(palette.primary.opacity(0.07)),
                lineWidth: ring.points - ring.pointsInner
            )
            hairline(context, center: center, radius: ring.points)
            hairline(context, center: center, radius: ring.pointsInner)
        }

        guard chart.houses.count == 12 else { return }

        // The angles get a divider too: they are house cusps in all but name,
        // and without them the ring's quarters do not line up with the axes.
        let cusps = chart.houses + [chart.asc, Zodiac.normalize(chart.asc + 180)]
            + (chart.mc.map { [$0, Zodiac.normalize($0 + 180)] } ?? [])

        for cusp in cusps {
            let angle = chart.angle(of: cusp)
            var path = Path()
            path.move(to: WheelMath.point(center: center, radius: ring.outer, angle: angle))
            path.addLine(to: WheelMath.point(center: center, radius: ring.inner, angle: angle))
            if !chart.hidesSpecialPoints {
                path.move(to: WheelMath.point(center: center, radius: ring.points, angle: angle))
                path.addLine(to: WheelMath.point(center: center, radius: ring.pointsInner, angle: angle))
            }
            context.stroke(path, with: .color(palette.primary.opacity(0.3)), lineWidth: 0.75)
        }

        // House numbers ride the gap above the natal ring only. Repeating them
        // against the transit ring would say nothing new.
        guard labelsHouses else { return }

        for (index, cusp) in chart.houses.enumerated() {
            let midAngle = chart.angle(
                of: WheelMath.midpoint(from: cusp, to: chart.houses[(index + 1) % chart.houses.count])
            )
            draw(
                "\(index + 1)",
                font: label(layout.metrics.houseLabel, .medium),
                color: palette.tertiary,
                at: WheelMath.point(center: center, radius: layout.metrics.houseLabelRadius, angle: midAngle),
                in: context
            )
        }
    }

    private func drawGlyphs(_ layout: WheelLayout, in context: GraphicsContext) {
        for placed in layout.glyphs {
            let isSelected = selection == .body(placed.body, isTransit: placed.isTransit)
            let center = layout.center

            // The tick stays on the true longitude even when the glyph had to
            // move, so the position is never a lie.
            var ticks = Path()
            ticks.move(to: WheelMath.point(center: center, radius: placed.bandOuter, angle: placed.angle))
            ticks.addLine(to: WheelMath.point(center: center, radius: placed.bandOuter + layout.metrics.tick, angle: placed.angle))
            ticks.move(to: WheelMath.point(center: center, radius: placed.bandInner, angle: placed.angle))
            ticks.addLine(to: WheelMath.point(center: center, radius: placed.bandInner - layout.metrics.tick, angle: placed.angle))
            context.stroke(
                ticks,
                with: .color(palette.primary.opacity((isSelected ? 1 : 0.45) * placed.ink)),
                lineWidth: 1
            )

            if isSelected {
                context.stroke(
                    circle(center: placed.point, radius: placed.size * 0.8),
                    with: .color(palette.primary.opacity(0.9)),
                    lineWidth: 1.5
                )
            }

            draw(
                placed.body.glyph,
                font: glyph(placed.size),
                color: palette.primary.opacity(placed.ink),
                at: placed.point,
                in: context
            )
        }
    }

    // MARK: - Angles

    private func drawAxes(_ layout: WheelLayout, in context: GraphicsContext) {
        let metrics = layout.metrics
        let center = layout.center

        var axes: [(label: String, longitude: Double, chevron: Bool)] = [
            ("AC", chart.asc, true),
            ("DC", Zodiac.normalize(chart.asc + 180), false),
        ]
        if let mc = chart.mc {
            axes.append(("MC", mc, true))
            axes.append(("IC", Zodiac.normalize(mc + 180), false))
        }

        for axis in axes {
            let angle = chart.angle(of: axis.longitude)
            let tip = WheelMath.point(center: center, radius: metrics.zodiacOuter, angle: angle)

            var line = Path()
            line.move(to: WheelMath.point(center: center, radius: metrics.zodiacInner, angle: angle))
            line.addLine(to: tip)
            context.stroke(line, with: .color(.white.opacity(0.8)), lineWidth: 1)

            if axis.chevron {
                let base = WheelMath.point(center: center, radius: metrics.zodiacOuter - metrics.arrow, angle: angle)
                let tangent = WheelMath.tangentUnit(angle)
                var chevron = Path()
                chevron.move(to: CGPoint(x: base.x + tangent.x * metrics.arrow, y: base.y + tangent.y * metrics.arrow))
                chevron.addLine(to: tip)
                chevron.addLine(to: CGPoint(x: base.x - tangent.x * metrics.arrow, y: base.y - tangent.y * metrics.arrow))
                context.stroke(
                    chevron,
                    with: .color(palette.primary.opacity(0.7)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
                )
            }

            draw(
                axis.label,
                font: label(metrics.axisLabel, .semibold),
                color: palette.secondary,
                at: WheelMath.point(center: center, radius: metrics.zodiacOuter + metrics.axisLabelOffset, angle: angle),
                in: context
            )
        }
    }

    // MARK: - Aspect lines

    private func drawAspects(_ layout: WheelLayout, in context: GraphicsContext) {
        for line in layout.lines {
            let isSelected = selection == line.subject
            var path = Path()
            path.move(to: line.from)
            path.addLine(to: line.to)
            context.stroke(
                path,
                with: .color(palette.primary.opacity(isSelected ? 1 : line.style.ink * line.ink)),
                style: StrokeStyle(
                    lineWidth: line.style.width + (isSelected ? 0.9 : 0),
                    lineCap: .round,
                    dash: isSelected ? [] : line.style.dash
                )
            )
        }
    }

    // MARK: - Drawing helpers

    private func circle(center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }

    private func hairline(_ context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        context.stroke(
            circle(center: center, radius: radius),
            with: .color(palette.primary.opacity(0.26)),
            lineWidth: 0.75
        )
    }

    private func draw(
        _ string: String,
        font: Font,
        color: Color,
        at point: CGPoint,
        in context: GraphicsContext
    ) {
        var resolved = context.resolve(Text(string).font(font))
        resolved.shading = .color(color)
        context.draw(resolved, at: point, anchor: .center)
    }

    /// Numbers and letters on the wheel, in the app's own face.
    private func label(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Astrological glyphs, in the default face. SF Rounded carries no zodiac
    /// signs, and inside a `Canvas` a missing glyph is a tofu box rather than
    /// a fallback, so these never ask for a design.
    private func glyph(_ size: CGFloat) -> Font {
        .system(size: size)
    }
}
