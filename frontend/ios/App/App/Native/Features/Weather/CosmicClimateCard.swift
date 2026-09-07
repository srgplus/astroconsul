import SwiftUI

/// The season behind the reading: the outer-planet transits that stay inside
/// orb for months rather than days, one line each.
///
/// Deliberately thinner than `ActiveTransitsCard`, and thinner than the web
/// widget of the same name — that one spells every row out with a paragraph of
/// meaning and a line of advice. Here a row is the glyphs, the arc of the
/// window, and the months it spans; anything longer stops being a dashboard
/// row. The list arrives already ranked by the backend, longest and tightest
/// first, so it is drawn in the order it came in.
struct CosmicClimateCard: View {

    let aspects: [ActiveAspect]
    /// Transiting bodies that are retrograde right now, marked in the sheet.
    var retrograde: Set<String> = []
    var positions: TransitPositions = .init()
    /// Injected rather than read from the clock so previews are stable.
    var now: Date = Date()

    @Environment(\.transitPalette) private var palette

    @State private var selected: ActiveAspect?

    /// Wide enough for "Aug 2026 – Mar 2027", and fixed so the bars end on the
    /// same line however long each range prints.
    private let dateColumn: CGFloat = 116

    /// The rows the card can actually draw. The window and the months it spans
    /// are the whole row here, so an aspect the report sent without timing has
    /// nothing to say on this card — and the report's fast phase sends exactly
    /// that.
    private var visible: [ActiveAspect] {
        aspects.filter { $0.timing?.start != nil && $0.timing?.end != nil }
    }

    var body: some View {
        if !visible.isEmpty {
            WeatherCard {
                WeatherCardHeader(icon: "sun.haze", title: "Cosmic climate")
                    .padding(.bottom, 10)

                ForEach(visible) { aspect in
                    WeatherCardDivider()

                    row(aspect)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = aspect }
                }
            }
            // The row says when; the sheet says what — the same one the
            // transits card opens, so a tap here behaves the way a tap up
            // there already does.
            .sheet(item: $selected) { aspect in
                TransitDetailSheet(
                    aspect: aspect,
                    isRetrograde: retrograde.contains(aspect.transitObject),
                    positions: positions,
                    now: now
                )
            }
        }
    }

    private func row(_ aspect: ActiveAspect) -> some View {
        let range = Self.range(aspect.timing)

        return HStack(spacing: 10) {
            TransitGlyphs(aspect: aspect)

            if let timing = aspect.timing {
                TransitProgressBar(timing: timing, transitObject: aspect.transitObject, now: now)
            }

            Text(range ?? "")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: dateColumn, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(range.map { "\(aspect.title), \($0)" } ?? aspect.title)
        .accessibilityAddTraits(.isButton)
    }

    /// "Aug – Dec 2026", or "Aug 2026 – Mar 2027" once the window crosses a new
    /// year — the shape the web widget prints over its cards.
    static func range(_ timing: AspectTiming?) -> String? {
        guard let start = timing?.start, let end = timing?.end else { return nil }

        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
        let head = sameYear ? month.string(from: start) : monthYear.string(from: start)
        return "\(head) – \(monthYear.string(from: end))"
    }

    private static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    private static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM y")
        return formatter
    }()
}
