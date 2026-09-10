import SwiftUI

/// A person as a circle of initials.
///
/// The app has no avatars — nobody uploads a picture — so the web widget draws
/// initials on a tinted disc, indigo for one side of the pair and pink for the
/// other, and so does this. Which colour a disc takes is the only thing saying
/// whose planets are whose, so it is the same pair everywhere: the card, the
/// report's header and every position line inside it.
struct PersonAvatar: View {

    let name: String
    let side: SynastrySide
    var size: CGFloat = 52

    @Environment(\.transitPalette) private var palette

    var body: some View {
        Circle()
            .fill(palette.person(side).opacity(0.22))
            .overlay {
                Circle().strokeBorder(palette.person(side).opacity(0.55), lineWidth: 2)
            }
            .overlay {
                Text(Self.initials(name))
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.person(side))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(2)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// "Alena Brama" → "AB", "Asmik" → "A". Two letters at most: three initials
    /// on a 52pt disc is a word, not a mark.
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return "?" }
        guard words.count > 1, let second = words.dropFirst().first?.first else {
            return String(first).uppercased()
        }
        return "\(first)\(second)".uppercased()
    }
}

/// An empty second slot: a dashed ring with a plus in it, which is how the web
/// widget asks for a partner.
struct PersonAvatarPlaceholder: View {

    var size: CGFloat = 52

    @Environment(\.transitPalette) private var palette

    var body: some View {
        Circle()
            .fill(palette.primary.opacity(0.06))
            .overlay {
                Circle()
                    .strokeBorder(
                        palette.tertiary,
                        style: StrokeStyle(lineWidth: 1.6, dash: [4, 3])
                    )
            }
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.34, weight: .light))
                    .foregroundStyle(palette.secondary)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The overall score as a ring, purple into pink — the web report's gauge.
///
/// The arc draws itself on rather than appearing filled: the number is the one
/// thing the whole feature is for, and a ring that sweeps to it says "this was
/// just worked out" in a way a static circle does not. It sweeps once, when the
/// score lands, and never again on a redraw.
struct CompatibilityGauge: View {

    /// 0–100 from the engine.
    let score: Int
    var size: CGFloat = 116
    var lineWidth: CGFloat = 9

    @Environment(\.transitPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var swept = false

    private var fill: CGFloat { CGFloat(min(max(Double(score) / 100, 0), 1)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.track, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: swept ? fill : 0)
                .stroke(
                    AngularGradient(
                        colors: [Theme.scoreArcStart, Theme.scoreArcEnd],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(score)")
                .font(.system(size: size * 0.34, weight: .light, design: .rounded))
                .foregroundStyle(palette.primary)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        // Two animations, because the arc moves for two different reasons: the
        // sweep it draws itself with, and the shorter step it takes when the
        // reader switches between the love and the business reading.
        .animation(.easeOut(duration: 0.7), value: swept)
        .animation(.easeOut(duration: 0.4), value: fill)
        .task {
            guard !swept else { return }
            guard !reduceMotion else {
                swept = true
                return
            }
            // A beat, so the sweep starts after the card has settled rather
            // than during the same frame it appears in.
            try? await Task.sleep(for: .milliseconds(80))
            swept = true
        }
        .accessibilityHidden(true)
    }
}

/// The four category scores as small meters, for the card: a caps label over a
/// bar, all in the palette's own ink.
///
/// White rather than the web's four colours, which were picked for a dark page
/// and are the report's business. Over a saturated sky four coloured bars in a
/// row read as a chart the card is not; the hero above draws its intensity and
/// tension the same way, so the page keeps one voice.
struct CompatibilityMeters: View {

    let categories: [(key: String, value: Int)]

    @Environment(\.transitPalette) private var palette
    @ObservedObject private var strings = L10n.shared

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(categories, id: \.key) { category in
                VStack(spacing: 5) {
                    Text(L("synastry.\(category.key)"))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("\(category.value)")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.primary)
                        .monospacedDigit()

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(palette.track)
                            .frame(height: 3)

                        GeometryReader { geometry in
                            Capsule()
                                .fill(palette.primary.opacity(0.85))
                                .frame(
                                    width: max(geometry.size.width * fill(category.value), 3),
                                    height: 3
                                )
                        }
                        .frame(height: 3)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            categories
                .map { "\(L("synastry.\($0.key)")) \($0.value)" }
                .joined(separator: ", ")
        )
    }

    private func fill(_ value: Int) -> CGFloat {
        CGFloat(min(max(Double(value) / 100, 0), 1))
    }
}

/// The same four scores as full rows, for the report: name, per cent and a bar
/// in the category's own colour, the way the web report prints them.
struct CompatibilityCategoryRows: View {

    let categories: [(key: String, value: Int)]

    @ObservedObject private var strings = L10n.shared

    var body: some View {
        VStack(spacing: 12) {
            ForEach(categories, id: \.key) { category in
                let ink = Theme.categoryColor(category.key)

                VStack(spacing: 5) {
                    HStack(spacing: 8) {
                        Text(L("synastry.\(category.key)"))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(Theme.textDim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Spacer(minLength: 6)

                        Text("\(category.value)%")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(ink)
                            .monospacedDigit()
                    }

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.lineStrong)
                            .frame(height: 5)

                        GeometryReader { geometry in
                            Capsule()
                                .fill(ink)
                                .frame(
                                    width: max(geometry.size.width * fill(category.value), 5),
                                    height: 5
                                )
                        }
                        .frame(height: 5)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(L("synastry.\(category.key)")) \(category.value)%")
            }
        }
    }

    private func fill(_ value: Int) -> CGFloat {
        CGFloat(min(max(Double(value) / 100, 0), 1))
    }
}

/// The keywords of one aspect as tinted tags, cycling through seven colours the
/// way the web's `nth-child(7n+…)` rules do.
struct KeywordTags: View {

    let keywords: [String]

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(keywords.enumerated()), id: \.offset) { index, keyword in
                let tint = Theme.keywordTint(index)

                Text(keyword)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(tint.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tint.fill))
            }
        }
    }
}

/// Tags wrapped onto as many lines as they need.
///
/// `LazyVGrid` cannot do this — every column would be as wide as the longest
/// word — and an `HStack` runs off the edge. Twelve lines of `Layout` is the
/// whole of it.
struct FlowLayout: Layout {

    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, in: width)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layout(subviews: subviews, in: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = row.indices.isEmpty ? size.width : row.width + spacing + size.width

            if next > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
                row.indices = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.indices.append(index)
                row.width = next
                row.height = max(row.height, size.height)
            }
        }

        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
