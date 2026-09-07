import SwiftUI

/// The 10-day list. Each row places the day's TII on the 0…100 index, and the
/// header carries the window's low and high, so the reader sees both the day
/// and the shape of the ten.
struct ForecastCard: View {

    let days: [ForecastDay]
    let low: Double
    let high: Double
    /// The zone the reading is cast in, so "Today" means today there.
    var zone: TimeZone = .current

    /// Tapping a row opens that day. Left unset the rows are just rows.
    var onSelect: ((ForecastDay) -> Void)?

    @ObservedObject private var strings = L10n.shared

    var body: some View {
        // Once per draw, not once per row.
        let today = ForecastDay.todayKey(in: zone)

        return WeatherCard {
            WeatherCardHeader(
                icon: "calendar",
                title: L("weather.forecastTitle", days.count),
                trailing: "\(Int(low.rounded()))–\(Int(high.rounded()))"
            )
            .padding(.bottom, 10)

            ForEach(days) { day in
                WeatherCardDivider()

                row(day, isToday: day.date == today)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    // A tap gesture rather than a Button: inside the pager's
                    // scroll view a plain-styled Button never fires, which is
                    // why the transit rows above are wired the same way.
                    .onTapGesture { onSelect?(day) }
            }
        }
    }

    private func row(_ day: ForecastDay, isToday: Bool) -> some View {
        HStack(spacing: 10) {
            Text(day.label(isToday: isToday))
                .font(.system(size: 17, weight: isToday ? .semibold : .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                // Wide enough for the longest label the column ever holds —
                // "Today" in Russian is "Сегодня", which wrapped to two lines
                // at 58 and made the first row taller than the other nine.
                // Weekday names need half of this; the scale factor is only
                // there so a future language is squeezed rather than wrapped.
                .frame(width: 72, alignment: .leading)

            Image(systemName: FeelsLike.symbol(for: day.feelsLike))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 17))
                .frame(width: 26)

            ForecastBar(value: day.tii, zone: day.zone)

            Text("\(Int(day.tii.rounded()))")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                // Narrower than it was: the column no longer has a ° to hold,
                // and the space it kept for one belongs to the bar.
                .frame(width: 38, alignment: .trailing)

            // The day's tension, kept quiet: it is a second reading beside
            // the index, not a warning, so it is small and off-white rather
            // than coloured. The column stays even when a day has no ratio,
            // so the ten numbers keep their right edge.
            Text(Self.percent(day.tensionRatio))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .frame(width: 30, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y(day, isToday: isToday))
        .accessibilityAddTraits(onSelect == nil ? [] : .isButton)
    }

    /// The ratio as whole percent. Blank rather than "0%" when the day came
    /// without one, so a missing reading is not printed as a calm one.
    private static func percent(_ ratio: Double?) -> String {
        guard let ratio else { return "" }
        return "\(Int((min(max(ratio, 0), 1) * 100).rounded()))%"
    }

    private func a11y(_ day: ForecastDay, isToday: Bool) -> String {
        var parts = [
            day.label(isToday: isToday),
            Astro.feels(day.feelsLike) ?? day.feelsLike,
            L("weather.intensityValue", Int(day.tii.rounded())),
        ]
        if let ratio = day.tensionRatio {
            parts.append(L("weather.tensionA11y", Int((min(max(ratio, 0), 1) * 100).rounded())))
        }
        return parts.joined(separator: ", ")
    }

}

/// Track spanning the whole index, filled up to this day's value.
///
/// The scale is 0…100 and not the window's low…high. A window scale draws the
/// quietest of the ten days as an empty track and the loudest as a full one,
/// whatever the two readings are — so a 79 beside an untouched bar read as a
/// zero, and five days at 100 read as one day repeated. On the index the fill
/// says the same thing as the number printed next to it, and as the intensity
/// meter on the day's own screen, which was always on 0…100.
struct ForecastBar: View {

    let value: Double
    let zone: TiiZone

    /// The TII's ceiling. `TiiZone` bands the same range.
    private let scale: Double = 100

    private let track: CGFloat = 5
    private let dot: CGFloat = 9

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = min(max(value / scale, 0), 1)
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
