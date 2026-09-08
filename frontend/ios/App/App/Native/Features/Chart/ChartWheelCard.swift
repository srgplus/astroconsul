import SwiftUI

/// Birth or Transit rings — which grid the wheel draws, and what the switch
/// under the title says.
///
/// Top level rather than nested in the card: the full-screen wheel carries the
/// same switch, and both read it from the same binding.
enum ChartMode: String, CaseIterable, Identifiable {
    case chart, transit

    var id: String { rawValue }

    /// "Birth", not "Chart": the card is already called Birth chart, and a
    /// button repeating the second half of the title says nothing about what
    /// it switches to.
    var title: String { L(self == .chart ? "wheel.natal" : "wheel.transit") }
}

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
///
/// A card is as wide as the screen minus two sets of margins, so the wheel in
/// it is about 270 points across and a glyph on it is thirteen. That is a
/// summary, not something to read a chart off, so any tap that lands on
/// nothing — the empty middle, the header, the margin around the rings —
/// opens `ChartFullScreenView`, which draws the same wheel across the whole
/// screen and lets it be pinched.
struct ChartWheelCard: View {

    let positions: TransitPositions
    var aspects: [ActiveAspect] = []
    /// The moment the reading was cast for. The detail sheet marks it on the
    /// transit's window, so it follows a day the reader picked.
    var now: Date = Date()
    /// The sky this card is floating on, so the full-screen wheel can stand on
    /// the same one frosted rather than on a slab of grey.
    var state: SkyState = .flowing

    @ObservedObject private var strings = L10n.shared

    /// The two switches and the selection live here and are handed to the
    /// full-screen wheel as bindings: the same chart, in two sizes, not two
    /// charts that drift apart while one of them is covered.
    @State private var mode: ChartMode = .transit
    @State private var showsSpecialPoints = false
    @State private var selection: ChartWheelSelection?
    @State private var detail: ActiveAspect?
    @State private var isFullScreen = false

    private var chart: ChartWheelData? {
        ChartWheelData(
            positions: positions,
            aspects: aspects,
            mode: mode,
            showsSpecialPoints: showsSpecialPoints
        )
    }

    var body: some View {
        if let chart {
            WeatherCard {
                header

                ChartWheelView(chart: chart, selection: $selection) {
                    isFullScreen = true
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .animation(.easeInOut(duration: 0.25), value: mode)
                .animation(.easeInOut(duration: 0.25), value: showsSpecialPoints)

                WeatherCardDivider()

                ChartCaption(
                    chart: chart,
                    selection: selection,
                    onAspect: { detail = $0 },
                    onEmpty: { isFullScreen = true }
                )

                WeatherCardDivider()

                ChartSpecialPointsRow(isOn: $showsSpecialPoints)
                    .padding(.top, 12)
            }
            // Everything the rows above do not claim: the header line and the
            // margin around the wheel.
            .contentShape(Rectangle())
            .onTapGesture { isFullScreen = true }
            // A selection is a position on a ring, so it cannot survive the
            // rings being rebuilt: the body may not be drawn any more, and if
            // it is, it has moved. The rule lives here and not in the
            // full-screen wheel because this card owns the state — it stays
            // mounted under the cover, so its observers still run.
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
            .fullScreenCover(isPresented: $isFullScreen) {
                ChartFullScreenView(
                    positions: positions,
                    aspects: aspects,
                    now: now,
                    state: state,
                    mode: $mode,
                    showsSpecialPoints: $showsSpecialPoints,
                    selection: $selection
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
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.white.opacity(0.7))

            Spacer(minLength: 8)

            ChartModePicker(mode: $mode)

            // The tap on the wheel's empty middle is the shortcut; this is the
            // part that says the shortcut is there.
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .onTapGesture { isFullScreen = true }
                .accessibilityLabel(L("chart.openFullScreen"))
                .accessibilityAddTraits(.isButton)
        }
        .foregroundStyle(.white.opacity(0.7))
    }
}

// MARK: - Shared pieces

extension ChartWheelData {

    /// The chart the card's two switches ask for. Both surfaces build it the
    /// same way, so neither can draw a combination the other cannot.
    init?(
        positions: TransitPositions,
        aspects: [ActiveAspect],
        mode: ChartMode,
        showsSpecialPoints: Bool
    ) {
        self.init(
            positions: positions,
            aspects: aspects,
            showsTransits: mode == .transit,
            hidesSpecialPoints: !showsSpecialPoints
        )
    }
}

/// What the last tap landed on, or how to make one.
///
/// This is the phone's answer to the web ring's hover tooltip. It sits under
/// the wheel rather than in the middle of it because the middle is only about
/// seventy points across once five rings are drawn, and a readout that fits
/// there in one combination is clipped in another.
struct ChartCaption: View {

    let chart: ChartWheelData
    let selection: ChartWheelSelection?
    /// What the line says with nothing selected. Nil takes the plain hint;
    /// the full-screen wheel passes its own, which also names the pinch.
    var hint: String?
    /// Only a transit aspect has a sheet: it is the only thing the caption
    /// names that the report gives a window and a meaning for.
    var onAspect: (ActiveAspect) -> Void = { _ in }
    /// Tapped with nothing to open. On the card that is one more piece of
    /// empty surface, and empty surface goes full screen.
    var onEmpty: (() -> Void)?

    var body: some View {
        let readout = ChartWheelReadout(selection: selection, chart: chart, hint: hint)

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
            if let aspect = readout.aspect {
                onAspect(aspect)
            } else {
                onEmpty?()
            }
        }
        .animation(.easeOut(duration: 0.15), value: readout.text)
    }
}

/// Chiron, Lilith, the nodes and the parts: the inner row of each pair of
/// rings, on one switch.
struct ChartSpecialPointsRow: View {

    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(L("chart.specialPoints"))
                .font(.system(size: 14, design: .rounded))

            Spacer(minLength: 8)

            SmallSwitch(isOn: $isOn)
                .accessibilityLabel(L("chart.specialPoints"))
        }
        .foregroundStyle(.white.opacity(0.7))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { isOn.toggle() }
        }
    }
}

/// Birth or Transit, as the web chart's segmented control — small enough to
/// live on a card's header line.
struct ChartModePicker: View {

    @Binding var mode: ChartMode

    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ChartMode.allCases) { option in
                let isSelected = option == mode

                Text(option.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    // "Рождение" is half again as long as "Birth" and was
                    // breaking across two lines inside its own capsule.
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(isSelected ? Color.black.opacity(0.8) : .white.opacity(0.75))
                    .padding(.horizontal, 10)
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
        .fixedSize()
    }
}

// MARK: - Readout

/// One selection, spelled out for the caption.
struct ChartWheelReadout {

    let text: String
    /// The aspect the caption can open a sheet for, if any.
    let aspect: ActiveAspect?

    init(selection: ChartWheelSelection?, chart: ChartWheelData, hint: String? = nil) {
        let hint = hint ?? L("chart.tapHint")
        switch selection {
        case nil:
            text = hint
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
