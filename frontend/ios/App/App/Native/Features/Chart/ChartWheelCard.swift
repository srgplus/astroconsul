import SwiftUI

/// The birth chart, on the weather screen, in the same frosted panel the
/// forecast and the transits use.
///
/// The switch mirrors the web chart's: off, the wheel drops Chiron, Lilith,
/// the nodes and the parts, and the inner row of glyphs goes with them. On a
/// phone that is the difference between a readable chart and a smudge, so it
/// starts off.
struct ChartWheelCard: View {

    let positions: TransitPositions

    @State private var showsSpecialPoints = false

    var body: some View {
        if let wheel = ChartWheelView(positions: positions, hidesSpecialPoints: !showsSpecialPoints) {
            WeatherCard {
                header

                wheel
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .animation(.easeInOut(duration: 0.2), value: showsSpecialPoints)
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

            Spacer(minLength: 8)

            Text("Special points")
                .font(.system(size: 13, design: .rounded))

            SmallSwitch(isOn: $showsSpecialPoints)
                .accessibilityLabel("Special points")
        }
        .foregroundStyle(.white.opacity(0.7))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { showsSpecialPoints.toggle() }
        }
    }
}
