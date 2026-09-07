import SwiftUI

/// The chart a wheel draws. Everything is already in ecliptic longitude, so
/// this is the last place that knows what a planet is; below it there are only
/// angles and radii.
struct ChartWheelData: Equatable {

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

    var showsTransits: Bool { !transits.isEmpty }

    /// The bodies that get a glyph: the angles are drawn as axes instead, and
    /// the special points come and go with the switch.
    func drawable(_ bodies: [ChartWheelBody]) -> [ChartWheelBody] {
        bodies.filter { $0.id != "ASC" && $0.id != "MC" && (!hidesSpecialPoints || $0.isPlanet) }
    }

    func angle(of longitude: Double) -> Double {
        WheelMath.angle(longitude: longitude, asc: asc)
    }
}

/// What a tap on the wheel landed on.
enum ChartWheelSelection: Equatable {
    case body(ChartWheelBody, isTransit: Bool)
    case natalAspect(NatalAspect)
    case transitAspect(ActiveAspect)
}

/// Everything the wheel puts on screen, positioned.
///
/// Built once per size, then read both by the drawing and by the tap handler.
/// Working the geometry out twice — once inside the `Canvas` closure and once
/// inside the gesture — is how you end up with a wheel whose glyphs sit half a
/// degree from where they can be tapped, and nothing in either copy looks
/// wrong on its own.
struct WheelLayout {

    /// One body, where it is drawn and where it can be hit.
    struct Glyph {
        let body: ChartWheelBody
        let isTransit: Bool
        /// Where the glyph is drawn. Not always its true angle: a crowded row
        /// nudges glyphs apart, and the tap follows the glyph, not the tick.
        let point: CGPoint
        /// The true angle, where the tick is.
        let angle: Double
        let bandOuter: CGFloat
        let bandInner: CGFloat
        let size: CGFloat
        let ink: Double
    }

    /// One aspect line, and what it stands for.
    struct Line {
        let from: CGPoint
        let to: CGPoint
        let style: AspectStyle
        let ink: Double
        let subject: ChartWheelSelection
    }

    let chart: ChartWheelData
    let center: CGPoint
    let metrics: Metrics
    let natalRing: Ring
    let transitRing: Ring
    let glyphs: [Glyph]
    /// Natal first, transits after, so a tap that lands between two lines
    /// takes the transit one — the natal grid is background once both are on.
    let lines: [Line]

    init(size: CGSize, chart: ChartWheelData) {
        self.chart = chart
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        metrics = Metrics(
            size: min(size.width, size.height),
            showsTransits: chart.showsTransits,
            showsSpecialPoints: !chart.hidesSpecialPoints
        )
        natalRing = Ring(
            outer: metrics.natalUpperOuter, inner: metrics.natalUpperInner,
            points: metrics.natalLowerOuter, pointsInner: metrics.natalLowerInner
        )
        transitRing = Ring(
            outer: metrics.transitUpperOuter, inner: metrics.transitUpperInner,
            points: metrics.transitLowerOuter, pointsInner: metrics.transitLowerInner
        )

        glyphs = Self.glyphs(chart: chart, center: center, metrics: metrics,
                             natalRing: natalRing, transitRing: transitRing)
        lines = Self.lines(chart: chart, center: center, metrics: metrics,
                           natalRing: natalRing, transitRing: transitRing)
    }

    // MARK: - Hit testing

    /// What is under `point`, or nil for the empty middle.
    ///
    /// Glyphs win over lines: they are the smaller target and the one people
    /// aim at, and every line ends at one anyway. Within each kind the nearest
    /// wins, so a tap between two crowded glyphs picks the closer of the two
    /// rather than whichever happens to be first.
    func hit(_ point: CGPoint) -> ChartWheelSelection? {
        // Wider than the glyph: a fingertip is 44 points and a glyph is 13,
        // and since the nearest wins, reaching past the neighbours costs
        // nothing but makes a tap between two of them land on one of them.
        let glyphReach = max(metrics.bodyGlyph, 22) * 0.75

        let glyph = glyphs
            .map { ($0, hypot(point.x - $0.point.x, point.y - $0.point.y)) }
            .filter { $0.1 <= glyphReach }
            .min { $0.1 < $1.1 }?
            .0

        if let glyph {
            return .body(glyph.body, isTransit: glyph.isTransit)
        }

        // Lines are thin, so their reach is generous; the nearest still wins,
        // and `lines` is ordered so a transit line beats a natal one at equal
        // distance.
        let line = lines
            .map { ($0, Self.distance(from: point, toSegmentFrom: $0.from, to: $0.to)) }
            .filter { $0.1 <= 10 }
            .min { $0.1 < $1.1 }?
            .0

        return line?.subject
    }

    /// Shortest distance from a point to a line segment, clamped at both ends
    /// so the reach around a short line is a capsule and not an infinite band.
    static func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy

        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }

    // MARK: - Building

    private static func glyphs(
        chart: ChartWheelData,
        center: CGPoint,
        metrics: Metrics,
        natalRing: Ring,
        transitRing: Ring
    ) -> [Glyph] {
        var result: [Glyph] = []

        for (bodies, ring, size, ink, isTransit) in [
            (chart.bodies, natalRing, metrics.bodyGlyph, 1.0, false),
            (chart.showsTransits ? chart.transits : [], transitRing, metrics.transitGlyph, 0.85, true),
        ] {
            let drawn = chart.drawable(bodies)
            guard !drawn.isEmpty else { continue }

            for row in [
                (bodies: drawn.filter(\.isPlanet), outer: ring.outer, inner: ring.inner, mid: ring.mid),
                (bodies: drawn.filter { !$0.isPlanet }, outer: ring.points, inner: ring.pointsInner, mid: ring.pointsMid),
            ] where !row.bodies.isEmpty {
                let placed = WheelMath.spread(
                    markers: row.bodies.map { ($0.id, $0.longitude, $0.glyph) },
                    asc: chart.asc,
                    radius: row.mid,
                    glyphSize: size
                )
                let byId = Dictionary(row.bodies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

                for spread in placed {
                    guard let body = byId[spread.id] else { continue }
                    result.append(
                        Glyph(
                            body: body,
                            isTransit: isTransit,
                            point: WheelMath.point(center: center, radius: row.mid, angle: spread.displayAngle),
                            angle: spread.angle,
                            bandOuter: row.outer,
                            bandInner: row.inner,
                            size: size,
                            ink: ink
                        )
                    )
                }
            }
        }

        return result
    }

    private static func lines(
        chart: ChartWheelData,
        center: CGPoint,
        metrics: Metrics,
        natalRing: Ring,
        transitRing: Ring
    ) -> [Line] {
        // The angles are drawn as arrows through the rim rather than glyphs on
        // a ring, so they need a place of their own or every aspect to them is
        // dropped — and a transit exact on the ascendant is the loudest line
        // in the report.
        let natal = placements(of: chart.bodies, on: natalRing, chart: chart)
            .merging(axisPlacements(chart: chart, metrics: metrics)) { body, _ in body }

        // Dimmed once transits are on. Both grids at full strength is fifty
        // lines through one circle, and on a phone that is a ball of wool —
        // the natal grid is the standing background, the transits are the news.
        let natalInk = chart.showsTransits ? 0.5 : 1.0
        var result: [Line] = []

        // Natal to natal: both ends sit just inside their own band, and the
        // line crosses whatever is in the middle, which is what the web does.
        for aspect in chart.natalAspects {
            guard let from = natal[aspect.p1], let to = natal[aspect.p2] else { continue }
            result.append(
                Line(
                    from: WheelMath.point(center: center, radius: from.inner - metrics.notch, angle: from.angle),
                    to: WheelMath.point(center: center, radius: to.inner - metrics.notch, angle: to.angle),
                    style: .named(aspect.aspect),
                    ink: natalInk * AspectStyle.ink(orb: aspect.orb),
                    subject: .natalAspect(aspect)
                )
            )
        }

        guard chart.showsTransits else { return result }
        let transiting = placements(of: chart.transits, on: transitRing, chart: chart)

        // Transit to natal: each end leaves from whichever of its two edges
        // faces the other end, so a line never has to cross its own band.
        for aspect in chart.transitAspects {
            guard let natalEnd = natal[aspect.natalObject],
                  let transitEnd = transiting[aspect.transitObject] else { continue }

            let natalMid = WheelMath.point(center: center, radius: natalEnd.mid, angle: natalEnd.angle)
            let transitMid = WheelMath.point(center: center, radius: transitEnd.mid, angle: transitEnd.angle)

            result.append(
                Line(
                    from: edge(of: natalEnd, facing: transitMid, from: natalMid, center: center, notch: metrics.notch),
                    to: edge(of: transitEnd, facing: natalMid, from: transitMid, center: center, notch: metrics.notch),
                    style: .named(aspect.aspect),
                    ink: AspectStyle.ink(orb: aspect.orb),
                    subject: .transitAspect(aspect)
                )
            )
        }

        return result
    }

    /// Where each drawn body sits on its ring, keyed by id. The true angle, not
    /// the nudged one a glyph may have been given.
    private static func placements(
        of bodies: [ChartWheelBody],
        on ring: Ring,
        chart: ChartWheelData
    ) -> [String: Placement] {
        Dictionary(
            chart.drawable(bodies).map { body in
                (
                    body.id,
                    Placement(
                        angle: chart.angle(of: body.longitude),
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
    private static func axisPlacements(chart: ChartWheelData, metrics: Metrics) -> [String: Placement] {
        func placement(_ longitude: Double) -> Placement {
            Placement(
                angle: chart.angle(of: longitude),
                outer: metrics.zodiacOuter,
                inner: metrics.zodiacInner
            )
        }

        var placements = ["ASC": placement(chart.asc)]
        if let mc = chart.mc { placements["MC"] = placement(mc) }
        return placements
    }

    /// The band edge that faces `target`: outward when the other end is further
    /// out than this one, inward when it is closer to the centre.
    private static func edge(
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

    // MARK: - Geometry

    /// One pair of bands: planets outside, special points inside.
    struct Ring {
        let outer: CGFloat
        let inner: CGFloat
        let points: CGFloat
        let pointsInner: CGFloat

        var mid: CGFloat { (outer + inner) / 2 }
        var pointsMid: CGFloat { (points + pointsInner) / 2 }
    }

    /// One body's place on a ring, for hanging an aspect line off.
    struct Placement {
        let angle: Double
        let outer: CGFloat
        let inner: CGFloat

        var mid: CGFloat { (outer + inner) / 2 }
    }

    /// Every radius on the wheel, as a fraction of its width. The proportions
    /// come from the web ring so a chart looks like the same chart on both.
    struct Metrics {

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

extension ChartWheelData {

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
                position.wheelLongitude.map {
                    ChartWheelBody(id: id, longitude: $0, isRetrograde: position.retrograde == true)
                }
            }
            .sorted { TransitOrder.rank($0.id) < TransitOrder.rank($1.id) }
    }
}
