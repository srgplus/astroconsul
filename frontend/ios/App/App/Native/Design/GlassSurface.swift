import SwiftUI

extension View {

    /// Liquid Glass where the OS has it, a dark blurred material where it
    /// does not. The deployment target is still iOS 17, so every glass
    /// surface in the app goes through here rather than calling
    /// `glassEffect` at the use site.
    /// Tinted a little dark on purpose: over a bright sky, plain glass turns
    /// milky and the white dots and glyphs on it stop reading.
    @ViewBuilder
    func weatherGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let glass = Glass.regular.tint(Color.black.opacity(0.16))
            glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            background {
                shape
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(shape.stroke(Color.white.opacity(0.24), lineWidth: 1))
            }
            .clipShape(shape)
        }
    }
}

/// Groups neighbouring glass surfaces so they blend instead of each blurring
/// the sky on its own. A plain passthrough before iOS 26.
struct WeatherGlassGroup<Content: View>: View {

    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
