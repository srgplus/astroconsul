import SwiftUI

/// The birth chart, on the weather screen, in the same frosted panel the
/// forecast and the transits use.
///
/// Two controls, both borrowed from the web chart. Chart/Transit adds the
/// second pair of rings and the transit-to-natal lines; Special points adds
/// the inner row of each pair — Chiron, Lilith, the nodes, the parts. All four
/// combinations are drawable, from two rings to five.
///
/// Transit is the opening view: this card sits on the cosmic weather screen,
/// and what is happening now is why anyone scrolled this far.
struct ChartWheelCard: View {

    let positions: TransitPositions
    var aspects: [ActiveAspect] = []

    @State private var mode: Mode = .transit
    @State private var showsSpecialPoints = false

    enum Mode: String, CaseIterable, Identifiable {
        case chart, transit

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var body: some View {
        if let wheel = ChartWheelView(
            positions: positions,
            aspects: aspects,
            showsTransits: mode == .transit,
            hidesSpecialPoints: !showsSpecialPoints
        ) {
            WeatherCard {
                header

                wheel
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .animation(.easeInOut(duration: 0.25), value: mode)
                    .animation(.easeInOut(duration: 0.25), value: showsSpecialPoints)

                WeatherCardDivider()

                specialPointsRow
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dotted.circle")
                .font(.system(size: 12, weight: .semibold))

            Text("Birth chart".uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.7))

            Spacer(minLength: 8)

            ModePicker(mode: $mode)
        }
        .foregroundStyle(.white.opacity(0.7))
    }

    private var specialPointsRow: some View {
        HStack(spacing: 8) {
            Text("Special points")
                .font(.system(size: 14, design: .rounded))

            Spacer(minLength: 8)

            SmallSwitch(isOn: $showsSpecialPoints)
                .accessibilityLabel("Special points")
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.top, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { showsSpecialPoints.toggle() }
        }
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
