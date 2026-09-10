import SwiftUI

/// What a row of the natal table leaves out: where the point sits spelled in
/// full, what it touches inside the birth chart, and what is transiting it at
/// the moment being read.
///
/// It costs no extra request. The transit report that feeds Active Transits
/// already carries the natal positions, the natal aspect grid and every
/// aspect currently inside orb; this sheet only picks out the ones that name
/// this point.
///
/// Drawn like `TransitDetailSheet` — a plain surface rather than the sky, so
/// the reading stays legible whatever colour the page underneath happens to
/// be, and its ink follows the system appearance instead of being white.
struct NatalPositionDetailSheet: View {

    /// Object id, e.g. "Moon" or "ASC".
    let object: String
    let position: ChartPosition
    /// The whole natal grid; the rows drawn here are the ones naming `object`.
    var natalAspects: [NatalAspect] = []
    /// Every aspect currently inside orb; the rows drawn here are the ones
    /// landing on `object`.
    var transits: [ActiveAspect] = []
    /// Transiting bodies retrograde right now, marked on the transit rows.
    var retrograde: Set<String> = []
    var positions: TransitPositions = .init()
    var now: Date = Date()

    @Environment(\.dismiss) private var dismiss

    /// Held rather than read from the environment: the `.onSurface` palette
    /// this sheet sets applies to what its body draws, not to the view
    /// setting it, so an `@Environment` read here would still answer with the
    /// card's palette — the one tuned for glass over a saturated sky.
    private let palette: TransitPalette = .onSurface

    @ObservedObject private var strings = L10n.shared

    /// A transit row opens the same sheet the Active Transits card opens, so
    /// the window and the interpretation are read in one place only.
    @State private var selectedTransit: ActiveAspect?

    /// Tightest first: the closer the orb, the louder the aspect.
    private var aspects: [NatalAspect] {
        natalAspects
            .filter { $0.p1 == object || $0.p2 == object }
            .sorted { $0.orb < $1.orb }
    }

    private var hits: [ActiveAspect] {
        transits
            .filter { $0.natalObject == object }
            .sorted { $0.orb < $1.orb }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                chartAspects
                transitsHere
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
        .sheet(item: $selectedTransit) { aspect in
            TransitDetailSheet(
                aspect: aspect,
                isRetrograde: retrograde.contains(aspect.transitObject),
                positions: positions,
                now: now
            )
        }
    }

    /// The point's own glyph on the close line, where the transit sheet puts
    /// the three of the aspect.
    private var closeBar: some View {
        HStack {
            Text(AstroGlyph.object(object))
                .font(.system(size: 26))
                .foregroundStyle(Theme.text)
                .accessibilityHidden(true)

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
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Astro.object(object))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                // Retrograde at birth, not today: part of the chart, and it
                // never changes.
                if position.retrograde == true {
                    Text("\u{211E}")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize()
                        .accessibilityLabel(L("detail.retrograde"))
                }
            }

            HStack(spacing: 8) {
                if let degree = position.formattedDegree {
                    Text(degree)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.textStrong)
                        .monospacedDigit()
                        .fixedSize()
                }

                // Sign name, no glyph: U+2648-2653 resolve through the emoji
                // font, which the simulator draws as tofu and a device draws
                // in colour.
                if let sign = Astro.sign(position.sign) {
                    Text(sign)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.textStrong)
                        .lineLimit(1)
                        .fixedSize()
                }

                // The angles are the cusps of houses 1 and 10 by definition,
                // so naming a house there would repeat the title.
                if object != "ASC", object != "MC", let house = position.houseNumber {
                    Text("· \(L("detail.house", house))")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize()
                }
            }
        }
    }

    // MARK: - Aspects inside the chart

    @ViewBuilder
    private var chartAspects: some View {
        if !aspects.isEmpty {
            SheetCard {
                // The card on the page behind this sheet is headed the same
                // way, and it is the same table narrowed to one point.
                SheetCardHeader(
                    icon: "circle.hexagongrid.circle",
                    title: L("natalAspects.title"),
                    trailing: "\(aspects.count)"
                )
                .padding(.bottom, 4)

                ForEach(aspects) { aspect in
                    aspectRow(aspect)
                        .padding(.top, 10)
                }
            }
        }
    }

    /// The other end of the pair, whichever side of it this point is on: the
    /// engine emits each combination once, in the order the bodies happen to
    /// be listed.
    ///
    /// `NatalAspectsCard` prints the whole reading — "Луна квадрат Сатурн" —
    /// because its rows come from all over the chart. Here every row starts
    /// with the point the sheet is about, so naming it again on each line
    /// would cost the width the other half needs.
    private func aspectRow(_ aspect: NatalAspect) -> some View {
        let other = aspect.p1 == object ? aspect.p2 : aspect.p1

        return HStack(spacing: 6) {
            TransitGlyphs(first: object, aspect: aspect.aspect, second: other, width: 50)

            Text("\(Astro.aspect(aspect.aspect)) \(Astro.object(other))")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.2f°", aspect.orb))
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .monospacedDigit()
                .fixedSize()

            // Shrinks inside its column rather than growing over the reading
            // beside it, the same way the natal aspects card sets this label.
            Text(Astro.strength(aspect.strength))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(palette.strength(aspect.strength))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 60, alignment: .trailing)
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

    // MARK: - What is transiting it

    @ViewBuilder
    private var transitsHere: some View {
        if !hits.isEmpty {
            SheetCard {
                SheetCardHeader(
                    icon: "arrow.triangle.swap",
                    title: L("natal.transitsHere"),
                    trailing: "\(hits.count)"
                )
                .padding(.bottom, 4)

                ForEach(hits) { aspect in
                    transitRow(aspect)
                        .padding(.top, 10)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTransit = aspect }
                }
            }
        }
    }

    private func transitRow(_ aspect: ActiveAspect) -> some View {
        HStack(spacing: 8) {
            TransitGlyphs(aspect: aspect, width: 50)

            HStack(spacing: 5) {
                Text(Astro.object(aspect.transitObject))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Retrograde now, which is about the transiting body rather
                // than the natal point the sheet is about.
                if retrograde.contains(aspect.transitObject) {
                    Text("\u{211E}")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize()
                        .accessibilityLabel(L("detail.retrograde"))
                }
            }

            Spacer(minLength: 6)

            Text(String(format: "%.2f°", aspect.orb))
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .monospacedDigit()
                .fixedSize()

            StrengthLabel(strength: aspect.strength, width: 66)
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
        .accessibilityAddTraits(.isButton)
    }
}

#if DEBUG
#Preview {
    ZStack {
        WeatherSky.gradient(for: .active).ignoresSafeArea()
    }
    .sheet(isPresented: .constant(true)) {
        NatalPositionDetailSheet(
            object: "Moon",
            position: WeatherPreviewData.positions.natal["Moon"]!,
            natalAspects: WeatherPreviewData.positions.natalAspects,
            transits: WeatherPreviewData.aspects,
            retrograde: WeatherPreviewData.retrograde,
            positions: WeatherPreviewData.positions
        )
    }
}
#endif
