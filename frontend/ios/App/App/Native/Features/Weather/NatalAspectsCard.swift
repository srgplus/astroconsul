import SwiftUI

/// The aspect grid of the birth chart itself: which of a person's own planets
/// speak to which, and how closely.
///
/// The web has carried this table inside the birth chart modal since the
/// beginning; natively the wheel drew the lines but nothing named them, so a
/// reader could see that their Sun and Saturn were tied together and had no
/// way to find out by how much.
///
/// It costs no extra request. The transit report that feeds Active Transits
/// already sends `natal_aspects`, and the view model keeps them on
/// `TransitPositions.natalAspects` for the wheel to draw from.
///
/// Deliberately the same row as `ActiveTransitsCard` — glyphs, orb, strength —
/// with one difference: the name is spelled out. Up there the transit's arc
/// fills the middle of the row and three glyphs have to carry the naming; here
/// nothing is moving, so the room goes to saying what the aspect is.
struct NatalAspectsCard: View {

    /// The grid as the report sent it — `TransitPositions.natalAspects`.
    let aspects: [NatalAspect]

    @Environment(\.transitPalette) private var palette

    @ObservedObject private var strings = L10n.shared

    /// On by default, the way the web table opens: exact and strong only. A
    /// full grid runs to thirty-odd rows, which is a chart to study rather
    /// than a card to read.
    @State private var mostImpact = true

    private var visible: [NatalAspect] {
        mostImpact ? aspects.filter(\.isImpactful) : aspects
    }

    /// The visible rows sorted and banded the way the web table sorts and
    /// bands them: by the first body's place in the chart, then by orb, with
    /// empty bands dropped.
    ///
    /// Sorted here rather than upstream because the engine emits the grid in
    /// whatever order it happened to walk the bodies in, and both halves of a
    /// pair are equal partners — `p1` leads a row only because it was listed
    /// first.
    private var groups: [(group: TransitGroup, aspects: [NatalAspect])] {
        let sorted = visible.sorted { first, second in
            let ranks = (TransitOrder.natalRank(first.p1), TransitOrder.natalRank(second.p1))
            if ranks.0 != ranks.1 { return ranks.0 < ranks.1 }
            return first.orb < second.orb
        }
        let bands = Dictionary(grouping: sorted) { TransitGroup(natalObject: $0.p1) }
        return TransitGroup.allCases.compactMap { group in
            guard let aspects = bands[group], !aspects.isEmpty else { return nil }
            return (group, aspects)
        }
    }

    var body: some View {
        if !aspects.isEmpty {
            WeatherCard {
                header

                if visible.isEmpty {
                    WeatherCardDivider()

                    Text(L("natalAspects.nothingStrong"))
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                }

                ForEach(groups, id: \.group) { band in
                    WeatherCardDivider()

                    Text(band.group.title.uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    ForEach(band.aspects) { aspect in
                        WeatherCardDivider()

                        row(aspect)
                            .padding(.vertical, 11)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid.circle")
                .font(.system(size: 12, weight: .semibold))

            Text(L("natalAspects.title").uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 8)

            Text(L("transits.mostImpact"))
                .font(.system(size: 13, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            SmallSwitch(isOn: $mostImpact)
                .accessibilityLabel(L("transits.mostImpact"))
        }
        .foregroundStyle(.white.opacity(0.7))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { mostImpact.toggle() }
        }
        .padding(.bottom, 2)
    }

    private func row(_ aspect: NatalAspect) -> some View {
        HStack(spacing: 8) {
            TransitGlyphs(aspect: aspect, width: 54)

            Text(aspect.title)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                // Russian spells the angles out — "Меркурий квадрат
                // Асцендент" — so the line shrinks rather than truncating a
                // reading in the middle of the planet it names.
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.2f°", aspect.orb))
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
                .fixedSize()

            // `StrengthLabel`'s own text is `fixedSize`, which is safe on the
            // transit rows because nothing flexible sits beside it. Here the
            // reading does, and "УМЕРЕННЫЙ" is wider than the column, so this
            // one shrinks inside its width rather than growing over the name.
            Text(Astro.strength(aspect.strength))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 66, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L(
                "transits.orbA11y",
                aspect.title,
                Astro.strength(aspect.strength),
                String(format: "%.2f", aspect.orb)
            )
        )
    }
}

#if DEBUG
#Preview {
    ZStack {
        WeatherSky.gradient(for: .active).ignoresSafeArea()

        ScrollView {
            NatalAspectsCard(aspects: WeatherPreviewData.positions.natalAspects)
                .padding(16)
        }
    }
}
#endif
