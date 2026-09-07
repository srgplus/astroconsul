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

    /// What the ••• menu offers, and so what this page lets the viewer do:
    /// `onEdit` on a profile the account owns, `onUnfollow` on a followed one.
    /// Which of the two is handed in is the presenter's call — the page does
    /// not decide ownership for itself, because `is_own` has come back false
    /// on an owner's own primary profile and that would hide Edit from the
    /// person it belongs to.
    ///
    /// Both are handed up rather than acted on here: a sheet presented from
    /// inside a `TabView` page goes with the page when it scrolls away.
    var onEdit: ((ProfileSummary) -> Void)?
    var onUnfollow: ((ProfileSummary) -> Void)?

    @StateObject private var model: CosmicWeatherViewModel
    @ObservedObject private var device = DeviceLocation.shared

    init(
        profile: ProfileSummary,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        isPrimary: Bool = false,
        onEdit: ((ProfileSummary) -> Void)? = nil,
        onUnfollow: ((ProfileSummary) -> Void)? = nil
    ) {
        self.profile = profile
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.isPrimary = isPrimary
        self.onEdit = onEdit
        self.onUnfollow = onUnfollow
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
        onEdit: ((ProfileSummary) -> Void)? = nil,
        onUnfollow: ((ProfileSummary) -> Void)? = nil,
        model: @autoclosure @escaping () -> CosmicWeatherViewModel
    ) {
        self.profile = profile
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.isPrimary = isPrimary
        self.onEdit = onEdit
        self.onUnfollow = onUnfollow
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
        .overlay(alignment: .topTrailing) {
            profileMenu
                .padding(.top, topInset + 6)
                .padding(.trailing, 16)
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

            // Inset by the corner button's width on both sides so a long
            // name shrinks rather than sliding under the •••.
            Text(profile.profileName)
                .font(.system(size: 34, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, Self.menuButton)

            // A transit reading is a moment, not a day, so the hero says
            // which moment — in the profile's own zone, not the device's.
            // The spinner rides in the same capsule while the reading for
            // that moment is still being computed, so the stamp and its
            // progress are one thing rather than two.
            HStack(spacing: 7) {
                Text(readingStamp)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))

                if model.state == .loading || model.transitsState == .loading {
                    MinimalSpinner()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.16)))
            .padding(.top, 6)
            .animation(.easeInOut(duration: 0.2), value: model.transitsState)

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

    /// Weather puts its ••• in the same corner. With neither action wired up
    /// there is nothing to offer, so there is no button either.
    @ViewBuilder
    private var profileMenu: some View {
        if onEdit != nil || onUnfollow != nil {
            Menu {
                if let onEdit {
                    Button {
                        onEdit(profile)
                    } label: {
                        Label("Edit Profile", systemImage: "square.and.pencil")
                    }
                }

                if let onUnfollow {
                    Button(role: .destructive) {
                        onUnfollow(profile)
                    } label: {
                        Label("Unfollow", systemImage: "person.badge.minus")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Self.menuButton, height: Self.menuButton)
                    .contentShape(Circle())
            }
            .weatherGlass(in: .circle, interactive: true)
            .accessibilityLabel("Profile options")
        }
    }

    private static let menuButton: CGFloat = 36

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
        transits

        // The chart every reading above is cast against, so it closes the
        // screen rather than opening it: today first, the birth data last.
        // It draws nothing until the natal positions land.
        NatalChartCard(profile: profile, positions: model.positions.natal)
    }

    @ViewBuilder
    private var forecast: some View {
        switch model.state {
        case .idle, .loading:
            // Skeletons rather than a spinner or nothing: the cards keep their
            // place, so the reading fills in instead of shoving the page
            // around as each piece lands.
            WeatherSkeleton(kind: .summary)
            WeatherSkeleton(kind: .forecast)

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
                ForecastCard(days: model.days, low: low, high: high)

                if let moon = today.moonPhase {
                    MoonCard(phase: moon)
                }
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
            WeatherSkeleton(kind: .transits)

        case .loaded:
            ActiveTransitsCard(
                aspects: model.activeAspects,
                retrograde: model.retrogradeObjects,
                positions: model.positions
            )

            CosmicClimateCard(
                aspects: model.cosmicClimate,
                retrograde: model.retrogradeObjects,
                positions: model.positions
            )

            ChartWheelCard(positions: model.positions, aspects: model.activeAspects)
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

/// A thin rotating arc.
///
/// `ProgressView`'s spokes are a system alert's indicator: dropped on the sky
/// at 13pt they read as a stuck widget rather than as work in progress, and
/// the grey they are tinted with disappears on a dark sky where every other
/// mark in the hero is white.
struct MinimalSpinner: View {

    var size: CGFloat = 13
    var lineWidth: CGFloat = 1.6
    var color: Color = .white.opacity(0.75)

    @State private var turning = false

    /// Spelled out because the private `turning` makes the synthesized
    /// memberwise initializer private too, and the arc is used from other
    /// files.
    init(size: CGFloat = 13, lineWidth: CGFloat = 1.6, color: Color = .white.opacity(0.75)) {
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
    }

    var body: some View {
        Circle()
            // A gap, not a dash: the arc has to read as one line chasing its
            // own tail at this size.
            .trim(from: 0.06, to: 0.9)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
            .accessibilityLabel("Loading")
    }
}
