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
    /// Watched for a tapped push about a like or a follow, which opens
    /// Activity.
    @ObservedObject private var push = PushNotifications.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection = ""
    @State private var showsList = false
    @State private var showsSearch = false
    /// Settings is on the profile list's toolbar, which cannot be opened until
    /// a profile exists. Presented from here as well so the empty state can
    /// reach it — signing out is on it.
    @State private var showsSettings = false
    /// The still-web screen on show, if any, and which one. Named rather than
    /// a bare flag: the WebView is shared and would otherwise open wherever it
    /// was last left.
    @State private var webDestination: WebDestination?
    @State private var showsAlertsOffer = false
    @State private var skyStates: [String: SkyState] = [:]

    /// A first profile, made from the empty state: there is no list to open
    /// the plus from until one exists.
    @State private var showsNewProfile = false
    @State private var createdProfile: ProfileSummary?

    /// "Which chart is yours?", while the account owns charts and none of
    /// them is marked as its own.
    @State private var showsPrimaryPrompt = false
    /// Set when that sheet sent the reader to make their chart: whatever the
    /// new-profile form makes next is the account's own.
    @State private var createsOwnChart = false

    /// The profile the ••• menu opened the edit sheet for. Presented from
    /// here rather than from the page: the pager tears its pages down as they
    /// scroll out, and a sheet owned by one of them goes with it.
    @State private var editing: ProfileSummary?

    /// Bumped per profile when its birth data is saved. It rides in the
    /// page's `id`, so the page is rebuilt and its forecast recast against
    /// the new chart — the profile summary alone can come back identical
    /// after an edit that only moved the birthplace.
    @State private var editVersions: [String: Int] = [:]

    /// The social sheets a page asks for, presented from here for the same
    /// reason Edit is: a sheet owned by a pager page goes with the page.
    @State private var showsActivity = false
    /// The chats. Which one to open, if any, waits in `ChatStore.pendingRoute`
    /// for the screen to take when it is up.
    @State private var showsChats = false
    @State private var peopleTarget: PeopleSheet.Target?
    @State private var reporting: ProfileSummary?
    @State private var blocking: ProfileSummary?
    /// Asked before it happens, from "Following" and from the ••• alike: an
    /// unfollow takes the page out of the pager under the reader's thumb.
    @State private var unfollowing: ProfileSummary?

    /// Primary profile first, the way Weather keeps My Location at page one,
    /// then Favourites, then the rest of the owner's profiles and the followed
    /// ones. The model builds the same groups the list screen draws and
    /// flattens them here, so the pages come in the order the cards do —
    /// including whatever order they were dragged into.
    private var profiles: [ProfileSummary] {
        model.orderedProfiles
    }

    /// Which profiles this account owns, taken from the model's own split
    /// rather than from each profile's `is_own`: the API has reported an
    /// owner's own primary profile as `is_own: false`, and trusting that
    /// would offer its owner "Unfollow" instead of "Edit Profile".
    private var ownedIds: Set<String> {
        model.ownedProfileIds
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                // The launch mark, not a spinner: the profile list is the
                // first request of a cold launch, and one that takes longer
                // to answer than `RootView`'s patience used to leave a bare
                // spinner on an empty screen behind the fading splash. Same
                // mark, same place, so the handover has nothing to see and a
                // slow start reads as the app still opening.
                SplashView(label: L("common.loading"))

            case .signedOut:
                placeholder {
                    message(
                        icon: "person.crop.circle.badge.questionmark",
                        title: L("home.notSignedIn"),
                        body: L("home.notSignedInBody"),
                        action: L("home.openSignIn"),
                        perform: { webDestination = .home }
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
                    // Its own screen rather than a bare message, because with
                    // no pager there is no bottom bar and no way to reach the
                    // list's toolbar: the plus, search and Settings have to be
                    // on this screen or they are on none.
                    WeatherEmptyState(
                        onCreateProfile: { showsNewProfile = true },
                        onOpenSearch: { showsSearch = true },
                        onOpenSettings: { showsSettings = true }
                    )
                } else {
                    pager
                }
            }
        }
        .task {
            // Asked here rather than at launch: the permission sheet makes
            // sense over the screen whose label it fills in.
            DeviceLocation.shared.start()
            // A push tapped before this screen existed: the app was launched
            // by it, and Activity goes up without waiting for the list.
            if push.opensActivity { openActivityFromPush() }
            if push.opensChat != nil { openChatFromPush() }
            await model.load()
            syncSelection()
            await SocialStore.shared.refreshUnread()
            await ChatStore.shared.refreshUnread()
            await PushNotifications.shared.refresh()
            await refreshAlerts()
            await offerNext()
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
                // Someone may have liked, followed or written while the app
                // was away.
                await SocialStore.shared.refreshUnread()
                await ChatStore.shared.refreshUnread()
                await PushNotifications.shared.refresh()
                await refreshAlerts()
                // An app left running for days never reruns `.task`, and the
                // question is asked once a day, not once a launch.
                offerPrimary()
            }
        }
        .onChange(of: auth.session) { _, session in
            Task {
                // Signing out has to take the queue with it: the alerts name a
                // profile this device can no longer read.
                if session == nil {
                    await CategoryAlerts.shared.reset()
                    SocialStore.shared.reset()
                    ChatStore.shared.reset()
                    PrimaryPromptSchedule.reset()
                }
                await model.load()
                await SocialStore.shared.refreshUnread()
                await ChatStore.shared.refreshUnread()
                // A new account on this phone: its pushes come here now.
                await PushNotifications.shared.refresh()
                await refreshAlerts()
            }
        }
        .onChange(of: push.opensActivity) { _, opens in
            if opens { openActivityFromPush() }
        }
        .onChange(of: push.opensChat) { _, chatId in
            if chatId != nil { openChatFromPush() }
        }
        .onChange(of: model.profiles) { _, profiles in
            // A fresh listing carries the server's like counts; whatever was
            // tapped before it is now in them.
            SocialStore.shared.adopt(profiles)
            syncSelection()
            // A brand-new account reaches this screen with nothing on it; the
            // offer waits for the first profile rather than being spent on an
            // empty sky.
            Task { await offerNext() }
        }
        // The location prompt goes up from the same `task` as the offer, so on
        // a first run the offer is held back until that one is answered.
        .onChange(of: location.isSettled) { _, settled in
            guard settled else { return }
            Task { await offerNext() }
        }
        // Whatever the first load settles on — pages, an empty state or an
        // error — is worth more than the splash standing in front of it.
        .onChange(of: model.state) { _, state in
            guard state != .idle, state != .loading else { return }
            AppLaunch.shared.markContentReady()
        }
        // The list suspends the pages' skies while it is up, and resumes them
        // as it goes. Cleared from here as well, because a sky left frozen
        // because one disappear did not land is worse than a redundant call.
        .onChange(of: showsList) { _, isOpen in
            guard !isOpen else { return }
            SkyPlayerPool.shared.setPlaying(true, variant: .screen)
        }
        // A sheet, not a cover: with the toolbar down to one Settings
        // button, a swipe down is how the list is left.
        .sheet(isPresented: $showsList) { listScreen }
        .sheet(isPresented: $showsAlertsOffer) {
            CategoryAlertsOffer(
                profile: primaryProfile,
                onFinish: {
                    showsAlertsOffer = false
                    // The same permission covers pushes: granted here, the
                    // phone can be registered for likes and follows now.
                    Task { await PushNotifications.shared.refresh() }
                }
            )
        }
        .sheet(isPresented: $showsSearch) { searchScreen }
        .sheet(isPresented: $showsSettings) {
            SettingsView(skyState: visibleState)
        }
        .sheet(isPresented: $showsNewProfile, onDismiss: openCreatedProfile) {
            ProfileEditSheet(skyState: visibleState) { createdProfile = $0 }
        }
        .sheet(isPresented: $showsPrimaryPrompt, onDismiss: primaryPromptClosed) {
            PrimaryProfilePrompt(
                profiles: model.ownProfiles,
                onChoose: { profile in
                    let error = await model.claimPrimary(profile)
                    if error == nil {
                        // Their own chart is page one now; land on it, and
                        // move the alerts, which follow the primary, onto it.
                        selection = profile.profileId
                        await refreshAlerts()
                    }
                    return error
                },
                onAddOwn: {
                    createsOwnChart = true
                    showsPrimaryPrompt = false
                },
                onFinish: { showsPrimaryPrompt = false }
            )
        }
        .sheet(isPresented: $showsActivity) {
            ActivityScreen(
                list: model,
                skyState: visibleState ?? .calm,
                onFindPeople: {
                    // After the sheet has gone: two presentations in one
                    // frame and SwiftUI drops the second.
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        showsSearch = true
                    }
                },
                onOpenSaved: { selection = $0 }
            )
        }
        .sheet(isPresented: $showsChats) {
            ChatsScreen(
                list: model,
                skyState: visibleState ?? .calm,
                onOpenSaved: { selection = $0 },
                onBlocked: {
                    // A block takes the follows between the two with it.
                    Task {
                        await model.load(showSpinner: false)
                        syncSelection()
                    }
                }
            )
        }
        .sheet(item: $peopleTarget) { target in
            PeopleSheet(
                target: target,
                list: model,
                skyState: visibleState ?? .calm,
                onOpenSaved: { selection = $0 }
            )
        }
        .sheet(item: $reporting) { profile in
            ReportSheet(profile: profile) { blocked in
                if blocked { removeBlocked(profile) }
            }
        }
        .blockConfirmation($blocking) { profile in
            removeBlocked(profile)
        }
        .alert(
            L("unfollow.title", unfollowing?.profileName ?? ""),
            isPresented: Binding(
                get: { unfollowing != nil },
                set: { if !$0 { unfollowing = nil } }
            ),
            presenting: unfollowing
        ) { profile in
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("weather.unfollow"), role: .destructive) {
                Task { await model.unfollow(profile) }
            }
        } message: { _ in
            Text(L("unfollow.body"))
        }
        .fullScreenCover(item: $webDestination) { WebScreen(destination: $0) }
    }

    /// A block severs every follow between the two accounts, so the chart it
    /// was made from leaves the pager: reloaded rather than removed by hand,
    /// because the block may have taken other charts of the same owner too.
    private func removeBlocked(_ profile: ProfileSummary) {
        Task {
            await model.load(showSpinner: false)
            syncSelection()
        }
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
                    onUnfollow: isOwn ? nil : { unfollowing = $0 },
                    // Everyone the compatibility card could pair this page
                    // with. The list is already loaded, so the card asks the
                    // API for nothing but the report itself.
                    partners: profiles.filter { $0.profileId != profile.profileId },
                    onFindPeople: { showsSearch = true },
                    onOpenPeople: { profile, tab in peopleTarget = PeopleSheet.Target(profile: profile, tab: tab) },
                    onOpenActivity: { showsActivity = true },
                    onOpenChats: { showsChats = true },
                    onMessage: isOwn ? nil : { openChat(with: $0) },
                    followingCount: isOwn ? model.followedProfiles.count : nil,
                    onReport: isOwn ? nil : { reporting = $0 },
                    onBlock: isOwn ? nil : { blocking = $0 }
                )
                .id("\(profile.profileId)#\(editVersions[profile.profileId] ?? 0)")
            }
            .onPreferenceChange(SkyStateKey.self) { skyStates = $0 }
        }
        .sheet(item: $editing) { profile in
            ProfileEditSheet(
                profile: profile,
                skyState: visibleState,
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
    private var visibleState: SkyState? {
        if let reported = skyStates[selection] { return reported }
        guard let profile = profiles.first(where: { $0.profileId == selection }) else { return nil }
        return SkyState(
            label: profile.latestTransit?.feelsLike,
            zone: TiiZone(tii: profile.latestTransit?.tii ?? 0)
        )
    }

    private var listScreen: some View {
        ProfileListScreen(
            model: model,
            onSelect: { profile in
                selection = profile.profileId
                showsList = false
            },
            skyState: visibleState
        )
    }

    private var searchScreen: some View {
        ProfileSearchScreen(
            list: model,
            onSelect: { profile in
                selection = profile.profileId
                showsSearch = false
            },
            // The empty state has no page to take a colour from, so the calm
            // sky stands in: left nil, the sheet's glass frosts the window's
            // own white instead of a sky and its white text stops reading.
            skyState: visibleState ?? .calm
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
        guard auth.isSignedIn, !profiles.isEmpty, !showsAlertsOffer, !coversScreen else { return }
        guard location.isSettled else { return }
        await CategoryAlerts.shared.syncAuthorization()
        // Asked again after the wait: another trigger can have put a sheet up
        // in the meantime, and SwiftUI would drop this one on top of it.
        guard CategoryAlerts.shared.shouldOffer, !coversScreen else { return }
        showsAlertsOffer = true
    }

    /// The questions this screen puts of its own accord, one at a time: whose
    /// chart the account is first, because the alerts are scheduled for that
    /// chart, then the alerts. The second waits for the first to go down.
    private func offerNext() async {
        if offerPrimary() { return }
        await offerAlerts()
    }

    /// Puts "Which chart is yours?" up while the account owns charts and none
    /// of them is its own, once a day. Answers whether it went up.
    ///
    /// Behind the location prompt, like the alerts offer: that one is the
    /// system's own and goes up first, and a sheet under it is read blind.
    @discardableResult
    private func offerPrimary() -> Bool {
        guard auth.isSignedIn, model.needsPrimary, !showsPrimaryPrompt, !coversScreen else { return false }
        guard location.isSettled, PrimaryPromptSchedule.isDue else { return false }
        PrimaryPromptSchedule.markShown()
        showsPrimaryPrompt = true
        return true
    }

    /// After "Which chart is yours?" has gone, however it went: the new-profile
    /// form if the reader went to make their chart, else the next question.
    /// From `onDismiss`, so the sheet is fully down before another goes up.
    private func primaryPromptClosed() {
        if createsOwnChart {
            showsNewProfile = true
        } else {
            Task { await offerNext() }
        }
    }

    /// Anything already up over the pages, which a question of the screen's
    /// own must not land on: one sheet at a time is all SwiftUI presents.
    private var coversScreen: Bool {
        showsList || showsSearch || showsSettings || showsNewProfile || showsActivity || showsChats
            || showsAlertsOffer || showsPrimaryPrompt || peopleTarget != nil || editing != nil
            || reporting != nil || blocking != nil || unfollowing != nil || webDestination != nil
    }

    /// A tapped push about a like or a follow: Activity, over whatever sheet
    /// was up. The other sheet goes first, because two presentations in one
    /// frame and SwiftUI drops the second.
    private func openActivityFromPush() {
        push.opensActivity = false
        guard auth.isSignedIn, !showsActivity else { return }
        let covered = closeSheets() || showsChats
        showsChats = false
        Task {
            if covered { try? await Task.sleep(for: .milliseconds(450)) }
            showsActivity = true
        }
    }

    /// A tapped push about a message: the chats, opened on that chat, over
    /// whatever sheet was up. Already open, they take it from the store.
    private func openChatFromPush() {
        guard let chatId = push.opensChat else { return }
        push.opensChat = nil
        guard auth.isSignedIn else { return }
        openChats(on: .chatId(chatId))
    }

    /// "Message" in the ••• of somebody's own chart.
    private func openChat(with profile: ProfileSummary) {
        openChats(on: .profile(profile))
    }

    private func openChats(on route: ChatRoute) {
        ChatStore.shared.pendingRoute = route
        guard !showsChats else { return }
        let covered = closeSheets() || showsActivity
        showsActivity = false
        Task {
            if covered { try? await Task.sleep(for: .milliseconds(450)) }
            showsChats = true
        }
    }

    /// Puts away the sheets a push opens over, and says whether any was up:
    /// two presentations in one frame and SwiftUI drops the second, so the
    /// next one waits for this one to go.
    private func closeSheets() -> Bool {
        let covered = showsList || showsSearch || showsSettings || showsNewProfile || showsPrimaryPrompt
            || peopleTarget != nil
        showsList = false
        showsSearch = false
        showsSettings = false
        showsNewProfile = false
        showsPrimaryPrompt = false
        peopleTarget = nil
        return covered
    }

    /// Turns the pager to a profile the empty state just made, once the list
    /// holding its page has come back. Made from "Which chart is yours?", it
    /// is the account's own chart as well.
    private func openCreatedProfile() {
        // Read and cleared either way: a form closed without saving leaves
        // the question for another day.
        let isOwnChart = createsOwnChart
        createsOwnChart = false
        guard let created = createdProfile else { return }
        createdProfile = nil

        Task {
            // A failure is logged by the model, and the question comes back.
            if isOwnChart { _ = await model.claimPrimary(created) }
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
