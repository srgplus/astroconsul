import SwiftUI

/// What a row of the chart aspects table leaves out: the aspect named in
/// full, where both of its points stand in the birth chart, and what each
/// piece of the row means.
///
/// It costs no extra request. The transit report that feeds Active Transits
/// already carries the natal grid and the natal positions; this sheet only
/// picks out the two points the aspect joins.
///
/// Drawn like `TransitDetailSheet` — a plain surface rather than the sky, so
/// the reading stays legible whatever colour the page underneath happens to
/// be. No window and no progress bar: a chart aspect was set at birth and
/// never moves, so there is nothing for either to show.
struct NatalAspectDetailSheet: View {

    let aspect: NatalAspect
    /// Natal positions by object id — `TransitPositions.natal`. Empty only
    /// costs the sheet its positions card.
    var positions: [String: ChartPosition] = [:]

    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var strings = L10n.shared

    /// Both ends of the pair that the report placed, in the order the title
    /// names them.
    private var points: [(object: String, position: ChartPosition)] {
        [aspect.p1, aspect.p2].compactMap { object in
            positions[object].map { (object, $0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                where_
                about
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { closeBar }
        .presentationDetents([.medium, .large])
        // A grabber and a close button say the same thing twice; Weather's own
        // detail sheets carry the button and no grabber.
        .presentationDragIndicator(.hidden)
        .presentationBackground(Theme.sheetBg)
        .environment(\.transitPalette, .onSurface)
    }

    /// The aspect's three glyphs on the close line, the way the transit sheet
    /// carries its own.
    private var closeBar: some View {
        HStack {
            TransitGlyphs(aspect: aspect, size: 26, width: nil)

            Spacer(minLength: 12)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.sheetCard))
            }
            .accessibilityLabel(L("common.close"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        // The scroll runs behind this inset, so the strip carries the sheet's
        // own ground: without it the glossary slides up under the glyphs.
        .background(Theme.sheetBg)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(aspect.title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                StrengthLabel(strength: aspect.strength)

                Text(L("detail.orb", String(format: "%.2f", aspect.orb)))
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.textStrong)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Positions

    @ViewBuilder
    private var where_: some View {
        if !points.isEmpty {
            SheetCard {
                SheetCardHeader(icon: "location.circle", title: L("detail.positions"))
                    .padding(.bottom, 4)

                ForEach(points, id: \.object) { point in
                    SheetPositionRow(
                        object: point.object,
                        position: point.position,
                        label: L("detail.natal"),
                        marksRetrograde: true,
                        showsAngleHouse: false
                    )
                    .padding(.top, 10)
                }
            }
        }
    }

    // MARK: - About

    /// The glossary for what the sheet just showed: the two points and the
    /// angle between them, the numbers beside the title, and the notation
    /// the position rows are written in.
    ///
    /// Definitions only, the way every About block is. The sheet says the Sun
    /// squares Saturn by 1.4°; this says what the Sun, a square and Saturn
    /// each are, and leaves the conclusion to the person whose chart it is.
    private var about: some View {
        VStack(alignment: .leading, spacing: 22) {
            AboutSection(
                title: L("about.aspectTitle"),
                terms: whatItIs,
                note: L("guide.aspectsNote")
            )

            AboutSection(title: L("about.numbersTitle"), terms: numbers)

            if !positionTerms.isEmpty {
                AboutSection(title: L("about.positionsTitle"), terms: positionTerms)
            }
        }
        .padding(.top, 8)
    }

    /// The title, read left to right: one point, the angle, the other point.
    private var whatItIs: [AboutTerm] {
        var terms: [AboutTerm] = []
        terms.add(L("about.natalAspectTerm"), L("about.natalAspectDesc"))
        terms.add(Astro.object(aspect.p1), Glossary.object(aspect.p1))
        terms.add(Glossary.aspectTerm(aspect.aspect), Glossary.aspect(aspect.aspect))
        terms.add(Astro.object(aspect.p2), Glossary.object(aspect.p2))
        return terms
    }

    private var numbers: [AboutTerm] {
        var terms: [AboutTerm] = []
        terms.add(L("about.orbTerm"), L("about.orbDesc"))
        terms.add(L("about.strengthTerm"), L("about.strengthNatalDesc"))
        return terms
    }

    /// The notation first, then the signs and houses these two points
    /// actually stand in, each named once: both ends of an aspect can sit in
    /// one sign, and the block should say so once.
    private var positionTerms: [AboutTerm] {
        guard !points.isEmpty else { return [] }

        var terms: [AboutTerm] = []
        terms.add(L("about.degreeTerm"), L("about.degreeDesc"))

        for sign in distinct(points.compactMap(\.position.sign)) {
            terms.add(Astro.sign(sign) ?? sign, Glossary.sign(sign))
        }

        // The rows print no house for the angles, so neither does this.
        let houses = distinct(
            points
                .filter { $0.object != "ASC" && $0.object != "MC" }
                .compactMap(\.position.houseNumber)
        )

        if !houses.isEmpty {
            terms.add(L("about.houseTerm"), L("about.houseDesc"))

            for house in houses {
                terms.add(L("about.houseNumber", house), Glossary.house(house))
            }
        }

        if points.contains(where: { $0.position.retrograde == true }) {
            terms.add(L("guide.retrograde"), L("about.retrogradeNatalDesc"))
        }

        return terms
    }

    private func distinct<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }
}

#if DEBUG
#Preview {
    ZStack {
        WeatherSky.gradient(for: .active).ignoresSafeArea()
    }
    .sheet(isPresented: .constant(true)) {
        NatalAspectDetailSheet(
            aspect: WeatherPreviewData.positions.natalAspects[0],
            positions: WeatherPreviewData.positions.natal
        )
    }
}
#endif
