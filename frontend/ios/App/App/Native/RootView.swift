import SwiftUI

/// Native shell of the app.
///
/// There is no tab bar: the home screen is the cosmic weather pager, and the
/// screens that are still web (birth chart, transits, compatibility, account)
/// open from the bottom bar as a full-screen cover.
struct RootView: View {

    /// The splash is held at least this long, so a fast launch reads as a
    /// deliberate opening rather than a flicker of the mark.
    private static let minimumSplash: Duration = .milliseconds(450)

    /// And no longer than this past that floor: a stalled request should reach
    /// the home screen's own error state, not sit behind the logo.
    private static let patience: Duration = .seconds(2)

    @ObservedObject private var auth = AuthStore.shared
    @ObservedObject private var strings = L10n.shared
    @ObservedObject private var launch = AppLaunch.shared
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system.rawValue

    @State private var heldMinimum = false
    @State private var ranOutOfPatience = false

    private var showsSplash: Bool {
        !heldMinimum || !(launch.isContentReady || ranOutOfPatience)
    }

    var body: some View {
        ZStack {
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

            if showsSplash {
                SplashView().transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: showsSplash)
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
        .task {
            #if DEBUG
            // The harness is opened to look at one card, not at the mark.
            if WeatherPreviewHarness.isEnabled { launch.markContentReady() }
            #endif
            try? await Task.sleep(for: Self.minimumSplash)
            heldMinimum = true
            try? await Task.sleep(for: Self.patience)
            ranOutOfPatience = true
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
