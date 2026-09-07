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

                // The page draws footage over its gradient, so frosting the
                // gradient alone leaves the glass a shade the sky no longer
                // is. The material blurs this to a wash either way, but it is
                // the sky's own wash.
                //
                // The card crop rather than the full-screen clip: what comes
                // out the other side of the material is a blur, and decoding
                // eight times the pixels for it costs the list scrolling on
                // top of it.
                SkyVideo(zone: zone, variant: .card)
            }
            // Frosted dark whatever the device is set to: the thing being
            // frosted is a night sky, and a light material over it turns the
            // backdrop into milk that neither the sky nor the screen's own
            // white text survives.
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .ignoresSafeArea()
    }
}

extension View {

    /// Drops the navigation bar's own background so a screen can draw its
    /// own. The modifier was renamed in iOS 18 and the old one is a no-op on
    /// the new bars, so both are here.
    @ViewBuilder
    func hidingBarBackground() -> some View {
        if #available(iOS 18.0, *) {
            toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        } else {
            toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
