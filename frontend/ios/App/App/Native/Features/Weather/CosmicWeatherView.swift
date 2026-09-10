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
    /// Raised by Copy report and lowered two seconds later. Copying is
    /// otherwise invisible — the menu closes over it and the clipboard says
    /// nothing — so the page says it happened.
    @State private var didCopy = false

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
    private var state: SkyState {
        SkyState(
            label: model.today?.feelsLike ?? profile.latestTransit?.feelsLike,
            zone: TiiZone(tii: model.today?.tii ?? profile.latestTransit?.tii ?? 0)
        )
    }

    /// The gradient follows the state rather than the raw TII, so the colour
    /// and the footage can never disagree about which reading is on screen.
    private var zone: TiiZone { state.zone }

    var body: some View {
        ZStack {
            WeatherSky.gradient(for: zone)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: zone)

            SkyVideo(state: state)

            SkyScrim()
                .ignoresSafeArea()

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
        .overlay(alignment: .bottom) {
            if didCopy {
                Label(L("report.copied"), systemImage: "checkmark")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .weatherGlass(in: .capsule)
                    .padding(.bottom, WeatherBottomBar.height(bottomInset: bottomInset) + 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: didCopy)
        .sensoryFeedback(trigger: didCopy) { _, copied in copied ? .success : nil }
        // Lowered on its own rather than by a dismiss the reader has to find.
        // Keyed on the flag, so a second copy restarts the two seconds instead
        // of inheriting what was left of the first.
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
        .tint(.white)
        .preference(key: SkyStateKey.self, value: [profile.profileId: state])
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

            IntensityTension(
                intensity: model.today?.tii ?? profile.latestTransit?.tii,
                tension: model.today?.tensionRatio ?? profile.latestTransit?.tensionRatio
            )
            .padding(.top, 2)
            .padding(.bottom, 10)

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
        }
        .frame(maxWidth: .infinity)
    }

    /// Weather puts its ••• in the same corner. Copy report is in it on every
    /// page — the reading belongs to whoever is looking at it — and Edit or
    /// Unfollow join it depending on which one the presenter wired up.
    @ViewBuilder
    private var profileMenu: some View {
        Menu {
            Button {
                report.copyToClipboard()
                didCopy = true
            } label: {
                Label(L("report.copy"), systemImage: "doc.on.clipboard")
            }
            // Nothing has landed yet, so there would be nothing on the
            // clipboard but a heading.
            .disabled(report.isEmpty)

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

    /// What Copy report puts on the clipboard. A handle is not a place, so
    /// the reading is labelled with one only when the hero has one.
    private var report: ProfileReport {
        model.report(for: profile, place: place.source == .handle ? nil : place.name)
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
        NatalChartCard(
            profile: profile,
            positions: model.positions.natal,
            natalAspects: model.positions.natalAspects,
            transits: model.activeAspects,
            retrograde: model.retrogradeObjects,
            transitPositions: model.positions,
            now: model.readingTime
        )

        // Where those positions stand to each other. Under the table and not
        // above it: a row here names two bodies, and the table is where a
        // reader just looked them up.
        NatalAspectsCard(aspects: model.positions.natalAspects)
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
                now: model.readingTime,
                state: state
            )
        }
    }
}

/// The reading, as the two numbers it is actually made of.
///
/// Intensity is the TII: an index from 0 to 100. Not a temperature and not an
/// angle, so it wears no degree sign — the ° it used to carry was borrowed
/// from a screen this one is not. Tension is how much of that intensity is
/// friction rather than flow.
///
/// They stand side by side because neither answers the other's question: a
/// quiet day can be all friction and a strong day all flow. Folding them into
/// a single score would be the app saying hard days are worse days, which is
/// not ours to say.
struct IntensityTension: View {

    /// 0…100 from the transit engine. Nil until a reading has landed.
    let intensity: Double?

    /// 0…1 from the transit engine. Nil when the reading carries no split, in
    /// which case the intensity stands alone rather than beside a guess.
    let tension: Double?

    @ObservedObject private var strings = L10n.shared

    /// The tension is set at 65% of the intensity, and that ratio is the point
    /// of the pair rather than a taste. "100%" is four glyphs against two: at a
    /// shared size it outweighs the intensity on exactly the quiet days where
    /// tension matters least, and the hierarchy turns over.
    private static let intensitySize: CGFloat = 58
    private static let tensionSize: CGFloat = 38

    /// A column is wider than its bar so the longest label still sits inside
    /// it: ИНТЕНСИВНОСТЬ runs half again the length of INTENSITY.
    private static let column: CGFloat = 108
    private static let bar: CGFloat = 88
    /// Narrower than the column, so the two labels always have a gutter
    /// between them. ИНТЕНСИВНОСТЬ set at full size fills the column edge to
    /// edge and leaves the Russian pair reading as one long word; held to this
    /// it comes down a fraction of a point instead, which nobody reads and
    /// everybody can tell apart.
    private static let label: CGFloat = 96
    private static let track: CGFloat = 4
    private static let ruleWidth: CGFloat = 1.5
    private static let ruleHeight: CGFloat = 50

    /// Where a digit sits inside its line box, as a fraction of the point size.
    /// SF leaves more air above a big face than a small one, so aligning the
    /// boxes would leave the smaller number floating; these put the tops of the
    /// digits together instead, and hang the rule off the digits rather than
    /// off the box.
    private static let digitTop: CGFloat = 0.26
    private static let digitHeight: CGFloat = 0.70

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .top, spacing: 0) {
                number(intensityText, size: Self.intensitySize)

                if tension != nil {
                    rule

                    // Tops together, not baselines: at two sizes a shared
                    // baseline leaves the smaller number hanging off the
                    // bottom of the larger one.
                    number(tensionText, size: Self.tensionSize)
                        .padding(.top, (Self.intensitySize - Self.tensionSize) * Self.digitTop)
                }
            }

            HStack(spacing: 0) {
                meter(L("weather.intensityLabel"), fill: intensityFill, ink: 0.5)

                if tension != nil {
                    // Standing in for the rule, so the two rows keep step.
                    Color.clear.frame(width: Self.ruleWidth, height: 1)

                    meter(L("weather.tensionLabel"), fill: tensionFill, ink: 0.42)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }

    private func number(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .ultraLight, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: Self.column)
    }

    /// The hairline between the two numbers, centred on the digits.
    private var rule: some View {
        Capsule()
            .fill(.white.opacity(0.30))
            .frame(width: Self.ruleWidth, height: Self.ruleHeight)
            .padding(
                .top,
                Self.intensitySize * Self.digitTop
                    + (Self.intensitySize * Self.digitHeight - Self.ruleHeight) / 2
            )
    }

    /// A caps label and a bar filled by its own number — the intensity against
    /// 100, the tension against a whole. The tension's label is the fainter of
    /// the two, so the pair still reads left to right.
    private func meter(_ text: String, fill: CGFloat, ink: Double) -> some View {
        VStack(spacing: 6) {
            Text(text)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(ink))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.label)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: Self.bar, height: Self.track)

                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: max(Self.bar * fill, Self.track), height: Self.track)
            }
        }
        .frame(width: Self.column)
    }

    private var intensityText: String {
        guard let intensity else { return "--" }
        return "\(Int(intensity.rounded()))"
    }

    private var tensionText: String { "\(percent)%" }

    private var percent: Int { Int((tensionFill * 100).rounded()) }

    private var intensityFill: CGFloat { CGFloat(min(max((intensity ?? 0) / 100, 0), 1)) }

    private var tensionFill: CGFloat { CGFloat(min(max(tension ?? 0, 0), 1)) }

    /// One label for the pair: VoiceOver is reading a hero, not a table. And
    /// it says the words rather than the abbreviation — "TII 51" is nothing to
    /// anyone who cannot see what it is written on.
    private var spoken: String {
        var parts: [String] = []
        if let intensity {
            parts.append(L("weather.intensityValue", Int(intensity.rounded())))
        }
        if tension != nil {
            parts.append(L("weather.tensionA11y", percent))
        }
        return parts.isEmpty ? L("profiles.noReading") : parts.joined(separator: ", ")
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
