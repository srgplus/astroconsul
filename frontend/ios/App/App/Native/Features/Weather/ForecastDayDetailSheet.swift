import SwiftUI

/// One day of the forecast, opened from its row.
///
/// The same reading the page would show if the day had been picked by hand in
/// the settings sheet — hero, Moon, active transits, cosmic climate — minus
/// the birth chart, which is the one thing on that page that does not move
/// when the day does.
///
/// The day's own numbers are already in hand: the forecast row carries the
/// TII, the feels-like and the Moon, so the hero draws immediately and only
/// the transit report is fetched. Until it lands the cards below stand as
/// skeletons, the way they do on the page itself.
struct ForecastDayDetailSheet: View {

    let profile: ProfileSummary
    let day: ForecastDay
    /// The first row of the window, so the header can say "Today".
    var isToday = false
    /// The moment this day is read at — its date, at the clock time and in the
    /// place the page is already reading.
    let moment: TransitMoment

    @StateObject private var model: CosmicWeatherViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var strings = L10n.shared

    /// Autoclosure so the model is built on the main actor when SwiftUI
    /// installs the view, not at the call site.
    init(
        profile: ProfileSummary,
        day: ForecastDay,
        isToday: Bool = false,
        moment: TransitMoment,
        model: @autoclosure @escaping () -> CosmicWeatherViewModel
    ) {
        self.profile = profile
        self.day = day
        self.isToday = isToday
        self.moment = moment
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                    .padding(.top, 4)
                    .padding(.bottom, 2)

                if let phase = day.moonPhase {
                    MoonCard(phase: phase)
                }

                transits

                about
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { closeBar }
        .tint(.white)
        .presentationDetents([.medium, .large])
        // A close button and a grabber say the same thing twice; the detail
        // sheets already in the app carry the button and no grabber.
        .presentationDragIndicator(.hidden)
        // The day's own sky, so the sheet is coloured by the reading it
        // carries rather than by the page it was opened from.
        .presentationBackground {
            ZStack {
                WeatherSky.gradient(for: day.zone)

                // The same scrim the page carries, so a sheet opened from a
                // row is lit like the row it came from.
                SkyScrim()
            }
        }
        .task {
            // A seeded model (previews, harness) is already loaded.
            guard model.transitsState == .idle else { return }
            await model.loadDay(moment, profile: profile)
        }
    }

    // MARK: - Chrome

    /// The day on the left, the way out on the right — the same bar the
    /// transit detail sheet opens with, so a sheet reached from a row behaves
    /// like every other sheet reached from a row.
    private var closeBar: some View {
        HStack(spacing: 12) {
            Text(day.label(isToday: isToday))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .weatherGlass(in: .circle, interactive: true)
            .accessibilityLabel(L("common.close"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        // The scroll runs behind this inset. On the plain sheets the strip
        // takes their grey ground; here the ground is the day's own sky, so
        // it takes the glass the cards are made of instead and the reading
        // blurs out under the label rather than colliding with it.
        .weatherGlass(in: Rectangle(), tint: 0.18)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11, weight: .semibold))

                Text(place.uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.75))

            Text(day.longLabel(isToday: isToday))
                .font(.system(size: 28, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            // The report is cast for a moment, not for a date, so the hero
            // says which — the same stamp the page carries under the name.
            Text(stamp)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 5)

            IntensityTension(intensity: day.tii, tension: day.tensionRatio)
                .padding(.top, 2)
                .padding(.bottom, 10)

            HStack(spacing: 7) {
                Image(systemName: FeelsLike.symbol(for: day.feelsLike))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 18))

                Text(Astro.feels(day.feelsLike) ?? day.feelsLike)
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }

            if let headline = Astro.headline(for: day.feelsLike, at: moment.instant, in: moment.zone) {
                Text(headline)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Where the sky is being read from: the place the page is on, falling
    /// back to the profile's own.
    private var place: String {
        moment.locationName ?? profile.currentLocationName ?? "@\(profile.username)"
    }

    /// "Mon, Sep 7 at 1:05 AM", in the zone the reading is cast for.
    private var stamp: String {
        LocalizedDate.string(moment.instant, template: "EEE d MMM jmm", in: moment.zone)
    }

    // MARK: - About

    /// The glossary for the day: the two numbers in the hero, the label they
    /// resolve to, the Moon panel, and the difference between the two transit
    /// lists under it.
    ///
    /// Drawn in the sky palette rather than the sheet one — this sheet keeps
    /// the day's own weather behind it, so the block has to sit on glass with
    /// the cards above it rather than on a grouped grey.
    ///
    /// Definitions, not a verdict: what intensity counts and where the bands
    /// fall, so a reader can look at 62 with high tension and decide for
    /// themselves what kind of day that is.
    private var about: some View {
        VStack(alignment: .leading, spacing: 22) {
            AboutSection(title: L("about.numbersTitle"), style: .sky, terms: numbers)

            if let phase = day.moonPhase {
                AboutSection(title: L("about.moonTitle"), style: .sky, terms: moonTerms(phase))
            }

            if !listTerms.isEmpty {
                AboutSection(title: L("about.listsTitle"), style: .sky, terms: listTerms)
            }
        }
        .padding(.top, 4)
    }

    private var numbers: [AboutTerm] {
        var terms: [AboutTerm] = []
        terms.add(L("about.intensityTerm"), L("about.intensityDesc"))
        terms.add(L("about.zonesTerm"), L("about.zonesDesc"))

        // The pair is only a pair when the reading carries the split; on a
        // day that came back without one the hero shows the intensity alone.
        if day.tensionRatio != nil {
            terms.add(L("about.tensionTerm"), L("about.tensionDesc"))
            terms.add(L("about.tensionBandsTerm"), L("about.tensionBandsDesc"))
        }

        if !day.feelsLike.isEmpty {
            terms.add(L("about.feelsTerm"), L("about.feelsLikeDesc"))
        }

        return terms
    }

    /// One row per reading the Moon card actually prints, plus the archetype
    /// of the sign it is crossing.
    private func moonTerms(_ phase: MoonPhase) -> [AboutTerm] {
        var terms: [AboutTerm] = []
        terms.add(L("about.moonPhaseTerm"), L("about.moonPhaseDesc"))

        if phase.illuminationPct != nil {
            terms.add(L("moon.illumination"), L("about.illuminationDesc"))
        }

        if let sign = phase.moonSign, !sign.isEmpty {
            terms.add(L("moon.sign"), L("about.moonSignDesc"))
            terms.add(Astro.sign(sign) ?? sign, Glossary.sign(sign))
        }

        return terms
    }

    /// Both lists hold transits and neither is a subset of the other, which
    /// is the one thing a reader cannot tell from the two cards alone.
    private var listTerms: [AboutTerm] {
        guard case .loaded = model.transitsState else { return [] }

        var terms: [AboutTerm] = []

        if !model.activeAspects.isEmpty {
            terms.add(L("transits.title"), L("about.activeTransitsDesc"))
        }

        if !model.cosmicClimate.isEmpty {
            terms.add(L("climate.title"), L("about.climateDesc"))
        }

        return terms
    }

    // MARK: - Transits

    @ViewBuilder
    private var transits: some View {
        switch model.transitsState {
        case .idle, .loading:
            WeatherSkeleton(kind: .transits)

        case let .failed(message):
            WeatherCard {
                WeatherCardHeader(icon: "exclamationmark.triangle", title: L("forecast.noTransits"))
                    .padding(.bottom, 8)

                Text(message)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Button(L("common.tryAgain")) {
                    Task { await model.loadDay(moment, profile: profile) }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 10)
            }

        case .loaded:
            if model.activeAspects.isEmpty && model.cosmicClimate.isEmpty {
                WeatherCard {
                    Text(L("forecast.noTransitsBody"))
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.white)
                }
            } else {
                // `now` is the day being read, not the clock: the progress
                // bars mark where each transit stands on that day.
                ActiveTransitsCard(
                    aspects: model.activeAspects,
                    retrograde: model.retrogradeObjects,
                    positions: model.positions,
                    now: moment.instant
                )

                CosmicClimateCard(
                    aspects: model.cosmicClimate,
                    retrograde: model.retrogradeObjects,
                    positions: model.positions,
                    now: moment.instant
                )
            }
        }
    }
}

#if DEBUG
#Preview("Forecast day") {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ForecastDayDetailSheet(
                profile: WeatherPreviewData.profile,
                day: WeatherPreviewData.days[3],
                moment: TransitMoment(instant: Date(), zone: .current),
                model: CosmicWeatherViewModel(
                    previewDays: WeatherPreviewData.days,
                    previewAspects: WeatherPreviewData.aspects,
                    previewClimate: WeatherPreviewData.climate,
                    previewRetrograde: WeatherPreviewData.retrograde,
                    previewPositions: WeatherPreviewData.positions
                )
            )
        }
}
#endif
