import SwiftUI

/// Cosmic weather for one profile, laid out the way Apple Weather lays out a
/// city: the sky is the reading, TII stands in for temperature and the
/// feels-like label for "Cloudy". One forecast request feeds the whole screen.
struct CosmicWeatherView: View {

    let profile: ProfileSummary

    /// Safe-area insets, passed in because the pager draws full bleed and the
    /// page can no longer read them for itself. The bottom one also has the
    /// floating bar to clear.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    /// The primary profile is the person holding the phone, so it — and only
    /// it — is labelled with where this device is. A followed profile's owner
    /// is somewhere else entirely.
    var isPrimary: Bool = false

    @StateObject private var model: CosmicWeatherViewModel
    @ObservedObject private var device = DeviceLocation.shared

    init(
        profile: ProfileSummary,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        isPrimary: Bool = false
    ) {
        self.profile = profile
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.isPrimary = isPrimary
        _model = StateObject(wrappedValue: CosmicWeatherViewModel())
    }

    #if DEBUG
    /// Autoclosure so the model is built on the main actor when SwiftUI
    /// installs the view, not at the call site.
    init(
        profile: ProfileSummary,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        isPrimary: Bool = false,
        model: @autoclosure @escaping () -> CosmicWeatherViewModel
    ) {
        self.profile = profile
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.isPrimary = isPrimary
        _model = StateObject(wrappedValue: model())
    }
    #endif

    /// The sky needs a colour before the forecast lands, so fall back to the
    /// TII the profile list already carried in.
    private var zone: TiiZone {
        TiiZone(tii: model.today?.tii ?? profile.latestTransit?.tii ?? 0)
    }

    var body: some View {
        ZStack {
            WeatherSky.gradient(for: zone)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: zone)

            SkyVideo(zone: zone)

            // The footage is brightest where the cards sit, so the lower half
            // gets a scrim. Without it a lightning core or a sunlit cloud eats
            // the white text on the forecast rows.
            LinearGradient(
                colors: [.clear, .black.opacity(0.10), .black.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 18) {
                    hero
                        .padding(.top, topInset + 8)
                        .padding(.bottom, 6)

                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, WeatherBottomBar.height(bottomInset: bottomInset) + 12)
            }
            .refreshable { await model.load(profile: profile, showSpinner: false) }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [WeatherSky.topColor(for: zone), WeatherSky.topColor(for: zone).opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: topInset + 8)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        .tint(.white)
        .preference(key: SkyZoneKey.self, value: [profile.profileId: zone])
        .task {
            // A seeded model (previews, harness) is already loaded.
            guard model.state == .idle else { return }
            await model.load(profile: profile)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11, weight: .semibold))

                Text(subtitle.uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.75))

            Text(profile.profileName)
                .font(.system(size: 34, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            // A transit reading is a moment, not a day, so the hero says
            // which moment — in the profile's own zone, not the device's.
            Text(readingStamp)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.16)))
                .padding(.top, 6)

            Text(temperature)
                .font(.system(size: 92, weight: .ultraLight, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.leading, 14)   // optical centring: the ° hangs right
                .padding(.vertical, -8)

            Text(feelsLike ?? " ")
                .font(.system(size: 21, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            if let headline = FeelsLike.headline(for: feelsLike, at: model.readingTime, in: model.readingZone) {
                Text(headline)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.top, 1)
            }

            if let tension = model.today?.tensionRatio ?? profile.latestTransit?.tensionRatio {
                TensionBar(ratio: tension)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var feelsLike: String? {
        model.today?.feelsLike ?? profile.latestTransit?.feelsLike
    }

    /// "Mon, Sep 7 at 1:05 AM", in the zone the reading was cast for.
    private var readingStamp: String {
        let formatter = DateFormatter()
        formatter.timeZone = model.readingZone
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM jmm")
        return formatter.string(from: model.readingTime)
    }

    /// Weather names the place you are standing in, so this is where the
    /// person is, never where they were born: this device's own location on
    /// your page, the transit location on everyone else's. With neither, the
    /// handle stands in rather than a place we cannot vouch for.
    private var subtitle: String {
        if isPrimary, let here = device.placeName {
            return here
        }
        return profile.currentLocationName ?? "@\(profile.username)"
    }

    private var temperature: String {
        guard let tii = model.today?.tii ?? profile.latestTransit?.tii else { return "--°" }
        return "\(Int(tii.rounded()))°"
    }

    // MARK: - Body states

    @ViewBuilder
    private var content: some View {
        forecast

        // While the forecast is still on its first spinner, that one spinner
        // speaks for the whole screen.
        if model.state != .loading, model.state != .idle {
            transits
        }
    }

    @ViewBuilder
    private var forecast: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.large)
                .tint(Theme.spinner)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)

        case let .failed(message):
            WeatherCard {
                WeatherCardHeader(icon: "exclamationmark.triangle", title: "No forecast")
                    .padding(.bottom, 8)

                Text(message)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Try again") {
                    Task { await model.load(profile: profile) }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 10)
            }

        case .loaded:
            if let today = model.today, let high = model.high, let low = model.low {
                TodaySummaryCard(day: today)
                ForecastCard(days: model.days, low: low, high: high)
            } else {
                WeatherCard {
                    Text("No forecast days came back for this profile.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    /// The transit report is a slower request than the forecast, so it lands
    /// under the cards on its own schedule instead of holding them back.
    @ViewBuilder
    private var transits: some View {
        switch model.transitsState {
        case .idle, .failed:
            EmptyView()

        case .loading:
            WeatherCard {
                WeatherCardHeader(icon: "circle.hexagongrid", title: "Active transits")

                ProgressView()
                    .tint(Theme.spinner)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }

        case .loaded:
            ActiveTransitsCard(
                aspects: model.activeAspects,
                retrograde: model.retrogradeObjects,
                positions: model.positions
            )
        }
    }
}

/// How much of the day's intensity is friction rather than flow, as the
/// engine's tension ratio. A short track and a number, nothing else: it is a
/// footnote to the reading above it, not a second headline.
struct TensionBar: View {

    /// 0…1 from the transit engine.
    let ratio: Double

    private var percent: Int { Int((min(max(ratio, 0), 1) * 100).rounded()) }

    private let width: CGFloat = 132
    private let track: CGFloat = 4

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(width: width, height: track)

                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: max(width * CGFloat(min(max(ratio, 0), 1)), track), height: track)
            }

            Text("Tension \(percent)%")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tension \(percent) percent")
    }
}
