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

                // The cards sit low and white on this; the same scrim the
                // page uses keeps them off the brightest part of the sky.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.10), .black.opacity(0.38)],
                    startPoint: .top,
                    endPoint: .bottom
                )
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
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
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

            Text("\(Int(day.tii.rounded()))°")
                .font(.system(size: 84, weight: .ultraLight, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.leading, 13)   // optical centring: the ° hangs right
                .padding(.vertical, -6)

            HStack(spacing: 7) {
                Image(systemName: FeelsLike.symbol(for: day.feelsLike))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 18))

                Text(day.feelsLike)
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }

            if let headline = FeelsLike.headline(for: day.feelsLike, at: moment.instant, in: moment.zone) {
                Text(headline)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.top, 1)
            }

            if let tension = day.tensionRatio {
                TensionBar(ratio: tension)
                    .padding(.top, 12)
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
        let formatter = DateFormatter()
        formatter.timeZone = moment.zone
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM jmm")
        return formatter.string(from: moment.instant)
    }

    // MARK: - Transits

    @ViewBuilder
    private var transits: some View {
        switch model.transitsState {
        case .idle, .loading:
            WeatherSkeleton(kind: .transits)

        case let .failed(message):
            WeatherCard {
                WeatherCardHeader(icon: "exclamationmark.triangle", title: "No transits")
                    .padding(.bottom, 8)

                Text(message)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Try again") {
                    Task { await model.loadDay(moment, profile: profile) }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 10)
            }

        case .loaded:
            if model.activeAspects.isEmpty && model.cosmicClimate.isEmpty {
                WeatherCard {
                    Text("No transits inside orb on this day.")
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
