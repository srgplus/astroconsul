import SwiftUI

extension View {

    /// Liquid Glass where the OS has it, a dark blurred material where it
    /// does not. The deployment target is still iOS 17, so every glass
    /// surface in the app goes through here rather than calling
    /// `glassEffect` at the use site.
    /// Tinted a little dark on purpose: over a bright sky, plain glass turns
    /// milky and the white dots and glyphs on it stop reading.
    ///
    /// `tint` is how much of that dark carries. Controls that hold a glyph or
    /// two get the light default; a panel of running text needs more, or the
    /// sky behind it reads through the words.
    @ViewBuilder
    func weatherGlass<S: Shape>(
        in shape: S,
        tint: Double = 0.16,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            let glass = Glass.regular.tint(Color.black.opacity(tint))
            glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            background {
                shape
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(shape.fill(Color.black.opacity(tint)))
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

/// The backdrop a presented screen sits on.
///
/// A sheet's presenting screen is not rendered behind it — a clear or material
/// background over it shows the window's own white, not the weather page — so
/// the page's sky is drawn here and frosted, which is what would show through
/// if the system kept it around.
struct WeatherGlassBackdrop: View {

    var zone: TiiZone?

    var body: some View {
        ZStack {
            if let zone {
                WeatherSky.gradient(for: zone)
            }
            Rectangle().fill(.ultraThinMaterial)
        }
        .ignoresSafeArea()
    }
}
