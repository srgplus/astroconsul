import SwiftUI

/// The big3.me wordmark, the same three-part lockup the web app draws in
/// `B3Logo.tsx`: light "big", bold "3", small muted ".me", set in Space
/// Grotesk and tracked tight.
struct B3Wordmark: View {

    var size: CGFloat = 22

    /// Bundled with the app so the mark matches the site rather than falling
    /// back to the system face. Google's subset names them oddly — the
    /// PostScript names are what `Font.custom` needs.
    private enum Face {
        static let light = "SpaceGroteskLight-Light"
        static let regular = "SpaceGroteskLight-Regular"
        static let bold = "SpaceGroteskLight-Bold"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("big")
                .font(.custom(Face.light, size: size))
                .foregroundStyle(Theme.text)

            Text("3")
                .font(.custom(Face.bold, size: size))
                .foregroundStyle(Theme.text)

            Text(".me")
                .font(.custom(Face.regular, size: size * 0.65))
                .foregroundStyle(Theme.textDim)
                .padding(.leading, 1)
        }
        .tracking(-0.8)
        .accessibilityElement()
        .accessibilityLabel("big3.me")
    }
}

#Preview {
    VStack(spacing: 20) {
        B3Wordmark()
        B3Wordmark(size: 30)
    }
    .padding()
}
