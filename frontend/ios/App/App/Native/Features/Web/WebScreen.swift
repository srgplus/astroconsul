import SwiftUI

/// One of the web app's screens, named rather than assumed.
///
/// The WebView is created once and kept for the app's lifetime, so it stays
/// wherever it was last left. Every entry point says where it means to go
/// instead of trusting that.
enum WebDestination: String, Identifiable {

    /// The web app's own home screen.
    case home = "/"

    /// Account settings: email, subscription and account deletion. Settings →
    /// "Manage account" opens this rather than the home screen — deletion is
    /// what Apple reviews under 5.1.1(v), and it should be one tap away.
    case account = "/account"

    var id: String { rawValue }

    /// Absolute URL on the backend origin.
    var url: URL? { URL(string: rawValue, relativeTo: AppConfig.apiBaseURL) }
}

/// Full-screen wrapper around the Capacitor WebView.
///
/// The web app still owns everything that is not native yet — the birth chart,
/// transits, compatibility, profile editing and account management — so it is
/// reachable from the bottom bar and from Settings rather than living in a tab.
struct WebScreen: View {

    /// Which web screen to open.
    var destination: WebDestination = .home

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(L("common.done")) { dismiss() }
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.text)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.bg)

            Divider().overlay(Theme.line)

            WebContainerView(destination: destination)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Theme.bg)
    }
}
