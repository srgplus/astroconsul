import SwiftUI

/// Ink for the transit views. The same rows are drawn twice in two very
/// different places: on the card they float over a saturated sky and have to
/// be white in both light and dark mode, and in the detail sheet they sit on a
/// plain surface that follows the system theme. One value carried through the
/// environment keeps the pieces from each having to be told which.
struct TransitPalette {

    var primary: Color
    var secondary: Color
    var tertiary: Color
    /// The unfilled part of a progress bar.
    var track: Color

    /// Over the weather sky: white, because the sky is dark blue or deep
    /// orange under both appearances.
    static let onSky = TransitPalette(
        primary: .white,
        secondary: .white.opacity(0.7),
        tertiary: .white.opacity(0.55),
        track: .white.opacity(0.22)
    )

    /// On a plain surface, where the ink has to flip with the appearance.
    static let onSurface = TransitPalette(
        primary: Theme.text,
        secondary: Theme.textStrong,
        tertiary: Theme.textDim,
        track: Theme.lineStrong
    )
}

private struct TransitPaletteKey: EnvironmentKey {
    static let defaultValue = TransitPalette.onSky
}

extension EnvironmentValues {
    var transitPalette: TransitPalette {
        get { self[TransitPaletteKey.self] }
        set { self[TransitPaletteKey.self] = newValue }
    }
}
