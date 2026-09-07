import SwiftUI

/// One body on the wheel: where it is, and what to draw for it.
struct ChartWheelBody: Identifiable, Hashable {
    let id: String
    let longitude: Double

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
struct AspectStyle {

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
/// One `Canvas` rather than a stack of shape views: seventy ticks, two dozen
/// dividers, three dozen glyphs and a hundred aspect lines as separate views is
/// a layout pass the phone does not need to do.
struct ChartWheelView: View {

    /// Ascendant. The whole wheel is rotated so it sits on the left horizon,
    /// so without it there is nothing to draw.
    let asc: Double
    var mc: Double?
    var houses: [Double] = []
    var bodies: [ChartWheelBody] = []
    /// Where the same bodies are right now. Empty draws the natal chart alone.
    var transits: [ChartWheelBody] = []
    var natalAspects: [NatalAspect] = []
    var transitAspects: [ActiveAspect] = []
    /// Chiron, Lilith, the nodes and the parts, folded away.
    var hidesSpecialPoints = false

    @Environment(\.transitPalette) private var palette

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let metrics = Metrics(
                size: min(size.width, size.height),
                showsTransits: !transits.isEmpty,
                showsSpecialPoints: !hidesSpecialPoints
            )
            let origin = CGPoint(x: size.width / 2, y: size.height / 2)

            let natalRing = Ring(outer: metrics.natalUpperOuter, inner: metrics.natalUpperInner,
                                 points: metrics.natalLowerOuter, pointsInner: metrics.natalLowerInner)
            let transitRing = Ring(outer: metrics.transitUpperOuter, inner: metrics.transitUpperInner,
                                   points: metrics.transitLowerOuter, pointsInner: metrics.transitLowerInner)

            drawZodiac(in: context, metrics: metrics, center: origin)
            drawBands(in: context, metrics: metrics, center: origin, ring: natalRing, labelsHouses: true)
            drawGlyphs(in: context, metrics: metrics, center: origin, ring: natalRing,
                       bodies: bodies, glyphSize: metrics.bodyGlyph, opacity: 1)

            if !transits.isEmpty {
                drawBands(in: context, metrics: metrics, center: origin, ring: transitRing, labelsHouses: false)
                drawGlyphs(in: context, metrics: metrics, center: origin, ring: transitRing,
                           bodies: transits, glyphSize: metrics.transitGlyph, opacity: 0.85)
            }

            drawAxes(in: context, metrics: metrics, center: origin)

            // Last, so the lines lie over every ring they cross.
            drawAspects(in: context, metrics: metrics, center: origin,
                        natalRing: natalRing, transitRing: transitRing)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Birth chart wheel")
    }

    // MARK: - Zodiac ring

    /// The rim, inverted: a dark band with light ink on it, the way the web
    /// chart's is. It is the one part of the wheel that does not follow the
    /// palette — it makes its own contrast rather than borrowing the sky's.
    private func drawZodiac(in context: GraphicsContext, metrics: Metrics, center: CGPoint) {
        context.stroke(
            circle(center: center, radius: metrics.zodiacMid),
            with: .color(.black.opacity(0.62)),
            lineWidth: metrics.zodiacBand
        )

        // Degree ticks: one every 5°, a full-height brighter one on each sign
        // boundary. This is the part that makes it read as an instrument.
        for step in 0..<72 {
            let angle = WheelMath.angle(longitude: Double(step) * 5, asc: asc)
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
            let angle = WheelMath.angle(longitude: Double(index) * 30 + 15, asc: asc)
            draw(
                Zodiac.glyphs[index],
                font: glyph(metrics.signGlyph),
                color: .white.opacity(0.92),
                at: WheelMath.point(center: center, radius: metrics.zodiacMid, angle: angle),
                in: context
            )
        }
    }

    // MARK: - Body rings

    /// The two bands of one pair, their outlines, and the house dividers and
    /// numbers that cross them.
    private func drawBands(
        in context: GraphicsContext,
        metrics: Metrics,
        center: CGPoint,
        ring: Ring,
        labelsHouses: Bool
    ) {
        context.stroke(
            circle(center: center, radius: ring.mid),
            with: .color(palette.primary.opacity(0.07)),
            lineWidth: ring.outer - ring.inner
        )
        hairline(context, center: center, radius: ring.outer)
        hairline(context, center: center, radius: ring.inner)

        if !hidesSpecialPoints {
            context.stroke(
                circle(center: center, radius: ring.pointsMid),
                with: .color(palette.primary.opacity(0.07)),
                lineWidth: ring.points - ring.pointsInner
            )
            hairline(context, center: center, radius: ring.points)
            hairline(context, center: center, radius: ring.pointsInner)
        }

        guard houses.count == 12 else { return }

        // The angles get a divider too: they are house cusps in all but name,
        // and without them the ring's quarters do not line up with the axes.
        let cusps = houses + [asc, Zodiac.normalize(asc + 180)]
            + (mc.map { [$0, Zodiac.normalize($0 + 180)] } ?? [])

        for cusp in cusps {
            let angle = WheelMath.angle(longitude: cusp, asc: asc)
            var path = Path()
            path.move(to: WheelMath.point(center: center, radius: ring.outer, angle: angle))
            path.addLine(to: WheelMath.point(center: center, radius: ring.inner, angle: angle))
            if !hidesSpecialPoints {
                path.move(to: WheelMath.point(center: center, radius: ring.points, angle: angle))
                path.addLine(to: WheelMath.point(center: center, radius: ring.pointsInner, angle: angle))
            }
            context.stroke(path, with: .color(palette.primary.opacity(0.3)), lineWidth: 0.75)
        }

        // House numbers ride the gap above the natal ring only. Repeating them
        // against the transit ring would say nothing new.
        guard labelsHouses else { return }

        for (index, cusp) in houses.enumerated() {
            let midAngle = WheelMath.angle(
                longitude: WheelMath.midpoint(from: cusp, to: houses[(index + 1) % houses.count]),
                asc: asc
            )
            draw(
                "\(index + 1)",
                font: label(metrics.houseLabel, .medium),
                color: palette.tertiary,
                at: WheelMath.point(center: center, radius: metrics.houseLabelRadius, angle: midAngle),
                in: context
            )
        }
    }

    private func drawGlyphs(
        in context: GraphicsContext,
        metrics: Metrics,
        center: CGPoint,
        ring: Ring,
        bodies: [ChartWheelBody],
        glyphSize: CGFloat,
        opacity: Double
    ) {
        let drawn = drawable(bodies)
        guard !drawn.isEmpty else { return }

        let rows = [
            (bodies: drawn.filter(\.isPlanet), outer: ring.outer, inner: ring.inner, mid: ring.mid),
            (bodies: drawn.filter { !$0.isPlanet }, outer: ring.points, inner: ring.pointsInner, mid: ring.pointsMid),
        ]

        for row in rows where !row.bodies.isEmpty {
            let placed = WheelMath.spread(
                markers: row.bodies.map { ($0.id, $0.longitude, $0.glyph) },
                asc: asc,
                radius: row.mid,
                glyphSize: glyphSize
            )

            for body in placed {
                // The tick stays on the true longitude even when the glyph had
                // to move, so the position is never a lie.
                var ticks = Path()
                ticks.move(to: WheelMath.point(center: center, radius: row.outer, angle: body.angle))
                ticks.addLine(to: WheelMath.point(center: center, radius: row.outer + metrics.tick, angle: body.angle))
                ticks.move(to: WheelMath.point(center: center, radius: row.inner, angle: body.angle))
                ticks.addLine(to: WheelMath.point(center: center, radius: row.inner - metrics.tick, angle: body.angle))
                context.stroke(ticks, with: .color(palette.primary.opacity(0.45 * opacity)), lineWidth: 1)

                draw(
                    body.glyph,
                    font: glyph(glyphSize),
                    color: palette.primary.opacity(opacity),
                    at: WheelMath.point(center: center, radius: row.mid, angle: body.displayAngle),
                    in: context
                )
            }
        }
    }

    // MARK: - Angles

    private func drawAxes(in context: GraphicsContext, metrics: Metrics, center: CGPoint) {
        var axes: [(label: String, longitude: Double, chevron: Bool)] = [
            ("AC", asc, true),
            ("DC", Zodiac.normalize(asc + 180), false),
        ]
        if let mc {
            axes.append(("MC", mc, true))
            axes.append(("IC", Zodiac.normalize(mc + 180), false))
        }

        for axis in axes {
            let angle = WheelMath.angle(longitude: axis.longitude, asc: asc)
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

    private func drawAspects(
        in context: GraphicsContext,
        metrics: Metrics,
        center: CGPoint,
        natalRing: Ring,
        transitRing: Ring
    ) {
        // The angles are drawn as arrows through the rim rather than glyphs on
        // a ring, so they need a place of their own or every aspect to them is
        // dropped — and a transit exact on the ascendant is the loudest line
        // in the report.
        let natal = placements(of: bodies, on: natalRing)
            .merging(axisPlacements(metrics)) { body, _ in body }

        // Natal to natal: both ends sit just inside their own band, and the
        // line crosses whatever is in the middle, which is what the web does.
        //
        // Dimmed once transits are on. Both grids at full strength is fifty
        // lines through one circle, and on a phone that is a ball of wool —
        // the natal grid is the standing background, the transits are the news.
        let natalInk = transits.isEmpty ? 1.0 : 0.5

        for aspect in natalAspects {
            guard let from = natal[aspect.p1], let to = natal[aspect.p2] else { continue }
            stroke(
                from: WheelMath.point(center: center, radius: from.inner - metrics.notch, angle: from.angle),
                to: WheelMath.point(center: center, radius: to.inner - metrics.notch, angle: to.angle),
                style: .named(aspect.aspect),
                ink: natalInk * AspectStyle.ink(orb: aspect.orb),
                in: context
            )
        }

        guard !transits.isEmpty else { return }
        let transiting = placements(of: transits, on: transitRing)

        // Transit to natal: each end leaves from whichever of its two edges
        // faces the other end, so a line never has to cross its own band.
        for aspect in transitAspects {
            guard let natalEnd = natal[aspect.natalObject],
                  let transitEnd = transiting[aspect.transitObject] else { continue }

            let natalMid = WheelMath.point(center: center, radius: natalEnd.mid, angle: natalEnd.angle)
            let transitMid = WheelMath.point(center: center, radius: transitEnd.mid, angle: transitEnd.angle)

            let natalPoint = edge(of: natalEnd, facing: transitMid, from: natalMid, center: center, notch: metrics.notch)
            let transitPoint = edge(of: transitEnd, facing: natalMid, from: transitMid, center: center, notch: metrics.notch)
            stroke(
                from: natalPoint,
                to: transitPoint,
                style: .named(aspect.aspect),
                ink: AspectStyle.ink(orb: aspect.orb),
                in: context
            )
        }
    }

    /// Where each drawn body sits on its ring, keyed by id. The true angle, not
    /// the nudged one a glyph may have been given.
    private func placements(of bodies: [ChartWheelBody], on ring: Ring) -> [String: Placement] {
        Dictionary(
            drawable(bodies).map { body in
                (
                    body.id,
                    Placement(
                        angle: WheelMath.angle(longitude: body.longitude, asc: asc),
                        outer: body.isPlanet ? ring.outer : ring.points,
                        inner: body.isPlanet ? ring.inner : ring.pointsInner
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Where an aspect line to one of the angles ends: on that axis, just
    /// inside the rim, where the axis line itself begins. Everything else on
    /// the wheel sits further in, so a line to an angle always leaves the
    /// zodiac band inward and lands along the arrow it names.
    private func axisPlacements(_ metrics: Metrics) -> [String: Placement] {
        func placement(_ longitude: Double) -> Placement {
            Placement(
                angle: WheelMath.angle(longitude: longitude, asc: asc),
                outer: metrics.zodiacOuter,
                inner: metrics.zodiacInner
            )
        }

        var placements = ["ASC": placement(asc)]
        if let mc { placements["MC"] = placement(mc) }
        return placements
    }

    /// The band edge that faces `target`: outward when the other end is further
    /// out than this one, inward when it is closer to the centre.
    private func edge(
        of placement: Placement,
        facing target: CGPoint,
        from anchor: CGPoint,
        center: CGPoint,
        notch: CGFloat
    ) -> CGPoint {
        let outward = WheelMath.radialUnit(placement.angle)
        let projection = (target.x - anchor.x) * outward.x + (target.y - anchor.y) * outward.y
        let radius = projection > 0 ? placement.outer + notch : placement.inner - notch
        return WheelMath.point(center: center, radius: radius, angle: placement.angle)
    }

    private func stroke(
        from: CGPoint,
        to: CGPoint,
        style: AspectStyle,
        ink: Double,
        in context: GraphicsContext
    ) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(
            path,
            with: .color(palette.primary.opacity(style.ink * ink)),
            style: StrokeStyle(lineWidth: style.width, lineCap: .round, dash: style.dash)
        )
    }

    // MARK: - Drawing helpers

    /// The bodies that get a glyph: the angles are drawn as axes instead, and
    /// the special points come and go with the switch.
    private func drawable(_ bodies: [ChartWheelBody]) -> [ChartWheelBody] {
        bodies.filter { $0.id != "ASC" && $0.id != "MC" && (!hidesSpecialPoints || $0.isPlanet) }
    }

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

    // MARK: - Layout

    /// One pair of bands: planets outside, special points inside.
    private struct Ring {
        let outer: CGFloat
        let inner: CGFloat
        let points: CGFloat
        let pointsInner: CGFloat

        var mid: CGFloat { (outer + inner) / 2 }
        var pointsMid: CGFloat { (points + pointsInner) / 2 }
    }

    /// One body's place on a ring, for hanging an aspect line off.
    private struct Placement {
        let angle: Double
        let outer: CGFloat
        let inner: CGFloat

        var mid: CGFloat { (outer + inner) / 2 }
    }

    /// Every radius on the wheel, as a fraction of its width. The proportions
    /// come from the web ring so a chart looks like the same chart on both.
    private struct Metrics {

        let zodiacOuter: CGFloat
        let zodiacInner: CGFloat
        let zodiacBand: CGFloat
        let natalUpperOuter: CGFloat
        let natalUpperInner: CGFloat
        let natalLowerOuter: CGFloat
        let natalLowerInner: CGFloat
        let transitUpperOuter: CGFloat
        let transitUpperInner: CGFloat
        let transitLowerOuter: CGFloat
        let transitLowerInner: CGFloat
        let houseLabelRadius: CGFloat
        let tick: CGFloat
        let notch: CGFloat
        let arrow: CGFloat
        let axisLabelOffset: CGFloat
        let signGlyph: CGFloat
        let bodyGlyph: CGFloat
        let transitGlyph: CGFloat
        let houseLabel: CGFloat
        let axisLabel: CGFloat

        var zodiacMid: CGFloat { (zodiacOuter + zodiacInner) / 2 }

        /// The bands are thinner when the transit pair has to fit too: five
        /// rings in the same circle is a different budget from three.
        init(size: CGFloat, showsTransits: Bool, showsSpecialPoints: Bool) {
            let ring = max(size, 200)
            let padding = max(ring * 0.075, 26)

            zodiacOuter = ring / 2 - padding
            zodiacBand = max(ring * (showsTransits ? 0.046 : 0.052), 17)
            zodiacInner = zodiacOuter - zodiacBand

            let spacer = max(ring * (showsTransits ? 0.024 : 0.03), 9)
            let gap = max(ring * 0.011, 4)
            let bandWidth = max(ring * (showsTransits ? 0.044 : 0.05), 16)

            natalUpperOuter = zodiacInner - spacer
            natalUpperInner = natalUpperOuter - bandWidth
            natalLowerOuter = natalUpperInner - gap
            natalLowerInner = natalLowerOuter - bandWidth

            // With the inner rows off the transit pair starts higher up, so
            // it gets the room the special points would have taken.
            transitUpperOuter = (showsSpecialPoints ? natalLowerInner : natalUpperInner) - spacer
            transitUpperInner = transitUpperOuter - bandWidth
            transitLowerOuter = transitUpperInner - gap
            transitLowerInner = transitLowerOuter - bandWidth

            houseLabelRadius = zodiacInner - spacer / 2
            tick = max(ring * 0.008, 3)
            notch = max(ring * 0.006, 2)
            arrow = max(ring * 0.016, 5)
            axisLabelOffset = max(ring * 0.038, 13)

            signGlyph = max(ring * 0.036, 13)
            bodyGlyph = max(ring * (showsTransits ? 0.032 : 0.036), 13)
            transitGlyph = max(ring * 0.03, 12)
            houseLabel = max(ring * 0.024, 9)
            axisLabel = max(ring * 0.026, 10)
        }
    }
}

// MARK: - Building from a report

extension ChartWheelView {

    /// A transit report, ready to draw. Returns nil when the report has no
    /// ascendant, which is the one thing the wheel cannot do without.
    init?(
        positions: TransitPositions,
        aspects: [ActiveAspect],
        showsTransits: Bool,
        hidesSpecialPoints: Bool
    ) {
        guard let asc = positions.natal["ASC"]?.wheelLongitude else { return nil }

        self.asc = asc
        self.mc = positions.natal["MC"]?.wheelLongitude
        self.houses = positions.houses
        self.hidesSpecialPoints = hidesSpecialPoints
        self.bodies = Self.wheelBodies(positions.natal)
        self.natalAspects = positions.natalAspects

        if showsTransits {
            self.transits = Self.wheelBodies(positions.transiting)
            self.transitAspects = aspects
        }
    }

    private static func wheelBodies(_ positions: [String: ChartPosition]) -> [ChartWheelBody] {
        positions
            .compactMap { id, position in
                position.wheelLongitude.map { ChartWheelBody(id: id, longitude: $0) }
            }
            .sorted { TransitOrder.rank($0.id) < TransitOrder.rank($1.id) }
    }
}
