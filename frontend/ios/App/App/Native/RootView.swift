import SwiftUI

/// Native shell of the app.
///
/// There is no tab bar: the home screen is the cosmic weather pager, and the
/// screens that are still web (birth chart, transits, compatibility, account)
/// open from the bottom bar as a full-screen cover.
struct RootView: View {

    @ObservedObject private var auth = AuthStore.shared
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system.rawValue

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
        // Applied to the window rather than with `preferredColorScheme`: this
        // hierarchy has no SwiftUI presentation above it to read that
        // preference, so it went nowhere — see `Appearance`. `AppDelegate`
        // sets the launch value, and this carries every later change.
        .onChange(of: appearance) { _, choice in
            Appearance.apply(Appearance(rawValue: choice) ?? .system)
        }
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
