import SwiftUI

/// Weather's explanation blocks, the ones under a detail chart: a heading in
/// the sheet's own voice, and a panel of plain definitions under it.
///
/// One rule holds the copy together, and it is the reason these exist at all:
/// a definition, never a reading. "Square, 90°: friction that forces action"
/// tells the reader what the thing on screen is and leaves the conclusion to
/// them; "your week will be difficult" hands them one they cannot check. The
/// app already interprets elsewhere, in the transit meanings; this is the
/// glossary a reader learns the chart from.
///
/// Always at the foot of a sheet, after the data it explains, so the reading
/// stays first and the schooling is there for whoever scrolls.
struct AboutSection: View {

    let title: String
    var style: AboutStyle = .sheet
    let terms: [AboutTerm]
    /// A closing paragraph with no term of its own, for the thing that has to
    /// be said about a whole group rather than about one row of it.
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(style.ink)
                .fixedSize(horizontal: false, vertical: true)

            card
        }
    }

    @ViewBuilder
    private var card: some View {
        switch style {
        // The two sheet grounds the app has: a plain grouped surface under
        // the transit and natal sheets, the day's own sky under the forecast
        // one. The block has to be legible on both.
        case .sheet:
            SheetCard { rows }
        case .sky:
            WeatherCard { rows }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(terms) { term in
                VStack(alignment: .leading, spacing: 3) {
                    Text(term.term)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(style.ink)

                    Text(term.definition)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(style.dim)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }

            if let note {
                Text(note)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(style.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A term and what it means. Built through `add` rather than by hand, so a
/// definition the glossary does not carry drops its row instead of printing
/// an empty one.
struct AboutTerm: Identifiable {
    let id = UUID()
    let term: String
    let definition: String
}

extension Array where Element == AboutTerm {
    /// Appends the pair, or nothing at all when there is no definition to
    /// show — which is how a chart point the guide has no line for, or a
    /// house on a sheet about an angle, leaves no gap behind.
    mutating func add(_ term: String, _ definition: String?) {
        guard let definition, !definition.isEmpty else { return }
        append(AboutTerm(term: term, definition: definition))
    }
}

enum AboutStyle {
    case sheet
    case sky

    var ink: Color {
        switch self {
        case .sheet: return Theme.text
        case .sky: return .white
        }
    }

    var dim: Color {
        switch self {
        case .sheet: return Theme.textDim
        case .sky: return .white.opacity(0.75)
        }
    }
}

#if DEBUG
#Preview("About") {
    ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            AboutSection(
                title: L("about.numbersTitle"),
                terms: {
                    var terms: [AboutTerm] = []
                    terms.add(L("about.orbTerm"), L("about.orbDesc"))
                    terms.add(L("about.strengthTerm"), L("about.strengthTransitDesc"))
                    terms.add(Astro.object("Saturn"), Glossary.object("Saturn"))
                    return terms
                }(),
                note: L("guide.aspectsNote")
            )
        }
        .padding(16)
    }
    .background(Theme.sheetBg)
}
#endif
