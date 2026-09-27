import SwiftUI

#if DEBUG

/// Debug-only shortcut into the weather screens with sample data.
///
/// Launch with `-uiPreviewWeather` (`xcrun simctl launch <device> me.big3.app
/// -uiPreviewWeather`) to check layout on a simulator without signing in.
struct WeatherPreviewHarness: View {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiPreviewWeather")
    }

    /// Add `-uiPreviewLoading` to watch the screens fill in the way they do on
    /// an account, spinners and all, instead of arriving already loaded.
    static var simulatesLoading: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiPreviewLoading")
    }

    private static var previewDelay: Duration? {
        simulatesLoading ? .seconds(3) : nil
    }

    /// Add `-uiPreviewAlerts` to schedule the daily weather notifications
    /// from the sample forecast: the permission sheet, the pending queue
    /// printed to the log, and one banner a few seconds later so the alert can
    /// be seen arriving without waiting for tomorrow.
    static var schedulesAlerts: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiPreviewAlerts")
    }

    /// Add `-uiPreviewAlertsOffer` to raise the first-run notification card.
    /// On an account it shows once and never again; here it shows every launch,
    /// which is the only way to look at it twice.
    static var offersAlerts: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiPreviewAlertsOffer")
    }

    /// Add `-uiPreviewPrimaryPrompt` to raise "Which chart is yours?" over the
    /// sample account, with its first two charts; `-uiPreviewPrimaryPrompt 1`
    /// shows the one-chart form, already selected, and any other number that
    /// many charts. On an account it shows once a day at most.
    static var primaryPromptCharts: Int? {
        guard ProcessInfo.processInfo.arguments.contains("-uiPreviewPrimaryPrompt") else { return nil }
        let asked = UserDefaults.standard.integer(forKey: "uiPreviewPrimaryPrompt")
        return asked > 0 ? asked : 2
    }

    @StateObject private var listModel: ProfileListViewModel
    @State private var selection = WeatherPreviewData.profile.profileId
    @State private var showsList = false
    @State private var editing: ProfileSummary?
    @State private var showsSearch = false
    @State private var showsAlertsOffer = false
    @State private var showsPrimaryPrompt = false
    @State private var showsActivity = false
    @State private var showsChats = false
    @State private var peopleTarget: PeopleSheet.Target?

    /// Add `-uiPreviewActivity` to open straight onto the Activity screen,
    /// the way App Store screenshots of it are taken.
    static var opensActivity: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiPreviewActivity")
    }

    /// Add `-uiPreviewChats` to open straight onto the chats, with sample
    /// conversations; what is sent stays on the screen, nothing leaves.
    static var opensChats: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiPreviewChats")
    }

    init() {
        _listModel = StateObject(
            wrappedValue: ProfileListViewModel(
                previewProfiles: WeatherPreviewData.profiles,
                primaryProfileId: WeatherPreviewData.profile.profileId
            )
        )
    }

    private var previewState: SkyState {
        SkyState(
            label: WeatherPreviewData.profile.latestTransit?.feelsLike,
            zone: TiiZone(tii: WeatherPreviewData.profile.latestTransit?.tii ?? 0)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top

            WeatherPager(
                profiles: WeatherPreviewData.profiles,
                selection: $selection,
                primaryProfileId: WeatherPreviewData.profile.profileId,
                bottomInset: geometry.safeAreaInsets.bottom,
                onOpenSearch: { showsSearch = true },
                onOpenList: { showsList = true }
            ) { profile in
                CosmicWeatherView(
                    profile: profile,
                    topInset: topInset,
                    bottomInset: geometry.safeAreaInsets.bottom,
                    isPrimary: profile.profileId == WeatherPreviewData.profile.profileId,
                    // The sample account owns every page, so the ••• offers
                    // Edit throughout, over a seeded sheet — there is no
                    // session here to load a real profile with.
                    onEdit: { editing = $0 },
                    partners: WeatherPreviewData.profiles.filter {
                        $0.profileId != profile.profileId
                    },
                    onFindPeople: { showsSearch = true },
                    onOpenPeople: { profile, tab in peopleTarget = PeopleSheet.Target(profile: profile, tab: tab) },
                    onOpenActivity: { showsActivity = true },
                    onOpenChats: { showsChats = true },
                    model: CosmicWeatherViewModel(
                        previewDays: WeatherPreviewData.days(for: profile),
                        previewAspects: WeatherPreviewData.aspects,
                        previewClimate: WeatherPreviewData.climate,
                        previewRetrograde: WeatherPreviewData.retrograde,
                        previewPositions: WeatherPreviewData.positions,
                        loadingFor: Self.previewDelay
                    )
                )
            }
        }
        .task {
            DeviceLocation.shared.start()
            showsAlertsOffer = Self.offersAlerts
            showsPrimaryPrompt = Self.primaryPromptCharts != nil
            await SocialStore.shared.refreshUnread()
            await ChatStore.shared.refreshUnread()
            showsActivity = Self.opensActivity
            showsChats = Self.opensChats && !Self.opensActivity

            guard Self.schedulesAlerts else { return }
            await CategoryAlerts.shared.scheduleForPreview(days: WeatherPreviewData.days)
            await CategoryAlerts.shared.previewDelivery()
        }
        .sheet(item: $editing) { profile in
            ProfileEditSheet(
                skyState: .flowing,
                model: ProfileEditViewModel(previewProfile: profile)
            )
        }
        .sheet(isPresented: $showsAlertsOffer) {
            CategoryAlertsOffer(
                profile: WeatherPreviewData.profile,
                onFinish: { showsAlertsOffer = false }
            )
        }
        .sheet(isPresented: $showsPrimaryPrompt) {
            PrimaryProfilePrompt(
                profiles: Array(WeatherPreviewData.profiles.prefix(Self.primaryPromptCharts ?? 2)),
                // No account to save to: a moment's spinner, then done.
                onChoose: { _ in
                    try? await Task.sleep(for: .milliseconds(600))
                    return nil
                },
                onAddOwn: { showsPrimaryPrompt = false },
                onFinish: { showsPrimaryPrompt = false }
            )
        }
        .sheet(isPresented: $showsList) {
            ProfileListScreen(
                model: listModel,
                onSelect: { profile in
                    selection = profile.profileId
                    showsList = false
                },
                skyState: previewState
            )
        }
        .sheet(isPresented: $showsActivity) {
            ActivityScreen(list: listModel, skyState: previewState, onFindPeople: { showsSearch = true })
        }
        .sheet(isPresented: $showsChats) {
            ChatsScreen(list: listModel)
        }
        .sheet(item: $peopleTarget) { target in
            PeopleSheet(target: target, list: listModel, skyState: previewState)
        }
        .sheet(isPresented: $showsSearch) {
            ProfileSearchScreen(
                list: listModel,
                onSelect: { profile in
                    selection = profile.profileId
                    showsSearch = false
                },
                skyState: previewState,
                // Seeded, because the harness runs without an account to
                // search with: the "new profiles" group would otherwise be
                // empty on every query.
                model: ProfileSearchViewModel(previewDiscoveries: WeatherPreviewData.discoveries)
            )
        }
    }
}

#Preview("Cosmic weather") {
    CosmicWeatherView(
        profile: WeatherPreviewData.profile,
        model: CosmicWeatherViewModel(
            previewDays: WeatherPreviewData.days,
            previewAspects: WeatherPreviewData.aspects,
            previewClimate: WeatherPreviewData.climate,
            previewRetrograde: WeatherPreviewData.retrograde,
            previewPositions: WeatherPreviewData.positions
        )
    )
}

#Preview("Home pager") {
    WeatherPreviewHarness()
}

#Preview("Profile preview") {
    ProfilePreviewSheet(profile: WeatherPreviewData.discoveries[2], onSubscribe: {})
}

#endif
