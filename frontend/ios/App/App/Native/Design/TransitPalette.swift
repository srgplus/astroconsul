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
    /// A square or an opposition, marked apart from the two bodies its glyph
    /// sits between.
    var challenge: Color
    /// The four strength bands, read through `strength(_:)`.
    var exact: Color
    var strong: Color
    var moderate: Color
    var wide: Color

    /// The colour of one strength band. Anything the engine has not sent
    /// before reads as the widest, which is what an unknown band is worth.
    func strength(_ band: String) -> Color {
        switch band.lowercased() {
        case "exact": return exact
        case "strong": return strong
        case "moderate": return moderate
        default: return wide
        }
    }

    /// Over the weather sky: white, because the sky is dark blue or deep
    /// orange under both appearances. The accents are the web widget's own,
    /// which were picked for a dark page and hold over the card's glass —
    /// except the widest band, dim white here rather than the web's grey,
    /// which turns to mud against the sky.
    static let onSky = TransitPalette(
        primary: .white,
        secondary: .white.opacity(0.7),
        tertiary: .white.opacity(0.55),
        track: .white.opacity(0.22),
        challenge: Color(hex: 0xFF453A),
        exact: Color(hex: 0xFF2D55),
        strong: Color(hex: 0xFF9500),
        moderate: Color(hex: 0x5AC8FA),
        wide: .white.opacity(0.55)
    )

    /// On a plain surface, where the ink has to flip with the appearance.
    static let onSurface = TransitPalette(
        primary: Theme.text,
        secondary: Theme.textStrong,
        tertiary: Theme.textDim,
        track: Theme.lineStrong,
        challenge: Theme.challenge,
        exact: Theme.strengthExact,
        strong: Theme.strengthStrong,
        moderate: Theme.strengthModerate,
        wide: Theme.textDim
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
