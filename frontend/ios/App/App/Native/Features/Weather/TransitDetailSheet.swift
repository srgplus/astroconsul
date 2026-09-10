import SwiftUI

/// What the compact row leaves out: the transit's name, the window it runs
/// over, and where both bodies sit. The written interpretation belongs here
/// too and is not wired up yet.
///
/// Unlike the card, this is not drawn on the sky. Weather's own detail sheets
/// drop the weather behind them for a plain surface, and so does this one, so
/// the reading stays legible whatever colour the page underneath happens to
/// be — which means its ink follows the system appearance instead of being
/// white throughout.
struct TransitDetailSheet: View {

    let aspect: ActiveAspect
    var isRetrograde = false
    var positions: TransitPositions = .init()
    var now: Date = Date()

    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var strings = L10n.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                window
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

    /// Weather's close button: a glyph on a filled circle, top right, floating
    /// over the content rather than sitting in a titled navigation bar. The
    /// aspect's three glyphs ride the same line — alone above the title they
    /// cost a whole row of the sheet and said nothing the title does not.
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(aspect.title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                if isRetrograde {
                    Text("\u{211E}")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize()
                        .accessibilityLabel(L("detail.retrograde"))
                }
            }

            HStack(spacing: 8) {
                StrengthLabel(strength: aspect.strength)

                Text(L("detail.orb", String(format: "%.2f", aspect.orb)))
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.textStrong)
                    .monospacedDigit()

                if let status = aspect.timing?.status, !status.isEmpty {
                    Text("· \(Astro.status(status))")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    // MARK: - Window

    @ViewBuilder
    private var window: some View {
        if let timing = aspect.timing, timing.start != nil, timing.end != nil {
            SheetCard {
                SheetCardHeader(icon: "calendar", title: L("detail.window"), trailing: duration(timing))
                    .padding(.bottom, 14)

                TransitProgressBar(
                    timing: timing,
                    transitObject: aspect.transitObject,
                    showsDates: true,
                    now: now
                )

                if timing.passes.count > 1 {
                    Text(
                        L(
                            "detail.exactTimes",
                            timing.passes.count,
                            timing.passes.map(TransitProgressBar.day).joined(separator: ", ")
                        )
                    )
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
            }
        }
    }

    /// "18 days" / "9 h" — the span in whichever unit reads plainly.
    private func duration(_ timing: AspectTiming) -> String? {
        guard let hours = timing.durationHours, hours > 0 else { return nil }
        if hours < 48 { return L("detail.hours", Int(hours.rounded())) }
        return L("detail.days", Int((hours / 24).rounded()))
    }

    // MARK: - About

    /// The glossary for what the sheet just showed: the two bodies and the
    /// angle between them, the numbers beside the title, the window, and the
    /// notation the position rows are written in.
    ///
    /// Every row names something visible above it and nothing else. The signs
    /// and houses listed are the ones this transit actually falls in, so a
    /// reader learns their own chart rather than a table of twelve.
    private var about: some View {
        VStack(alignment: .leading, spacing: 22) {
            AboutSection(
                title: L("about.transitTitle"),
                terms: whatItIs,
                note: L("guide.aspectsNote")
            )

            AboutSection(title: L("about.numbersTitle"), terms: numbers)

            if aspect.timing?.start != nil, aspect.timing?.end != nil {
                AboutSection(title: L("about.windowTitle"), terms: windowTerms)
            }

            if !positionTerms.isEmpty {
                AboutSection(title: L("about.positionsTitle"), terms: positionTerms)
            }
        }
        .padding(.top, 8)
    }

    /// The title, read left to right: the travelling body, the angle it makes,
    /// the point of the birth chart it lands on.
    private var whatItIs: [AboutTerm] {
        var terms: [AboutTerm] = []
        terms.add(L("about.transitTerm"), L("about.transitDesc"))
        terms.add(
            L("about.transitingRole", Astro.object(aspect.transitObject)),
            Glossary.object(aspect.transitObject)
        )
        terms.add(Glossary.aspectTerm(aspect.aspect), Glossary.aspect(aspect.aspect))
        terms.add(
            L("about.natalRole", Astro.object(aspect.natalObject)),
            Glossary.object(aspect.natalObject)
        )
        return terms
    }

    /// The line under the title: the orb, the band it falls in, which way it
    /// is going, and the retrograde mark when the header carries one.
    private var numbers: [AboutTerm] {
        var terms: [AboutTerm] = []
        terms.add(L("about.orbTerm"), L("about.orbDesc"))
        terms.add(L("about.strengthTerm"), L("about.strengthTransitDesc"))

        if let status = aspect.timing?.status, !status.isEmpty {
            terms.add(L("about.statusTerm"), L("guide.applyingSep"))
        }

        if isRetrograde {
            terms.add(L("guide.retrograde"), L("guide.retrogradeDesc"))
        }

        return terms
    }

    private var windowTerms: [AboutTerm] {
        var terms: [AboutTerm] = []
        terms.add(L("about.windowTerm"), L("about.windowDesc"))
        terms.add(L("about.exactTerm"), L("about.exactDesc"))
        terms.add(L("about.barTerm"), L("about.barDesc"))
        return terms
    }

    /// The notation first, then the signs and houses this transit actually
    /// stands in, each named once however many of the two rows above it they
    /// came from.
    private var positionTerms: [AboutTerm] {
        let shown = [
            positions.transiting[aspect.transitObject],
            positions.natal[aspect.natalObject],
        ].compactMap { $0 }

        guard !shown.isEmpty else { return [] }

        var terms: [AboutTerm] = []
        terms.add(L("about.degreeTerm"), L("about.degreeDesc"))

        for sign in distinct(shown.compactMap(\.sign)) {
            terms.add(Astro.sign(sign) ?? sign, Glossary.sign(sign))
        }

        let houses = distinct(shown.compactMap(\.houseNumber))

        if !houses.isEmpty {
            terms.add(L("about.houseTerm"), L("about.houseDesc"))

            for house in houses {
                terms.add(L("about.houseNumber", house), Glossary.house(house))
            }
        }

        return terms
    }

    /// Deduplicated, in the order the rows above print them: both ends of an
    /// aspect can sit in one sign, and the block should say so once.
    private func distinct<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }

    // MARK: - Positions

    @ViewBuilder
    private var where_: some View {
        let transiting = positions.transiting[aspect.transitObject]
        let natal = positions.natal[aspect.natalObject]

        if transiting != nil || natal != nil {
            SheetCard {
                SheetCardHeader(icon: "location.circle", title: L("detail.positions"))
                    .padding(.bottom, 4)

                if let transiting {
                    positionRow(
                        object: aspect.transitObject,
                        position: transiting,
                        label: L("detail.transiting")
                    )
                        .padding(.top, 10)
                }

                if let natal {
                    positionRow(
                        object: aspect.natalObject,
                        position: natal,
                        label: L("detail.natal")
                    )
                        .padding(.top, 10)
                }
            }
        }
    }

    private func positionRow(object: String, position: ChartPosition, label: String) -> some View {
        HStack(spacing: 8) {
            Text(AstroGlyph.object(object))
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .frame(width: 22, alignment: .leading)

            Text(Astro.object(object))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 6)

            if let degree = position.formattedDegree {
                Text(degree)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.textStrong)
                    .monospacedDigit()
                    .fixedSize()
            }

            // Sign name, no glyph: U+2648-2653 resolve through the emoji font,
            // which the simulator draws as tofu and a device draws in colour.
            // Neither is what this row wants.
            if let sign = Astro.sign(position.sign) {
                Text(sign)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.textStrong)
                    .lineLimit(1)
                    .fixedSize()
            }

            // A house symbol, not the web's △: that triangle is the glyph for
            // a trine, so on a row about aspects it reads as one.
            if let house = position.houseNumber {
                HStack(spacing: 3) {
                    Image(systemName: "house")
                        .font(.system(size: 11))

                    Text("\(house)")
                        .font(.system(size: 13, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(Theme.textDim)
                .fixedSize()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L("detail.house", house))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(Astro.object(object))")
    }
}

// MARK: - Surface

/// `WeatherCard` in the sheet's palette. The weather one is tuned to float on
/// a saturated sky and reads as a smudge on a plain background.
///
/// No border. The card is a step in tone from the sheet's own ground, which is
/// how the system separates a grouped panel from what it sits on; a hairline
/// on top of that is a second, weaker answer to a question already answered,
/// and it is what makes a panel look drawn rather than raised.
struct SheetCard<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.sheetCard)
        )
    }
}

struct SheetCardHeader: View {

    let icon: String
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))

            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(0.5)

            Spacer(minLength: 8)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
        }
        .foregroundStyle(Theme.textDim)
    }
}
