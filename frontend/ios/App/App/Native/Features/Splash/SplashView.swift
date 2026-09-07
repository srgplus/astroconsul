import SwiftUI

/// What the app shows while its first screen is still empty.
///
/// Not a screen of its own so much as a continuation of
/// `LaunchScreen.storyboard`: same mark, same width, same ground, centred on
/// the same point, so the handover out of the storyboard and into SwiftUI has
/// nothing to see. It stays up until the home screen has something to draw —
/// and the home screen's own loading state draws this same view, so a load
/// that outlasts `RootView`'s patience keeps the mark rather than uncovering
/// a spinner on an empty background.
struct SplashView: View {

    /// Kept in step with the imageView's width constraint in
    /// `LaunchScreen.storyboard`. Change one and the mark jumps at handover.
    static let markWidth: CGFloat = 180

    /// What VoiceOver reads. At launch the mark means the app is opening; on
    /// the home screen behind it, that the load is still running.
    var label = "big3.me"

    var body: some View {
        ZStack {
            Theme.bg
            Image("B3Logo")
                .resizable()
                .scaledToFit()
                .frame(width: Self.markWidth)
        }
        // The storyboard centres the mark in the whole screen, not in the safe
        // area, and the notch and the home indicator are not the same height.
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

/// When the screen behind the splash is worth looking at.
///
/// The home screen owns its own loading state, several layers below the shell
/// that draws the splash, so it reports up rather than being asked.
@MainActor
final class AppLaunch: ObservableObject {

    static let shared = AppLaunch()

    @Published private(set) var isContentReady = false

    private init() {}

    /// Called once the first screen has content, an error, or a sign-in form —
    /// anything other than a spinner.
    func markContentReady() {
        guard !isContentReady else { return }
        isContentReady = true
    }
}

#Preview {
    SplashView()
}
