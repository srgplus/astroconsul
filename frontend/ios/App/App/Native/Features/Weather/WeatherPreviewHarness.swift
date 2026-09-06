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

    @StateObject private var listModel: ProfileListViewModel
    @State private var selection = WeatherPreviewData.profile.profileId
    @State private var showsList = false

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
                    model: CosmicWeatherViewModel(
                        previewDays: WeatherPreviewData.days(for: profile),
                        previewAspects: WeatherPreviewData.aspects,
                        previewRetrograde: WeatherPreviewData.retrograde,
                        previewPositions: WeatherPreviewData.positions,
                        loadingFor: Self.previewDelay
                    )
                )
            }
        }
        .task { DeviceLocation.shared.start() }
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
            previewRetrograde: WeatherPreviewData.retrograde,
            previewPositions: WeatherPreviewData.positions
        )
    )
}

#Preview("Home pager") {
    WeatherPreviewHarness()
}

#endif
