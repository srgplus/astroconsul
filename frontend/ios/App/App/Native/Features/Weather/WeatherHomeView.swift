import SwiftUI

/// The app's home screen: cosmic weather for one profile at a time, swiped
/// like Weather's cities. There is no tab bar — the bottom bar's two buttons
/// reach the chart (web) and the profile list.
struct WeatherHomeView: View {

    @StateObject private var model = ProfileListViewModel()
    @ObservedObject private var auth = AuthStore.shared
    @ObservedObject private var strings = L10n.shared
    /// Watched only for `isSettled`: the notification offer waits until the
    /// location question has been answered before putting its own.
    @ObservedObject private var location = DeviceLocation.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection = ""
    @State private var showsList = false
    @State private var showsSearch = false
    @State private var showsWeb = false
    @State private var showsAlertsOffer = false
    @State private var skyZones: [String: TiiZone] = [:]

    /// A first profile, made from the empty state: there is no list to open
    /// the plus from until one exists.
    @State private var showsNewProfile = false
    @State private var createdProfile: ProfileSummary?

    /// The profile the ••• menu opened the edit sheet for. Presented from
    /// here rather than from the page: the pager tears its pages down as they
    /// scroll out, and a sheet owned by one of them goes with it.
    @State private var editing: ProfileSummary?

    /// Bumped per profile when its birth data is saved. It rides in the
    /// page's `id`, so the page is rebuilt and its forecast recast against
    /// the new chart — the profile summary alone can come back identical
    /// after an edit that only moved the birthplace.
    @State private var editVersions: [String: Int] = [:]

    /// Primary profile first, the way Weather keeps My Location at page one,
    /// then the rest of the owner's profiles and the followed ones. The model
    /// pins the primary for both this pager and the list, so the order here is
    /// just its two sections in order.
    private var profiles: [ProfileSummary] {
        model.ownProfiles + model.followedProfiles
    }

    /// Which profiles this account owns, taken from the model's own split
    /// rather than from each profile's `is_own`: the API has reported an
    /// owner's own primary profile as `is_own: false`, and trusting that
    /// would offer its owner "Unfollow" instead of "Edit Profile".
    private var ownedIds: Set<String> {
        Set(model.ownProfiles.map(\.profileId))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                placeholder { ProgressView().controlSize(.large).tint(Theme.spinner) }

            case .signedOut:
                placeholder {
                    message(
                        icon: "person.crop.circle.badge.questionmark",
                        title: L("home.notSignedIn"),
                        body: L("home.notSignedInBody"),
                        action: L("home.openSignIn"),
                        perform: { showsWeb = true }
                    )
                }

            case let .failed(text):
                placeholder {
                    message(
                        icon: "exclamationmark.triangle",
                        title: L("home.loadFailed"),
                        body: text,
                        action: L("common.tryAgain"),
                        perform: { Task { await model.load() } }
                    )
                }

            case .loaded:
                if profiles.isEmpty {
                    placeholder {
                        message(
                            icon: "person.2",
                            title: L("home.noProfiles"),
                            body: L("home.noProfilesBody"),
                            action: L("home.createProfile"),
                            perform: { showsNewProfile = true }
                        )
                    }
                } else {
                    pager
                }
            }
        }
        .task {
            // Asked here rather than at launch: the permission sheet makes
            // sense over the screen whose label it fills in.
            DeviceLocation.shared.start()
            await model.load()
            syncSelection()
            await refreshAlerts()
            await offerAlerts()
        }
        // The category alerts are scheduled days ahead, so the schedule has to
        // be topped up from a live forecast whenever the app is in hand. The
        // scheduler throttles itself; calling it on every foreground is free.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                // The system cancels whatever is in flight when the app is
                // suspended, and `.task` does not run again on the way back —
                // the screen never disappeared. Without this the list sat on
                // its spinner until it was left and reopened.
                if model.needsReload {
                    await model.load()
                    syncSelection()
                }
                await refreshAlerts()
            }
        }
        .onChange(of: auth.session) { _, session in
            Task {
                // Signing out has to take the queue with it: the alerts name a
                // profile this device can no longer read.
                if session == nil { await CategoryAlerts.shared.reset() }
                await model.load()
                await refreshAlerts()
            }
        }
        .onChange(of: model.profiles) { _, _ in
            syncSelection()
            // A brand-new account reaches this screen with nothing on it; the
            // offer waits for the first profile rather than being spent on an
            // empty sky.
            Task { await offerAlerts() }
        }
        // The location prompt goes up from the same `task` as the offer, so on
        // a first run the offer is held back until that one is answered.
        .onChange(of: location.isSettled) { _, settled in
            guard settled else { return }
            Task { await offerAlerts() }
        }
        // Whatever the first load settles on — pages, an empty state or an
        // error — is worth more than the splash standing in front of it.
        .onChange(of: model.state) { _, state in
            guard state != .idle, state != .loading else { return }
            AppLaunch.shared.markContentReady()
        }
        // A sheet, not a cover: with the toolbar down to one Settings
        // button, a swipe down is how the list is left.
        .sheet(isPresented: $showsList) { listScreen }
        .sheet(isPresented: $showsAlertsOffer) {
            CategoryAlertsOffer(
                profile: primaryProfile,
                onFinish: { showsAlertsOffer = false }
            )
        }
        .sheet(isPresented: $showsSearch) { searchScreen }
        .sheet(isPresented: $showsNewProfile, onDismiss: openCreatedProfile) {
            ProfileEditSheet(skyZone: visibleZone) { createdProfile = $0 }
        }
        .fullScreenCover(isPresented: $showsWeb) { WebScreen() }
    }

    private var pager: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top

            WeatherPager(
                profiles: profiles,
                selection: $selection,
                primaryProfileId: model.primaryProfileId,
                bottomInset: geometry.safeAreaInsets.bottom,
                onOpenSearch: { showsSearch = true },
                onOpenList: { showsList = true }
            ) { profile in
                let isOwn = ownedIds.contains(profile.profileId)

                CosmicWeatherView(
                    profile: profile,
                    topInset: topInset,
                    bottomInset: geometry.safeAreaInsets.bottom,
                    isPrimary: profile.profileId == model.primaryProfileId,
                    onEdit: isOwn ? { editing = $0 } : nil,
                    onUnfollow: isOwn ? nil : { profile in Task { await model.unfollow(profile) } }
                )
                .id("\(profile.profileId)#\(editVersions[profile.profileId] ?? 0)")
            }
            .onPreferenceChange(SkyZoneKey.self) { skyZones = $0 }
        }
        .sheet(item: $editing) { profile in
            ProfileEditSheet(
                profile: profile,
                skyZone: visibleZone,
                onSaved: {
                    editVersions[profile.profileId, default: 0] += 1
                    Task { await model.load(showSpinner: false) }
                },
                onDeleted: {
                    Task { await model.load(showSpinner: false) }
                }
            )
        }
    }

    /// The visible page's zone, so the list's glass matches the sky it came
    /// from rather than sitting on flat grey. The page reports its own, which
    /// is the forecast's reading; the profile's stored TII is the fallback
    /// until the forecast lands, and can be a zone out of date.
    private var visibleZone: TiiZone? {
        if let reported = skyZones[selection] { return reported }
        guard let profile = profiles.first(where: { $0.profileId == selection }) else { return nil }
        return TiiZone(tii: profile.latestTransit?.tii ?? 0)
    }

    private var listScreen: some View {
        ProfileListScreen(
            model: model,
            onSelect: { profile in
                selection = profile.profileId
                showsList = false
            },
            skyZone: visibleZone,
            onOpenWeb: {
                showsList = false
                showsWeb = true
            }
        )
    }

    private var searchScreen: some View {
        ProfileSearchScreen(
            list: model,
            onSelect: { profile in
                selection = profile.profileId
                showsSearch = false
            },
            skyZone: visibleZone
        )
    }

    /// Rebuilds the notification schedule for the profile marked as the
    /// owner's. Only that one: a person following a dozen charts does not want
    /// a dozen banners a day.
    private func refreshAlerts() async {
        guard auth.isSignedIn else { return }
        await CategoryAlerts.shared.refresh(profile: primaryProfile)
    }

    /// The profile the notifications are for: the one marked as the owner's,
    /// falling back to whatever is first.
    private var primaryProfile: ProfileSummary? {
        profiles.first { $0.profileId == model.primaryProfileId } ?? profiles.first
    }

    /// Puts the notification question, once, on the first run that gets as far
    /// as a weather screen with something on it.
    ///
    /// This replaces the bare `requestAuthorization` that `refreshAlerts` used
    /// to make from the same `task`. iOS grants one permission sheet per
    /// install, and spending it cold — over a screen the person has just met,
    /// with nothing said about what the alerts are — is how an app ends up
    /// permanently denied with no way back except iOS Settings. The card says
    /// what they are first, and only "Turn them on" spends the sheet.
    ///
    /// `shouldOffer` holds the once-only part; this holds the *when*, which is
    /// after there is a reading on the screen to explain what is being
    /// offered, and after the location prompt has been dealt with.
    private func offerAlerts() async {
        guard auth.isSignedIn, !profiles.isEmpty, !showsAlertsOffer else { return }
        guard location.isSettled else { return }
        await CategoryAlerts.shared.syncAuthorization()
        guard CategoryAlerts.shared.shouldOffer else { return }
        showsAlertsOffer = true
    }

    /// Turns the pager to a profile the empty state just made, once the list
    /// holding its page has come back.
    private func openCreatedProfile() {
        guard let created = createdProfile else { return }
        createdProfile = nil

        Task {
            await model.load(showSpinner: false)
            selection = created.profileId
            await refreshAlerts()
        }
    }

    /// Keeps the visible page pointed at a profile that still exists, falling
    /// back to the primary one.
    private func syncSelection() {
        guard !profiles.isEmpty else {
            selection = ""
            return
        }
        if profiles.contains(where: { $0.profileId == selection }) { return }
        selection = model.primaryProfileId ?? profiles[0].profileId
    }

    // MARK: - States

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            content()
        }
    }

    private func message(
        icon: String,
        title: String,
        body: String,
        action: String,
        perform: @escaping () -> Void
    ) -> some View {
        VStack(spacing: Theme.Spacing.base) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textDim)

            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.text)

            Text(body)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)

            Button(action, action: perform)
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.top, 4)
        }
        .padding(Theme.Spacing.section)
    }
}
