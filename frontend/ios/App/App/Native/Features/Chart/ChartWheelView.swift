import SwiftUI

/// One body on the wheel: where it is, and what to draw for it.
struct ChartWheelBody: Identifiable, Hashable {
    let id: String
    let longitude: Double

    var glyph: String { AstroGlyph.object(id) }
    /// Planets ride the outer row, points the inner one.
    var isPlanet: Bool { Zodiac.isPlanet(id) }
}

/// The natal chart, drawn as a dial.
///
/// Deliberately not a transcription of the web wheel. That one is a document:
/// curved sign names, hover tooltips, everything legible at desktop width. On
/// a phone the same rings have to read at a glance, so this follows the
/// instrument faces in Weather instead — fine ticks around the rim, upright
/// glyphs, hairlines, and no text that has to be chased around a curve.
///
/// One `Canvas` rather than a stack of shape views: forty ticks, twelve
/// dividers and a dozen glyphs as separate views is a layout pass the phone
/// does not need to do.
struct ChartWheelView: View {

    /// Ascendant. The whole wheel is rotated so it sits on the left horizon,
    /// so without it there is nothing to draw.
    let asc: Double
    var mc: Double?
    var houses: [Double] = []
    var bodies: [ChartWheelBody] = []
    /// Chiron, Lilith, the nodes and the parts, folded away.
    var hidesSpecialPoints = false

    @Environment(\.transitPalette) private var palette

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let metrics = Metrics(size: min(size.width, size.height))
            let origin = CGPoint(x: size.width / 2, y: size.height / 2)

            drawZodiac(in: context, metrics: metrics, center: origin)
            drawHouses(in: context, metrics: metrics, center: origin)
            drawBodies(in: context, metrics: metrics, center: origin)
            drawAxes(in: context, metrics: metrics, center: origin)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Birth chart wheel")
    }

    // MARK: - Zodiac ring

    private func drawZodiac(in context: GraphicsContext, metrics: Metrics, center: CGPoint) {
        context.stroke(
            circle(center: center, radius: metrics.zodiacMid),
            with: .color(palette.primary.opacity(0.08)),
            lineWidth: metrics.zodiacBand
        )
        hairline(context, center: center, radius: metrics.zodiacOuter, opacity: 0.4)
        hairline(context, center: center, radius: metrics.zodiacInner, opacity: 0.4)

        // Degree ticks: one every 5°, a taller brighter one on each sign
        // boundary. This is the part that makes it read as an instrument.
        for step in 0..<72 {
            let longitude = Double(step) * 5
            let angle = WheelMath.angle(longitude: longitude, asc: asc)
            let isBoundary = step % 6 == 0
            let length = isBoundary ? metrics.zodiacBand : metrics.tick

            var path = Path()
            path.move(to: WheelMath.point(center: center, radius: metrics.zodiacOuter, angle: angle))
            path.addLine(to: WheelMath.point(center: center, radius: metrics.zodiacOuter - length, angle: angle))
            context.stroke(
                path,
                with: .color(palette.primary.opacity(isBoundary ? 0.42 : 0.24)),
                lineWidth: isBoundary ? 1 : 0.75
            )
        }

        for index in 0..<12 {
            let angle = WheelMath.angle(longitude: Double(index) * 30 + 15, asc: asc)
            draw(
                Zodiac.glyphs[index],
                font: glyph(metrics.signGlyph),
                color: palette.secondary,
                at: WheelMath.point(center: center, radius: metrics.zodiacMid, angle: angle),
                in: context
            )
        }
    }

    // MARK: - House ring

    private func drawHouses(in context: GraphicsContext, metrics: Metrics, center: CGPoint) {
        context.stroke(
            circle(center: center, radius: metrics.upperMid),
            with: .color(palette.primary.opacity(0.06)),
            lineWidth: metrics.bandWidth
        )
        hairline(context, center: center, radius: metrics.upperOuter, opacity: 0.26)
        hairline(context, center: center, radius: metrics.upperInner, opacity: 0.26)

        if !hidesSpecialPoints {
            context.stroke(
                circle(center: center, radius: metrics.lowerMid),
                with: .color(palette.primary.opacity(0.06)),
                lineWidth: metrics.bandWidth
            )
            hairline(context, center: center, radius: metrics.lowerOuter, opacity: 0.26)
            hairline(context, center: center, radius: metrics.lowerInner, opacity: 0.26)
        }

        guard houses.count == 12 else { return }

        for (index, cusp) in houses.enumerated() {
            let angle = WheelMath.angle(longitude: cusp, asc: asc)

            var path = Path()
            path.move(to: WheelMath.point(center: center, radius: metrics.upperOuter, angle: angle))
            path.addLine(to: WheelMath.point(center: center, radius: metrics.upperInner, angle: angle))
            if !hidesSpecialPoints {
                path.move(to: WheelMath.point(center: center, radius: metrics.lowerOuter, angle: angle))
                path.addLine(to: WheelMath.point(center: center, radius: metrics.lowerInner, angle: angle))
            }
            context.stroke(path, with: .color(palette.primary.opacity(0.3)), lineWidth: 0.75)

            // The number goes in the gap above the band, halfway across the
            // house it belongs to rather than on its cusp.
            let next = houses[(index + 1) % houses.count]
            let midAngle = WheelMath.angle(
                longitude: WheelMath.midpoint(from: cusp, to: next),
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

    // MARK: - Bodies

    private func drawBodies(in context: GraphicsContext, metrics: Metrics, center: CGPoint) {
        let drawn = bodies.filter { body in
            body.id != "ASC" && body.id != "MC" && (!hidesSpecialPoints || body.isPlanet)
        }
        guard !drawn.isEmpty else { return }

        let rows = [
            (bodies: drawn.filter(\.isPlanet), outer: metrics.upperOuter, inner: metrics.upperInner, mid: metrics.upperMid),
            (bodies: drawn.filter { !$0.isPlanet }, outer: metrics.lowerOuter, inner: metrics.lowerInner, mid: metrics.lowerMid),
        ]

        for row in rows where !row.bodies.isEmpty {
            let placed = WheelMath.spread(
                markers: row.bodies.map { ($0.id, $0.longitude, $0.glyph) },
                asc: asc,
                radius: row.mid,
                glyphSize: metrics.bodyGlyph
            )

            for body in placed {
                // The tick stays on the true longitude even when the glyph
                // had to move, so the position is never a lie.
                var ticks = Path()
                ticks.move(to: WheelMath.point(center: center, radius: row.outer, angle: body.angle))
                ticks.addLine(to: WheelMath.point(center: center, radius: row.outer + metrics.tick, angle: body.angle))
                ticks.move(to: WheelMath.point(center: center, radius: row.inner, angle: body.angle))
                ticks.addLine(to: WheelMath.point(center: center, radius: row.inner - metrics.tick, angle: body.angle))
                context.stroke(ticks, with: .color(palette.primary.opacity(0.45)), lineWidth: 1)

                draw(
                    body.glyph,
                    font: glyph(metrics.bodyGlyph),
                    color: palette.primary,
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
            context.stroke(line, with: .color(palette.primary.opacity(0.7)), lineWidth: 1)

            if axis.chevron {
                let base = WheelMath.point(center: center, radius: metrics.zodiacOuter - metrics.arrow, angle: angle)
                let tangent = WheelMath.tangentUnit(angle)
                var chevron = Path()
                chevron.move(to: CGPoint(
                    x: base.x + tangent.x * metrics.arrow,
                    y: base.y + tangent.y * metrics.arrow
                ))
                chevron.addLine(to: tip)
                chevron.addLine(to: CGPoint(
                    x: base.x - tangent.x * metrics.arrow,
                    y: base.y - tangent.y * metrics.arrow
                ))
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
                at: WheelMath.point(
                    center: center,
                    radius: metrics.zodiacOuter + metrics.axisLabelOffset,
                    angle: angle
                ),
                in: context
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

    private func hairline(
        _ context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        opacity: Double
    ) {
        context.stroke(
            circle(center: center, radius: radius),
            with: .color(palette.primary.opacity(opacity)),
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

    /// Every radius on the wheel, as a fraction of its width. The proportions
    /// come from the web ring so a chart looks like the same chart on both.
    private struct Metrics {

        let zodiacOuter: CGFloat
        let zodiacInner: CGFloat
        let zodiacBand: CGFloat
        let upperOuter: CGFloat
        let upperInner: CGFloat
        let lowerOuter: CGFloat
        let lowerInner: CGFloat
        let bandWidth: CGFloat
        let houseLabelRadius: CGFloat
        let tick: CGFloat
        let arrow: CGFloat
        let axisLabelOffset: CGFloat
        let signGlyph: CGFloat
        let bodyGlyph: CGFloat
        let houseLabel: CGFloat
        let axisLabel: CGFloat

        var zodiacMid: CGFloat { (zodiacOuter + zodiacInner) / 2 }
        var upperMid: CGFloat { (upperOuter + upperInner) / 2 }
        var lowerMid: CGFloat { (lowerOuter + lowerInner) / 2 }

        init(size: CGFloat) {
            let ring = max(size, 200)
            let padding = max(ring * 0.075, 26)

            zodiacOuter = ring / 2 - padding
            zodiacBand = max(ring * 0.052, 20)
            zodiacInner = zodiacOuter - zodiacBand

            let spacer = max(ring * 0.03, 12)
            let gap = max(ring * 0.012, 5)
            bandWidth = max(ring * 0.05, 19)

            upperOuter = zodiacInner - spacer
            upperInner = upperOuter - bandWidth
            lowerOuter = upperInner - gap
            lowerInner = lowerOuter - bandWidth

            houseLabelRadius = zodiacInner - spacer / 2
            tick = max(ring * 0.008, 3)
            arrow = max(ring * 0.016, 5)
            axisLabelOffset = max(ring * 0.038, 13)

            signGlyph = max(ring * 0.038, 14)
            bodyGlyph = max(ring * 0.036, 14)
            houseLabel = max(ring * 0.024, 9)
            axisLabel = max(ring * 0.026, 10)
        }
    }
}

// MARK: - Building from a report

extension ChartWheelView {

    /// The natal side of a transit report, ready to draw. Returns nil when the
    /// report has no ascendant, which is the one thing the wheel cannot do
    /// without.
    init?(positions: TransitPositions, hidesSpecialPoints: Bool = false) {
        guard let asc = positions.natal["ASC"]?.wheelLongitude else { return nil }

        self.asc = asc
        self.mc = positions.natal["MC"]?.wheelLongitude
        self.houses = positions.houses
        self.hidesSpecialPoints = hidesSpecialPoints
        self.bodies = positions.natal
            .compactMap { id, position in
                guard let longitude = position.wheelLongitude else { return nil }
                return ChartWheelBody(id: id, longitude: longitude)
            }
            .sorted { TransitOrder.rank($0.id) < TransitOrder.rank($1.id) }
    }
}
