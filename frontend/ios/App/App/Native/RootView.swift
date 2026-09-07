import SwiftUI

/// Native shell of the app.
///
/// There is no tab bar: the home screen is the cosmic weather pager, and the
/// screens that are still web (birth chart, transits, compatibility, account)
/// open from the bottom bar as a full-screen cover.
struct RootView: View {

    @ObservedObject private var auth = AuthStore.shared
    @ObservedObject private var strings = L10n.shared
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
        // The app's own language, not the device's, so the system controls
        // under it — the date and time pickers, the pull-to-refresh label,
        // the swipe actions' own words — are set in the language the labels
        // beside them are.
        .environment(\.locale, LanguageStore.locale)
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
