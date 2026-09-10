import SwiftUI

/// The whole compatibility reading for one pair — the web's synastry report,
/// natively.
///
/// Like the transit and natal sheets, it drops the weather behind it for a
/// plain surface: this is paragraphs and a table of thirty-odd rows, and it has
/// to stay legible whatever colour the sky underneath happens to be. Its ink
/// follows the system appearance rather than being white throughout.
///
/// Two readings of the same aspects, love and business, arrive in one answer,
/// so the toggle at the top swaps the scores and the written reading without a
/// second request. The aspect list is the same either way — it is the pair's
/// geometry, and geometry does not care what the two of them are to each other.
struct CompatibilityReportSheet: View {

    let report: SynastryReport

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var strings = L10n.shared

    @State private var mode: SynastryMode = .love
    /// On by default, the way the web table opens: exact and strong only. The
    /// full grid runs long enough to be a chart to study rather than a reading.
    @State private var mostImpact = true

    private var scores: SynastryScores { report.activeScores(mode) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if report.hasBusiness { modeToggle }

                scoreCard

                aspects

                about
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { closeBar }
        .presentationDetents([.large])
        // A grabber and a close button say the same thing twice; the app's
        // other detail sheets carry the button and no grabber.
        .presentationDragIndicator(.hidden)
        .presentationBackground(Theme.sheetBg)
        .environment(\.transitPalette, .onSurface)
    }

    // MARK: - Chrome

    private var closeBar: some View {
        HStack {
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

    /// The pair, then what this is, then how much of it there is — the same
    /// three lines the web report opens with.
    private var header: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                person(report.personA.name, side: .a)

                Text("\u{00D7}")
                    .font(.system(size: 18, weight: .light, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .padding(.top, 20)

                person(report.personB.name, side: .b)
            }

            VStack(spacing: 4) {
                Text(L("synastry.report"))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)

                Text(
                    "\(report.aspectCount) \(L("synastry.interAspects")) · "
                        + "\(report.exactCount) \(L("synastry.exactOrTight"))"
                )
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func person(_ name: String, side: SynastrySide) -> some View {
        VStack(spacing: 6) {
            PersonAvatar(name: name, side: side, size: 56)

            Text(name)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textStrong)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }

    /// Love or business. A segmented picker rather than the web's pair of
    /// pills: this is the system's own two-way switch, and a sheet is where
    /// system controls belong.
    private var modeToggle: some View {
        Picker(L("synastry.title"), selection: $mode) {
            ForEach(SynastryMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Score

    private var scoreCard: some View {
        SheetCard {
            VStack(spacing: 14) {
                CompatibilityGauge(score: scores.overall, size: 150, lineWidth: 11)

                HStack(spacing: 6) {
                    Text(L("synastry.overallChemistry"))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.textDim)

                    Text(scores.overallLabel)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L("synastry.scoreA11y", scores.overall, scores.overallLabel))

                CompatibilityCategoryRows(categories: scores.categories(mode))
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - About

    /// The glossary for the report: what an inter-aspect is, where the score
    /// comes from, and how the table under it is banded and filtered.
    ///
    /// Definitions rather than a verdict, which matters more here than
    /// anywhere else in the app: a number about two people is the easiest
    /// thing to mistake for a judgement on them. It says what is counted, and
    /// the reader decides what that is worth.
    private var about: some View {
        VStack(alignment: .leading, spacing: 22) {
            AboutSection(title: L("about.synastryTitle"), terms: whatItIs)

            AboutSection(title: L("about.scoreTitle"), terms: scoreTerms)

            AboutSection(
                title: L("about.aspectTableTitle"),
                terms: tableTerms,
                note: L("guide.aspectsNote")
            )
        }
        .padding(.top, 8)
    }

    private var whatItIs: [AboutTerm] {
        var terms: [AboutTerm] = []
        terms.add(L("about.synastryTerm"), L("about.synastryDesc"))
        terms.add(L("about.sidesTerm"), L("about.sidesDesc"))

        // The switch is only drawn when both readings came back, and there is
        // nothing to explain about a choice nobody is offered.
        if report.hasBusiness {
            terms.add(L("about.modeTerm"), L("about.modeDesc"))
        }

        return terms
    }

    /// The categories row follows the switch: the bars under the gauge are
    /// the four of whichever reading is on screen, and so is the line saying
    /// what feeds them.
    private var scoreTerms: [AboutTerm] {
        var terms: [AboutTerm] = []
        terms.add(L("about.scoreTerm"), L("about.scoreDesc"))
        terms.add(L("about.scoreBandsTerm"), L("about.scoreBandsDesc"))
        terms.add(
            L("about.categoriesTerm"),
            mode == .business ? L("about.businessCategoriesDesc") : L("about.loveCategoriesDesc")
        )
        return terms
    }

    private var tableTerms: [AboutTerm] {
        var terms: [AboutTerm] = []
        terms.add(L("about.orbTerm"), L("about.orbDesc"))
        terms.add(L("about.strengthTerm"), L("about.strengthPairDesc"))
        terms.add(L("about.mostImpactTerm"), L("about.mostImpactDesc"))
        terms.add(L("about.bandsTerm"), L("about.bandsDesc"))
        return terms
    }

    // MARK: - Aspects

    private var visible: [SynastryAspect] {
        mostImpact ? report.aspects.filter(\.isImpactful) : report.aspects
    }

    /// The visible rows banded and sorted the way the web report bands and
    /// sorts them: by where the first body sits in the chart, then by orb.
    ///
    /// A pair is banded by whichever half is more personal — a Moon on a Pluto
    /// is a personal aspect, because half of it is a Moon — which is the web's
    /// own `categorizeAspect` rule and not the one-sided test the natal grid
    /// uses.
    private var groups: [(group: TransitGroup, aspects: [SynastryAspect])] {
        let sorted = visible.sorted { first, second in
            let ranks = (
                TransitOrder.natalRank(first.personAObject),
                TransitOrder.natalRank(second.personAObject)
            )
            if ranks.0 != ranks.1 { return ranks.0 < ranks.1 }
            return first.orb < second.orb
        }
        let bands = Dictionary(grouping: sorted, by: Self.band(of:))
        return TransitGroup.allCases.compactMap { group in
            guard let aspects = bands[group], !aspects.isEmpty else { return nil }
            return (group, aspects)
        }
    }

    private static func band(of aspect: SynastryAspect) -> TransitGroup {
        let sides = (
            TransitGroup(natalObject: aspect.personAObject),
            TransitGroup(natalObject: aspect.personBObject)
        )
        if sides.0 == .personal || sides.1 == .personal { return .personal }
        if sides.0 == .outer || sides.1 == .outer { return .outer }
        return .special
    }

    private var aspects: some View {
        SheetCard {
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.circle")
                    .font(.system(size: 12, weight: .semibold))

                Text(L("synastry.aspects"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 8)

                Text(L("transits.mostImpact"))
                    .font(.system(size: 13, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Toggle(L("transits.mostImpact"), isOn: $mostImpact)
                    .toggleStyle(.switch)
                    .tint(Theme.ok)
                    .labelsHidden()
                    .scaleEffect(0.8, anchor: .trailing)
                    .frame(width: 42)
                    .accessibilityLabel(L("transits.mostImpact"))
            }
            .foregroundStyle(Theme.textDim)

            if visible.isEmpty {
                Text(L("synastry.nothingStrong"))
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .padding(.top, 14)
            }

            ForEach(groups, id: \.group) { band in
                Text(band.group.title.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                ForEach(band.aspects) { aspect in
                    Divider().overlay(Theme.line)

                    row(aspect)
                }
            }
        }
    }

    /// One row, and only what can be measured: whose planet against whose, how
    /// far off exact, and which band that orb falls in. The engine also writes
    /// an interpretation of every pair and this deliberately does not print
    /// it — the report is the geometry, and a page of prose under each row
    /// buried the table it belongs to.
    private func row(_ aspect: SynastryAspect) -> some View {
        HStack(spacing: 6) {
            SynastryGlyphs(aspect: aspect)

            Text(title(aspect))
                .font(.system(size: 14, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.2f°", aspect.orb))
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .monospacedDigit()
                .fixedSize()

            Text(Astro.strength(aspect.strength))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(TransitPalette.onSurface.strength(aspect.strength))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// The reading with each body in its own side's colour, which is the only
    /// thing on the row saying whose Moon is whose.
    private func title(_ aspect: SynastryAspect) -> AttributedString {
        var first = AttributedString(Astro.object(aspect.personAObject))
        first.foregroundColor = Theme.personA

        var middle = AttributedString(" \(Astro.aspect(aspect.aspect)) ")
        middle.foregroundColor = Theme.textStrong

        var second = AttributedString(Astro.object(aspect.personBObject))
        second.foregroundColor = Theme.personB

        return first + middle + second
    }
}

/// The three glyphs of an inter-chart aspect, each side in its own colour.
///
/// `TransitGlyphs` draws both bodies in one ink, which is right for a transit
/// — one sky against one chart — and wrong here: the whole point of a synastry
/// row is that the two bodies belong to different people.
struct SynastryGlyphs: View {

    let aspect: SynastryAspect
    var size: CGFloat = 15
    var width: CGFloat? = 54

    @Environment(\.transitPalette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            Text(AstroGlyph.object(aspect.personAObject))
                .foregroundStyle(palette.personA)

            Text(AstroGlyph.aspect(aspect.aspect))
                .foregroundStyle(
                    AstroGlyph.isChallenging(aspect.aspect) ? palette.challenge : palette.secondary
                )

            Text(AstroGlyph.object(aspect.personBObject))
                .foregroundStyle(palette.personB)
        }
        .font(.system(size: size))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(width: width, alignment: .leading)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Compatibility report") {
    CompatibilityReportSheet(report: WeatherPreviewData.synastry)
}
#endif
