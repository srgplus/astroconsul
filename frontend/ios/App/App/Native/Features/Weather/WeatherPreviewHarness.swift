import SwiftUI

#if DEBUG

/// Debug-only shortcut into the weather screens with sample data.
///
/// Launch with `-uiPreviewWeather` (`xcrun simctl launch <device> me.big3.app
/// -uiPreviewWeather`) to check layout on a real device without signing in.
struct WeatherPreviewHarness: View {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiPreviewWeather")
    }

    @State private var openProfile: ProfileSummary?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(WeatherPreviewData.profiles) { profile in
                        Button { openProfile = profile } label: {
                            ProfileWeatherCard(
                                profile: profile,
                                isPrimary: profile.profileId == WeatherPreviewData.profile.profileId
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                } header: {
                    Text("MINE")
                        .font(.system(size: 12, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textDim)
                        .tracking(0.6)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Profiles")
            .navigationDestination(item: $openProfile) { profile in
                CosmicWeatherView(
                    profile: profile,
                    model: CosmicWeatherViewModel(previewDays: WeatherPreviewData.days)
                )
            }
        }
    }
}

#Preview("Cosmic weather") {
    NavigationStack {
        CosmicWeatherView(
            profile: WeatherPreviewData.profile,
            model: CosmicWeatherViewModel(previewDays: WeatherPreviewData.days)
        )
    }
}

#Preview("Profile cards") {
    WeatherPreviewHarness()
}

#endif
