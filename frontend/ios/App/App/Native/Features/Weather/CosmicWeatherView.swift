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
    @ObservedObject private var strings = L10n.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSettings = false
    /// The forecast row that was tapped, and so the day whose sheet is open.
    @State private var selectedDay: ForecastDay?

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
                        // In the scrolling content and not pinned over it, so
                        // it leaves with the header it belongs to. An overlay
                        // rather than a row, so it costs the hero no height:
                        // it sits in the band beside the status bar that is
                        // otherwise empty.
                        .overlay(alignment: .topTrailing) {
                            // No inset of its own: the scroll view is already
                            // laid out below the status bar, so the top of the
                            // content is the top of the header.
                            profileMenu
                        }

                    // A re-read keeps the reading it has on screen — there
                    // is nothing better to put there — so the cards step back
                    // while it is stale, and stop taking taps that would open
                    // a detail sheet on a row about to be replaced.
                    content
                        .opacity(model.isRefreshing ? 0.45 : 1)
                        .allowsHitTesting(!model.isRefreshing)
                        .animation(.easeInOut(duration: 0.2), value: model.isRefreshing)
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
        .sheet(item: $selectedDay) { day in
            ForecastDayDetailSheet(
                profile: profile,
                day: day,
                isToday: day.date == ForecastDay.todayKey(in: model.readingZone),
                moment: moment(for: day),
                model: dayModel()
            )
        }
        .sheet(isPresented: $showsSettings) {
            TransitSettingsSheet(
                current: model.chosen ?? model.readingMoment,
                isChosen: model.chosen != nil,
                onApply: { moment in
                    Task { await model.choose(moment, profile: profile) }
                },
                onReset: {
                    Task { await model.choose(nil, profile: profile) }
                }
            )
        }
        .task {
            // A seeded model (previews, harness) is already loaded.
            guard model.state == .idle else { return }
            await model.load(profile: profile)
        }
        // A reading in flight when the app is suspended comes back cancelled,
        // and `.task` does not run again on the way in — the page never
        // disappeared. Picked up here so the skeletons resolve on their own.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, model.needsReload else { return }
            Task { await model.load(profile: profile) }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if let symbol = place.source.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }

                Text(place.name.uppercased())
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

                if isBusy {
                    MinimalSpinner()
                } else {
                    // The stamp is the way into the settings, so it says so.
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            // No plate behind it. The chevron already says the stamp is a
            // control, and a capsule saying it a second time was the only
            // thing in the hero standing on one.
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .padding(.top, 6)
            .animation(.easeInOut(duration: 0.2), value: isBusy)
            .contentShape(Capsule())
            // A tap gesture rather than a Button: inside the pager's scroll
            // view a plain-styled Button never fires, which is the same
            // conflict SmallSwitch was drawn from shapes to avoid.
            .onTapGesture { showsSettings = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(L("weather.momentHint"))

            Text(temperature)
                .font(.system(size: 92, weight: .ultraLight, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.leading, 14)   // optical centring: the ° hangs right
                .padding(.vertical, -8)

            Text(Astro.feels(feelsLike) ?? " ")
                .font(.system(size: 21, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            if let headline = Astro.headline(for: feelsLike, at: model.readingTime, in: model.readingZone) {
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
                        Label(L("weather.editProfile"), systemImage: "square.and.pencil")
                    }
                }

                if let onUnfollow {
                    Button(role: .destructive) {
                        onUnfollow(profile)
                    } label: {
                        Label(L("weather.unfollow"), systemImage: "person.badge.minus")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Self.menuButton, height: Self.menuButton)
                    .contentShape(Circle())
            }
            // The page tints everything under it white so marks read on the
            // sky. The menu it opens is not on the sky — it is a system popup
            // in the system's own appearance — so a white tint left its icons
            // white beside black labels. Ink, which resolves either way.
            .tint(Theme.text)
            .weatherGlass(in: .circle, interactive: true)
            .accessibilityLabel(L("weather.profileOptions"))
        }
    }

    private static let menuButton: CGFloat = 36

    /// Anything the reader should see the app working on: the first load of
    /// either half, and a re-read for a moment they picked.
    private var isBusy: Bool {
        model.state == .loading || model.transitsState == .loading || model.isRefreshing
    }

    private var feelsLike: String? {
        model.today?.feelsLike ?? profile.latestTransit?.feelsLike
    }

    /// "Mon, Sep 7 at 1:05 AM", in the zone the reading was cast for and in
    /// the language the app is set to.
    private var readingStamp: String {
        LocalizedDate.string(model.readingTime, template: "EEE d MMM jmm", in: model.readingZone)
    }

    /// Where a hero label came from, which is what its icon says. Weather
    /// only earns the arrow for a fix off the device; a place someone typed
    /// gets the crossed-out one, so the two are never mistaken for each
    /// other, and a handle standing in for a place gets no icon at all —
    /// it is not a location and should not be dressed as one.
    private enum PlaceSource {
        case device
        case typed
        case handle

        var symbol: String? {
            switch self {
            case .device: return "location.fill"
            case .typed: return "location.slash"
            case .handle: return nil
            }
        }
    }

    /// Weather names the place you are standing in, so this is where the
    /// person is, never where they were born: this device's own location on
    /// your page, the transit location on everyone else's. With neither, the
    /// handle stands in rather than a place we cannot vouch for.
    private var place: (name: String, source: PlaceSource) {
        // A place the reader chose outranks both: they are asking what the
        // sky looks like from there, not from here.
        if let chosen = model.chosen?.locationName {
            return (chosen, .typed)
        }
        if isPrimary, let here = device.placeName {
            return (here, .device)
        }
        // Whatever the profile carries was set by hand on the web, so it is
        // typed however it got here.
        if let saved = profile.currentLocationName {
            return (saved, .typed)
        }
        return ("@\(profile.username)", .handle)
    }

    private var temperature: String {
        guard let tii = model.today?.tii ?? profile.latestTransit?.tii else { return "--°" }
        return "\(Int(tii.rounded()))°"
    }

    // MARK: - One day

    /// A forecast day, spelled as a moment to read: that date, at the clock
    /// time and in the place this page is already reading. The same request
    /// the settings sheet would send if the reader moved only the date wheel.
    private func moment(for day: ForecastDay) -> TransitMoment {
        var moment = model.readingMoment
        moment.instant = day.instant(at: moment.instant, in: moment.zone) ?? moment.instant
        return moment
    }

    /// A fresh model for the day sheet, so its request stands apart from this
    /// page's and neither overwrites the other.
    private func dayModel() -> CosmicWeatherViewModel {
        #if DEBUG
        // The harness has no account to read another day with, so a sheet
        // opened over a seeded page is seeded from the same report.
        if model.isSeeded { return model.seededCopy() }
        #endif
        return CosmicWeatherViewModel()
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
                WeatherCardHeader(icon: "exclamationmark.triangle", title: L("weather.noForecast"))
                    .padding(.bottom, 8)

                Text(message)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Button(L("common.tryAgain")) {
                    Task { await model.load(profile: profile) }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 10)
            }

        case .loaded:
            if let today = model.today, let high = model.high, let low = model.low {
                ForecastCard(days: model.days, low: low, high: high, zone: model.readingZone) { day in
                    selectedDay = day
                }

                if let moon = today.moonPhase {
                    MoonCard(phase: moon)
                }
            } else {
                WeatherCard {
                    Text(L("weather.noForecastDays"))
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
            // `now` is the moment the reading was cast for, not the clock:
            // every window bar marks where the reader is standing on the
            // transit's arc, and on a chosen day that is the day they chose.
            ActiveTransitsCard(
                aspects: model.activeAspects,
                retrograde: model.retrogradeObjects,
                positions: model.positions,
                now: model.readingTime
            )

            CosmicClimateCard(
                aspects: model.cosmicClimate,
                retrograde: model.retrogradeObjects,
                positions: model.positions,
                now: model.readingTime
            )

            ChartWheelCard(
                positions: model.positions,
                aspects: model.activeAspects,
                now: model.readingTime
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

            Text(L("weather.tension", percent))
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("weather.tensionA11y", percent))
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
            .accessibilityLabel(L("common.loading"))
    }
}
