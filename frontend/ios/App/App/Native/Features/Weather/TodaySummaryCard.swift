import SwiftUI

/// The block under the hero — Weather's "Rainy conditions expected…" card.
/// The sentence comes from the strongest transit of the day, the rows under it
/// name the three transits carrying today's TII.
struct TodaySummaryCard: View {

    let day: ForecastDay

    private var top: [TopTransit] { day.topTransits ?? [] }

    var body: some View {
        WeatherCard {
            Text(sentence)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            if !top.isEmpty {
                WeatherCardDivider()

                ForEach(top) { transit in
                    transitRow(transit)
                        .padding(.vertical, 9)
                }
            }

            if !conditions.isEmpty {
                WeatherCardDivider()

                HStack(spacing: 14) {
                    ForEach(conditions, id: \.self) { condition in
                        Text(condition)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 10)
            }
        }
    }

    private func transitRow(_ transit: TopTransit) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(transit.title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            if let strength = transit.strength {
                Text(strength.capitalized)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }

            if let orb = transit.orb {
                Text(String(format: "%.1f°", orb))
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
            }
        }
    }

    /// The engine writes a meaning for most aspects; when it does not, name the
    /// transit rather than showing an empty card.
    private var sentence: String {
        if let meaning = top.first?.meaning, !meaning.isEmpty {
            return meaning
        }
        if let title = top.first?.title {
            return "\(title) is the strongest influence today."
        }
        return "No strong transits today — a quiet sky."
    }

    /// The Moon used to sit here as a chip. It has its own panel now, so all
    /// that is left of this row is the retrograde count.
    private var conditions: [String] {
        var items: [String] = []

        if let count = day.retrogradeCount, count > 0 {
            items.append("℞ \(count) retrograde")
        }

        return items
    }
}
