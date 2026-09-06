import SwiftUI

/// Native shell of the app.
///
/// There is no tab bar: the home screen is the cosmic weather pager, and the
/// screens that are still web (birth chart, transits, compatibility, account)
/// open from the bottom bar as a full-screen cover.
struct RootView: View {

    @ObservedObject private var auth = AuthStore.shared
    @AppStorage("nativeAppearance") private var appearance = SettingsView.Appearance.system.rawValue

    var body: some View {
        Group {
            #if DEBUG
            if WeatherPreviewHarness.isEnabled {
                WeatherPreviewHarness()
            } else {
                signedInOrOut
            }
            #else
            signedInOrOut
            #endif
        }
        .animation(.easeInOut(duration: 0.25), value: auth.isSignedIn)
        .preferredColorScheme(SettingsView.Appearance(rawValue: appearance)?.colorScheme)
    }

    @ViewBuilder
    private var signedInOrOut: some View {
        if auth.isSignedIn {
            WeatherHomeView()
        } else {
            SignInView()
                .transition(.opacity)
        }
    }
}
