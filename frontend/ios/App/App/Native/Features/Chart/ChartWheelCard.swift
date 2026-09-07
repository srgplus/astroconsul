import SwiftUI

/// The birth chart, on the weather screen, in the same frosted panel the
/// forecast and the transits use.
///
/// Two switches, both borrowed from the web chart. Birth/Transit adds the
/// second pair of rings and swaps the natal aspect grid for the
/// transit-to-natal lines — one grid at a time, because both at once is fifty
/// lines through one circle; Special points adds the inner row of each pair —
/// Chiron, Lilith, the nodes, the parts. All four combinations are drawable,
/// from two rings to five.
///
/// Transit is the opening view: this card sits on the cosmic weather screen,
/// and what is happening now is why anyone scrolled this far.
struct ChartWheelCard: View {

    let positions: TransitPositions
    var aspects: [ActiveAspect] = []
    /// The moment the reading was cast for. The detail sheet marks it on the
    /// transit's window, so it follows a day the reader picked.
    var now: Date = Date()

    @ObservedObject private var strings = L10n.shared

    @State private var mode: Mode = .transit
    @State private var showsSpecialPoints = false
    @State private var selection: ChartWheelSelection?
    @State private var detail: ActiveAspect?

    enum Mode: String, CaseIterable, Identifiable {
        case chart, transit

        var id: String { rawValue }

        /// "Birth", not "Chart": the card is already called Birth chart, and a
        /// button repeating the second half of the title says nothing about
        /// what it switches to.
        var title: String { L(self == .chart ? "wheel.natal" : "wheel.transit") }
    }

    private var chart: ChartWheelData? {
        ChartWheelData(
            positions: positions,
            aspects: aspects,
            showsTransits: mode == .transit,
            hidesSpecialPoints: !showsSpecialPoints
        )
    }

    var body: some View {
        if let chart {
            WeatherCard {
                header

                ChartWheelView(chart: chart, selection: $selection)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .animation(.easeInOut(duration: 0.25), value: mode)
                    .animation(.easeInOut(duration: 0.25), value: showsSpecialPoints)

                WeatherCardDivider()

                caption(chart)

                WeatherCardDivider()

                specialPointsRow
            }
            // A selection is a position on a ring, so it cannot survive the
            // rings being rebuilt: the body may not be drawn any more, and if
            // it is, it has moved.
            .onChange(of: mode) { selection = nil }
            .onChange(of: showsSpecialPoints) { selection = nil }
            .sheet(item: $detail) { aspect in
                TransitDetailSheet(
                    aspect: aspect,
                    isRetrograde: positions.transiting[aspect.transitObject]?.retrograde == true,
                    positions: positions,
                    now: now
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dotted.circle")
                .font(.system(size: 12, weight: .semibold))

            Text(L("chart.title").uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.7))

            Spacer(minLength: 8)

            ModePicker(mode: $mode)
        }
        .foregroundStyle(.white.opacity(0.7))
    }

    /// What the last tap landed on, or how to make one.
    ///
    /// This is the phone's answer to the web ring's hover tooltip. It sits
    /// under the wheel rather than in the middle of it because the middle is
    /// only about seventy points across once five rings are drawn, and a
    /// readout that fits there in one combination is clipped in another.
    @ViewBuilder
    private func caption(_ chart: ChartWheelData) -> some View {
        let readout = ChartWheelReadout(selection: selection, chart: chart)

        HStack(spacing: 8) {
            Text(readout.text)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(selection == nil ? 0.45 : 0.95))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if readout.aspect != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(minHeight: 34)
        .contentShape(Rectangle())
        .onTapGesture {
            // Only a transit aspect has a sheet: it is the only one the report
            // gives a window and a meaning for.
            if let aspect = readout.aspect { detail = aspect }
        }
        .animation(.easeOut(duration: 0.15), value: readout.text)
    }

    private var specialPointsRow: some View {
        HStack(spacing: 8) {
            Text(L("chart.specialPoints"))
                .font(.system(size: 14, design: .rounded))

            Spacer(minLength: 8)

            SmallSwitch(isOn: $showsSpecialPoints)
                .accessibilityLabel(L("chart.specialPoints"))
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.top, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { showsSpecialPoints.toggle() }
        }
    }
}

/// One selection, spelled out for the caption.
struct ChartWheelReadout {

    let text: String
    /// The aspect the caption can open a sheet for, if any.
    let aspect: ActiveAspect?

    init(selection: ChartWheelSelection?, chart: ChartWheelData) {
        switch selection {
        case nil:
            text = L("chart.tapHint")
            aspect = nil

        case let .body(body, isTransit):
            text = Self.position(of: body, isTransit: isTransit, chart: chart)
            aspect = nil

        case let .natalAspect(natal):
            text = Self.pair(natal.p1, natal.aspect, natal.p2, orb: natal.orb)
            aspect = nil

        case let .transitAspect(transit):
            text = Self.pair(transit.transitObject, transit.aspect, transit.natalObject, orb: transit.orb)
            aspect = transit
        }
    }

    /// "Transit ♀ Venus · 23°16′ ♉ Taurus · House 1"
    private static func position(of body: ChartWheelBody, isTransit: Bool, chart: ChartWheelData) -> String {
        let sign = Zodiac.index(ofLongitude: body.longitude)
        let inSign = Zodiac.normalize(body.longitude).truncatingRemainder(dividingBy: 30)

        // Which ring it came from only needs saying when both are on screen.
        var parts: [String] = []
        if chart.showsTransits {
            parts.append(L(isTransit ? "chart.transit" : "chart.natal"))
        }
        parts.append("\(body.glyph) \(Astro.object(body.id))")
        parts.append(
            "\(degrees(inSign)) \(Zodiac.glyphs[sign]) \(Astro.sign(Zodiac.names[sign]) ?? Zodiac.names[sign])"
        )

        if let house = WheelMath.house(of: body.longitude, cusps: chart.houses) {
            parts.append(L("chart.house", house))
        }
        if body.isRetrograde {
            parts.append("\u{211E}")
        }

        return parts.joined(separator: " · ")
    }

    /// "♄ □ ☽ · Square · orb 1°14′"
    private static func pair(_ first: String, _ aspect: String, _ second: String, orb: Double) -> String {
        let glyphs = "\(AstroGlyph.object(first)) \(AstroGlyph.aspect(aspect)) \(AstroGlyph.object(second))"
        return "\(glyphs) · \(Astro.aspect(aspect).capitalized) · \(L("chart.orb", degrees(orb)))"
    }

    /// 23°16′, the form the rest of the app prints.
    private static func degrees(_ value: Double) -> String {
        let degree = Int(value)
        let minute = Int(((value - Double(degree)) * 60).rounded())
        return minute == 60
            ? "\(degree + 1)°00′"
            : "\(degree)°\(String(format: "%02d", minute))′"
    }
}

/// Chart or Transit, as the web chart's segmented control — small enough to
/// live on the card's header line.
private struct ModePicker: View {

    @Binding var mode: ChartWheelCard.Mode

    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ChartWheelCard.Mode.allCases) { option in
                let isSelected = option == mode

                Text(option.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.8) : .white.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.white.opacity(0.92))
                                .matchedGeometryEffect(id: "mode", in: selection)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.22)) { mode = option }
                    }
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.16)))
    }
}
