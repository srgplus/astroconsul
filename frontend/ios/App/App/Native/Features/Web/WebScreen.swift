import SwiftUI

/// Full-screen wrapper around the Capacitor WebView.
///
/// The web app still owns everything that is not native yet — the birth chart,
/// transits, compatibility, profile editing and account management — so it is
/// reachable from the bottom bar and from Settings rather than living in a tab.
struct WebScreen: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Done") { dismiss() }
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.text)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.bg)

            Divider().overlay(Theme.line)

            WebContainerView()
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Theme.bg)
    }
}
