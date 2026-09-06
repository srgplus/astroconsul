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
                onOpenChart: {},
                onOpenList: { showsList = true }
            ) { profile in
                CosmicWeatherView(
                    profile: profile,
                    topInset: topInset,
                    model: CosmicWeatherViewModel(previewDays: WeatherPreviewData.days(for: profile))
                )
            }
        }
        .fullScreenCover(isPresented: $showsList) {
            ProfileListScreen(
                model: listModel,
                onSelect: { profile in
                    selection = profile.profileId
                    showsList = false
                },
                onOpenSettings: { showsList = false },
                onOpenWeb: { showsList = false }
            )
        }
    }
}

#Preview("Cosmic weather") {
    CosmicWeatherView(
        profile: WeatherPreviewData.profile,
        model: CosmicWeatherViewModel(previewDays: WeatherPreviewData.days)
    )
}

#Preview("Home pager") {
    WeatherPreviewHarness()
}

#endif
