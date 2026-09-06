import SwiftUI

/// The 10-day list. Each row places the day's TII on the shared scale of the
/// whole window, so the reader sees which days stand out at a glance.
struct ForecastCard: View {

    let days: [ForecastDay]
    let low: Double
    let high: Double

    var body: some View {
        WeatherCard {
            WeatherCardHeader(
                icon: "calendar",
                title: "\(days.count)-day forecast",
                trailing: "\(Int(low.rounded()))°–\(Int(high.rounded()))°"
            )
            .padding(.bottom, 10)

            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                WeatherCardDivider()

                row(day, isToday: index == 0)
                    .padding(.vertical, 9)
            }
        }
    }

    private func row(_ day: ForecastDay, isToday: Bool) -> some View {
        HStack(spacing: 10) {
            Text(day.label(isToday: isToday))
                .font(.system(size: 17, weight: isToday ? .semibold : .medium, design: .rounded))
                .frame(width: 58, alignment: .leading)

            Image(systemName: FeelsLike.symbol(for: day.feelsLike))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 17))
                .frame(width: 26)

            ForecastBar(value: day.tii, low: low, high: high, zone: day.zone)

            Text("\(Int(day.tii.rounded()))°")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .frame(width: 44, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(day.label(isToday: isToday)), \(day.feelsLike), TII \(Int(day.tii.rounded()))")
    }

}

/// Track spanning the forecast's low…high, filled up to this day's value.
struct ForecastBar: View {

    let value: Double
    let low: Double
    let high: Double
    let zone: TiiZone

    private let track: CGFloat = 5
    private let dot: CGFloat = 9

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let span = max(high - low, 1)
            let fraction = min(max((value - low) / span, 0), 1)
            let filled = max(width * fraction, track)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: track)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [WeatherSky.accent(for: .quiet), WeatherSky.accent(for: zone)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: filled, height: track)

                Circle()
                    .fill(.white)
                    .frame(width: dot, height: dot)
                    .offset(x: min(max(filled - dot / 2, 0), width - dot))
            }
            .frame(height: geometry.size.height, alignment: .center)
        }
        .frame(height: dot)
    }
}
