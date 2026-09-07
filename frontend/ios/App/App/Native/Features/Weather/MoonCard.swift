import SwiftUI

/// The Moon, as its own panel — Weather's moon module, down to the shape of
/// it: the phase named in the header, a short column of readings, and the
/// sphere itself lit from the side on the right.
///
/// Where Weather prints moonrise and moonset, this prints the sign the Moon is
/// travelling through. Rise and set need a horizon, and the forecast is cast
/// for a chart rather than for a viewing spot; the sign is what an astrologer
/// would have looked up anyway.
struct MoonCard: View {

    let phase: MoonPhase

    @ObservedObject private var strings = L10n.shared

    var body: some View {
        WeatherCard {
            WeatherCardHeader(icon: symbol, title: Astro.moonPhase(phase.phaseName))

            HStack(alignment: .center, spacing: 14) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.label) { index, row in
                        if index > 0 {
                            WeatherCardDivider()
                        }

                        MoonRow(row: row)
                    }
                }

                MoonDisc(angle: phase.angle, size: 112)
                    .padding(.leading, 2)
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Readings

    private var rows: [MoonRow.Row] {
        var rows: [MoonRow.Row] = []

        if let illumination = phase.illuminationPct {
            rows.append(
                .init(label: L("moon.illumination"), value: "\(Int(illumination.rounded()))%", unit: nil)
            )
        }

        if let sign = phase.moonSign, !sign.isEmpty {
            let glyph = AstroGlyph.sign(sign)
            let name = Astro.sign(sign) ?? sign
            let degree = phase.moonDegree.map { " \($0)°" } ?? ""
            rows.append(
                .init(
                    label: L("moon.sign"),
                    value: glyph.isEmpty ? "\(name)\(degree)" : "\(glyph) \(name)\(degree)",
                    unit: nil
                )
            )
        }

        rows.append(nextEvent)
        return rows
    }

    /// Weather always counts down to the full moon. A countdown of nearly a
    /// month on the very day it is full would be a poor reading, so the day
    /// itself, and the new moon's own day, are named instead.
    private var nextEvent: MoonRow.Row {
        let toFull = phase.daysToFullMoon
        let toNew = phase.daysToNewMoon

        if toFull < 1 { return .init(label: L("moon.fullMoon"), value: L("common.today"), unit: nil) }
        if toNew < 1 { return .init(label: L("moon.newMoon"), value: L("common.today"), unit: nil) }

        let days = Int(toFull.rounded())
        return .init(
            label: L("moon.nextFullMoon"),
            value: "\(days)",
            unit: L(count: days, "common.day")
        )
    }

    private var symbol: String {
        switch phase.phaseName.lowercased() {
        case "new moon": return "moonphase.new.moon"
        case "waxing crescent": return "moonphase.waxing.crescent"
        case "first quarter": return "moonphase.first.quarter"
        case "waxing gibbous": return "moonphase.waxing.gibbous"
        case "full moon": return "moonphase.full.moon"
        case "waning gibbous": return "moonphase.waning.gibbous"
        case "third quarter", "last quarter": return "moonphase.last.quarter"
        case "waning crescent": return "moonphase.waning.crescent"
        default: return "moon"
        }
    }
}

/// One label-and-reading line. The unit rides smaller and in caps behind the
/// number, the way Weather sets "20 DAYS".
private struct MoonRow: View {

    struct Row {
        let label: String
        let value: String
        let unit: String?
    }

    let row: Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 6)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(row.value)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .monospacedDigit()

                if let unit = row.unit {
                    Text(unit.uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(0.3)
                }
            }
            .foregroundStyle(.white.opacity(0.65))
            .lineLimit(1)
            .fixedSize()
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label), \(row.value) \(row.unit ?? "")")
    }
}

#if DEBUG
#Preview("Moon card") {
    ZStack {
        WeatherSky.gradient(for: .active).ignoresSafeArea()

        VStack(spacing: 16) {
            MoonCard(
                phase: MoonPhase(
                    phaseName: "Waxing Gibbous",
                    illuminationPct: 78,
                    moonSign: "Aquarius",
                    moonDegree: 14,
                    phaseEmoji: "🌔",
                    phaseAngle: 124.1
                )
            )

            MoonCard(
                phase: MoonPhase(
                    phaseName: "Waning Crescent",
                    illuminationPct: 21,
                    moonSign: "Cancer",
                    moonDegree: 19,
                    phaseEmoji: "🌘",
                    phaseAngle: 305
                )
            )
        }
        .padding(16)
    }
}
#endif
