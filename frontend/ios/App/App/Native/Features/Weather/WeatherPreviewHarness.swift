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

    /// Add `-uiPreviewAlerts` to schedule the category-change notifications
    /// from the sample forecast: the permission sheet, the pending queue
    /// printed to the log, and one banner a few seconds later so the alert can
    /// be seen arriving without waiting for tomorrow.
    static var schedulesAlerts: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiPreviewAlerts")
    }

    @StateObject private var listModel: ProfileListViewModel
    @State private var selection = WeatherPreviewData.profile.profileId
    @State private var showsList = false
    @State private var editing: ProfileSummary?

    init() {
        _listModel = StateObject(
            wrappedValue: ProfileListViewModel(
                previewProfiles: WeatherPreviewData.profiles,
                primaryProfileId: WeatherPreviewData.profile.profileId
            )
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

            guard Self.schedulesAlerts else { return }
            await CategoryAlerts.shared.scheduleForPreview(days: WeatherPreviewData.days)
            await CategoryAlerts.shared.previewDelivery()
        }
        .sheet(item: $editing) { profile in
            ProfileEditSheet(
                skyZone: .active,
                model: ProfileEditViewModel(previewProfile: profile)
            )
        }
        .sheet(isPresented: $showsList) {
            ProfileListScreen(
                model: listModel,
                onSelect: { profile in
                    selection = profile.profileId
                    showsList = false
                },
                skyZone: TiiZone(tii: WeatherPreviewData.profile.latestTransit?.tii ?? 0),
                onOpenWeb: { showsList = false }
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

#endif
