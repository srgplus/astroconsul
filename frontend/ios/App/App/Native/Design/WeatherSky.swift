import SwiftUI
import UIKit

/// Sky palettes for the cosmic weather screens.
///
/// The metaphor is Apple Weather: the background *is* the reading. Each TII
/// zone gets its own sky, deeper in dark mode, and every stop is picked so
/// white text stays legible on top — which is why these screens use white
/// foregrounds instead of `Theme.text`.
enum WeatherSky {

    /// Full-bleed background behind a weather screen.
    static func gradient(for zone: TiiZone) -> LinearGradient {
        LinearGradient(
            colors: colors(for: zone),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Card fill for a profile row in the list, tilted diagonally so a stack
    /// of cards does not read as one flat block.
    static func cardGradient(for zone: TiiZone?) -> LinearGradient {
        LinearGradient(
            colors: zone.map(colors(for:)) ?? neutralColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Topmost stop, used to fade content sliding under the status bar.
    static func topColor(for zone: TiiZone) -> Color {
        colors(for: zone).first ?? .clear
    }

    /// Accent used for the forecast bars — the brightest stop of the sky.
    static func accent(for zone: TiiZone) -> Color {
        colors(for: zone).last ?? .white
    }

    private static func colors(for zone: TiiZone) -> [Color] {
        switch zone {
        case .quiet:
            return ramp(
                dark: [0x0C1D2E, 0x16354C, 0x2A5A79],
                light: [0x2C6BAC, 0x5896D2, 0x93C0E6]
            )
        case .active:
            return ramp(
                dark: [0x0A2823, 0x11463D, 0x1D6D5D],
                light: [0x1E7A6A, 0x35A78E, 0x84CFBB]
            )
        case .hot:
            return ramp(
                dark: [0x361707, 0x5B2A0D, 0x974717],
                light: [0xB05119, 0xDD7829, 0xEFAC68]
            )
        case .extreme:
            return ramp(
                dark: [0x2B0A0A, 0x501513, 0x882823],
                light: [0x8B2521, 0xC64233, 0xE27769]
            )
        }
    }

    /// A profile with no transit reading yet — grey sky, no false signal.
    private static var neutralColors: [Color] {
        ramp(
            dark: [0x1F1F22, 0x2C2C30, 0x3C3C42],
            light: [0x6E7079, 0x8A8C95, 0xA8AAB2]
        )
    }

    private static func ramp(dark: [UInt32], light: [UInt32]) -> [Color] {
        zip(dark, light).map { darkHex, lightHex in
            Color(UIColor { traits in
                UIColor(skyHex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
            })
        }
    }
}

/// The veil between the sky and everything drawn on it.
///
/// `WeatherSky`'s gradients are picked so white text sits on them. The footage
/// on top is not: a sunlit cloud drifting through the hero puts the hero's
/// ultraLight numbers on near-white, and the light appearance starts the whole
/// sky that bright. So the sky carries a scrim — lightest at the top where
/// there is only the place name, deeper through the hero, deepest under the
/// cards.
///
/// **It darkens in both appearances.** The text on these screens is white in
/// either one, so a pale veil under the light theme would push the contrast
/// the wrong way and swallow the numbers it is there to rescue. What the light
/// theme gets instead is more of the same veil, because it has more brightness
/// to hold down.
struct SkyScrim: View {

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(top), location: 0),
                .init(color: .black.opacity(hero), location: 0.34),
                .init(color: .black.opacity(bottom), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private var isLight: Bool { scheme == .light }

    /// Just enough to hold the status bar and the place name.
    private var top: Double { isLight ? 0.22 : 0.08 }
    /// Under the reading itself, which is the thinnest type on the screen.
    private var hero: Double { isLight ? 0.30 : 0.16 }
    /// Under the cards, where a lightning core or a lit cloud used to eat the
    /// forecast rows.
    private var bottom: Double { isLight ? 0.50 : 0.40 }
}

private extension UIColor {
    convenience init(skyHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The sky each weather page settled on, keyed by profile.
///
/// A page's zone comes from its own loaded forecast, which the pager above it
/// cannot see — it only holds the TII the profile list carried in, and the two
/// disagree often enough to put a green sheet over a blue sky. Pages report
/// upwards instead. Keyed rather than a single value because a paging TabView
/// keeps every page alive, so they all contribute.
struct SkyStateKey: PreferenceKey {
    static var defaultValue: [String: SkyState] = [:]

    static func reduce(value: inout [String: SkyState], nextValue: () -> [String: SkyState]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}
