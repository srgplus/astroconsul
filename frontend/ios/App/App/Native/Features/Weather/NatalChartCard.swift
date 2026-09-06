import SwiftUI

/// The birth chart behind every reading on this screen: where the seven points
/// the web app's Chart card names actually sit — sign, degrees, house, and ℞
/// for a body that was retrograde at birth.
///
/// It costs no extra request. The transit report that feeds Active Transits
/// already carries `natal_positions` and `angle_positions`, and the view model
/// indexes both into `TransitPositions.natal`.
struct NatalChartCard: View {

    let profile: ProfileSummary
    /// Natal positions by object id — `TransitPositions.natal`.
    let positions: [String: ChartPosition]

    /// The points the web app's Chart card names, in its order: the lights,
    /// then the angles, then the personal planets. Written out here because
    /// "ASC" and "MC" are ids, not something to show a reader.
    private static let points: [(id: String, name: String)] = [
        ("Sun", "Sun"),
        ("Moon", "Moon"),
        ("ASC", "Ascendant"),
        ("MC", "Midheaven"),
        ("Mercury", "Mercury"),
        ("Venus", "Venus"),
        ("Mars", "Mars"),
    ]

    private var rows: [(id: String, name: String, position: ChartPosition)] {
        Self.points.compactMap { point in
            guard let position = positions[point.id] else { return nil }
            return (point.id, point.name, position)
        }
    }

    var body: some View {
        if !rows.isEmpty {
            WeatherCard {
                WeatherCardHeader(icon: "circle.dotted", title: "Natal chart", trailing: age)
                    .padding(.bottom, 2)

                ForEach(rows, id: \.id) { row in
                    WeatherCardDivider()

                    positionRow(name: row.name, id: row.id, position: row.position)
                        .padding(.vertical, 10)
                }

                if birth != nil || profile.locationName != nil {
                    WeatherCardDivider()

                    birthLines
                        .padding(.top, 11)
                }
            }
        }
    }

    private func positionRow(name: String, id: String, position: ChartPosition) -> some View {
        HStack(spacing: 8) {
            Text(AstroGlyph.object(id))
                .font(.system(size: 15))
                .frame(width: 24, alignment: .leading)
                .accessibilityHidden(true)

            Text(name)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // Retrograde at birth, not today: the ℞ on the Active Transits
            // rows is about the transiting body, this one is part of the
            // chart and never changes.
            if position.retrograde == true {
                Text("\u{211E}")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize()
                    .accessibilityLabel("retrograde")
            }

            Spacer(minLength: 4)

            // Fixed columns rather than a run of `fixedSize` text: this is a
            // table, and the degrees and signs have to line up down the card.
            Text(position.formattedDegree ?? "—")
                .font(.system(size: 14, design: .rounded))
                .monospacedDigit()
                .frame(width: 58, alignment: .trailing)

            // Sign name, no glyph: U+2648-2653 resolve through the emoji font,
            // which the simulator draws as tofu and a device draws in colour.
            Text(position.sign ?? "—")
                .font(.system(size: 14, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 82, alignment: .leading)

            // Wide enough for a two-digit house: at 30 the "12" wrapped under
            // its own house symbol.
            house(for: id, position: position)
                .frame(width: 42, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    /// The angles are the cusps of houses 1 and 10 by definition, so a house
    /// number there would repeat the label. The column is still held open so
    /// the rows above and below stay in line.
    @ViewBuilder
    private func house(for id: String, position: ChartPosition) -> some View {
        if id != "ASC", id != "MC", let number = position.houseNumber {
            HStack(spacing: 3) {
                // A house symbol, not the web's △: that triangle is the glyph
                // for a trine, and this app draws trines elsewhere.
                Image(systemName: "house")
                    .font(.system(size: 11))

                Text("\(number)")
                    .font(.system(size: 13, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.7))
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("house \(number)")
        } else {
            Color.clear.frame(height: 1)
        }
    }

    private var birthLines: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let place = profile.locationName {
                Text(place)
                    .font(.system(size: 13, design: .rounded))
                    .lineLimit(2)
            }

            if let birth {
                Text([birth.date, birth.time].joined(separator: ", "))
                    .font(.system(size: 13, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.white.opacity(0.7))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Birth moment

    /// "1990-04-17T09:20:00" → ("17.04.1990", "09:20").
    ///
    /// Read as text, never parsed into a `Date`: the field is already the
    /// local birth moment, so any timezone conversion would move the clock
    /// away from the time on the birth certificate. It also survives the
    /// offset the backend sometimes appends ("…+03:00").
    private var birth: (date: String, time: String)? {
        guard let raw = profile.localBirthDatetime, raw.count >= 16 else { return nil }
        let parts = raw.split(separator: "T", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let ymd = parts[0].split(separator: "-")
        guard ymd.count == 3 else { return nil }

        return ("\(ymd[2]).\(ymd[1]).\(ymd[0])", String(parts[1].prefix(5)))
    }

    /// Whole years since the birth date, in the viewer's calendar. Nil when
    /// the profile carries no birth datetime, which is what a followed
    /// profile with private birth data looks like.
    private var age: String? {
        guard let raw = profile.localBirthDatetime else { return nil }
        let ymd = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard ymd.count == 3 else { return nil }

        let calendar = Calendar.current
        var components = DateComponents()
        components.year = ymd[0]
        components.month = ymd[1]
        components.day = ymd[2]

        guard let born = calendar.date(from: components),
              let years = calendar.dateComponents([.year], from: born, to: Date()).year,
              years >= 0
        else { return nil }

        return "\(years) years"
    }
}

#if DEBUG
#Preview {
    ZStack {
        WeatherSky.gradient(for: .active).ignoresSafeArea()

        NatalChartCard(
            profile: WeatherPreviewData.profile,
            positions: WeatherPreviewData.positions.natal
        )
        .padding(16)
    }
}
#endif
