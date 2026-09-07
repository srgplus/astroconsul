import SwiftUI

/// The app's home screen: cosmic weather for one profile at a time, swiped
/// like Weather's cities. There is no tab bar — the bottom bar's two buttons
/// reach the chart (web) and the profile list.
struct WeatherHomeView: View {

    @StateObject private var model = ProfileListViewModel()
    @ObservedObject private var auth = AuthStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection = ""
    @State private var showsList = false
    @State private var showsSearch = false
    @State private var showsWeb = false
    @State private var skyZones: [String: TiiZone] = [:]

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
                        title: "Not signed in",
                        body: "Sign in to see your cosmic weather.",
                        action: "Open sign in",
                        perform: { showsWeb = true }
                    )
                }

            case let .failed(text):
                placeholder {
                    message(
                        icon: "exclamationmark.triangle",
                        title: "Could not load profiles",
                        body: text,
                        action: "Try again",
                        perform: { Task { await model.load() } }
                    )
                }

            case .loaded:
                if profiles.isEmpty {
                    placeholder {
                        message(
                            icon: "person.2",
                            title: "No profiles yet",
                            body: "Create your first profile to get a reading.",
                            action: "Create profile",
                            perform: { showsWeb = true }
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
        .onChange(of: model.profiles) { _, _ in syncSelection() }
        // A sheet, not a cover: with the toolbar down to one Settings
        // button, a swipe down is how the list is left.
        .sheet(isPresented: $showsList) { listScreen }
        .sheet(isPresented: $showsSearch) { searchScreen }
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
        // Permission is asked here, next to the location prompt and for the
        // same reason: this is the screen the alerts are about, and it is the
        // first one a signed-in account sees. Asked once, and only while the
        // answer is still open.
        await CategoryAlerts.shared.requestAuthorizationIfNeeded()
        let primary = profiles.first { $0.profileId == model.primaryProfileId } ?? profiles.first
        await CategoryAlerts.shared.refresh(profile: primary)
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
