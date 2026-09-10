import SwiftUI
import UIKit

/// Design tokens ported from frontend/src/styles.css so native screens and
/// the WebView render the same palette. Every token resolves per trait
/// collection, so light and dark come from one definition.
enum Theme {

    // MARK: Surfaces

    static let bg = dynamic(dark: 0x1C1C1E, light: 0xF7F7F5)
    static let bgDeep = dynamic(dark: 0x131314, light: 0xEDEDEB)
    static let surface = dynamic(dark: 0x242426, light: 0xFFFFFF)
    static let surfaceSoft = dynamicAlpha(dark: (0xFFFFFF, 0.04), light: (0x000000, 0.03))

    // MARK: Sheets

    /// A sheet is the one place the app is not painted over the sky, so it uses
    /// the system's own grouped pair rather than the brand surfaces: black
    /// under raised charcoal in the dark, grey under white in the light. It is
    /// the ground every Apple sheet stands on, and the reason the panels inside
    /// need no border to separate them from it.
    static let sheetBg = Color(UIColor.systemGroupedBackground)
    static let sheetCard = Color(UIColor.secondarySystemGroupedBackground)

    // MARK: Lines

    static let line = dynamicAlpha(dark: (0xFFFFFF, 0.10), light: (0x000000, 0.10))
    static let lineStrong = dynamicAlpha(dark: (0xFFFFFF, 0.18), light: (0x000000, 0.18))

    // MARK: Text

    static let text = dynamic(dark: 0xF5F5F7, light: 0x1A1A1A)
    static let textDim = dynamic(dark: 0x98989D, light: 0x6B7280)
    static let textStrong = dynamic(dark: 0xC7C7CC, light: 0x374151)

    // MARK: Status

    static let ok = dynamic(dark: 0x30D158, light: 0x30D158)
    static let error = dynamic(dark: 0xFF453A, light: 0xFF453A)
    /// Grey, never purple: the project's spinner colour.
    static let spinner = Color(hex: 0x8E8E93)

    // MARK: Aspects

    /// A square or an opposition. Apple's systemRed, which is two values: the
    /// bright one over dark, a deeper one so it still reads on white.
    static let challenge = dynamic(dark: 0xFF453A, light: 0xD70015)

    /// EXACT / STRONG / MODERATE, in the ramp the web widget uses. The web
    /// paints them on a dark page only; the light values here are pulled down
    /// far enough that an 11pt label holds against a white sheet.
    static let strengthExact = dynamic(dark: 0xFF2D55, light: 0xD00030)
    static let strengthStrong = dynamic(dark: 0xFF9500, light: 0xB25E00)
    static let strengthModerate = dynamic(dark: 0x5AC8FA, light: 0x0A7AA8)

    // MARK: Compatibility

    /// The two people in a compatibility report, in the web widget's own pair:
    /// indigo for the profile whose page it is, pink for the partner. Every
    /// avatar, glyph and position line takes its colour from these, so a mark
    /// always says whose side it is on.
    ///
    /// The web values are picked for a dark page and go pale against a white
    /// sheet, so the light variants are the same hues pulled down to where an
    /// 11pt label still holds.
    static let personA = dynamic(dark: 0xA5B4FC, light: 0x4338CA)
    static let personB = dynamic(dark: 0xF9A8D4, light: 0xBE185D)

    /// The two ends of the score gauge's sweep — purple into pink, the
    /// gradient the web draws it with. One pair for both appearances: it is a
    /// saturated arc on glass or on a card, never text.
    static let scoreArcStart = Color(hex: 0xA855F7)
    static let scoreArcEnd = Color(hex: 0xEC4899)

    /// A category bar's ink, by the key the scores are read under. The four
    /// love categories and the four business ones, in the web report's own
    /// colours.
    static func categoryColor(_ key: String) -> Color {
        switch key {
        case "emotional": return dynamic(dark: 0xEC4899, light: 0xBE185D)
        case "mental", "communication": return dynamic(dark: 0x6366F1, light: 0x4338CA)
        case "physical", "drive": return dynamic(dark: 0xF59E0B, light: 0xB45309)
        case "karmic", "vision": return dynamic(dark: 0x8B5CF6, light: 0x6D28D9)
        case "trust": return dynamic(dark: 0x10B981, light: 0x047857)
        default: return textDim
        }
    }

    /// A keyword tag's fill and ink. The web cycles seven of these by position
    /// in the row (`.cw-transit-keyword-tag:nth-child(7n+1)` and its
    /// siblings), which is what keeps a row of five tags from reading as one
    /// long stripe; the cycle is the same here.
    static func keywordTint(_ index: Int) -> (fill: Color, ink: Color) {
        let hues: [(dark: UInt32, light: UInt32)] = [
            (0x6EE7A8, 0x047857),
            (0x7DD3E8, 0x0E7490),
            (0xC4A0F5, 0x6D28D9),
            (0xF0D060, 0x92400E),
            (0xF09070, 0xB91C1C),
            (0x7DB8F8, 0x1D4ED8),
            (0xF8A850, 0xB45309),
        ]
        let hue = hues[((index % hues.count) + hues.count) % hues.count]
        return (
            fill: dynamicAlpha(dark: (hue.dark, 0.18), light: (hue.light, 0.12)),
            ink: dynamic(dark: hue.dark, light: hue.light)
        )
    }

    // MARK: TII zones

    static func zoneColor(_ zone: TiiZone) -> Color {
        switch zone {
        case .quiet: return Color(hex: 0x4A90D9)
        case .active: return Color(hex: 0x5DCAA5)
        case .hot: return Color(hex: 0xE8651A)
        case .extreme: return Color(hex: 0xE24B4A)
        }
    }

    static func zoneColor(tii: Double) -> Color {
        zoneColor(TiiZone(tii: tii))
    }

    // MARK: Metrics

    enum Radius {
        static let card: CGFloat = 16
        static let pill: CGFloat = 999
    }

    enum Spacing {
        static let tight: CGFloat = 8
        static let base: CGFloat = 12
        static let loose: CGFloat = 16
        static let section: CGFloat = 24
    }

    // MARK: Builders

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light, alpha: 1)
        })
    }

    private static func dynamicAlpha(
        dark: (rgb: UInt32, alpha: CGFloat),
        light: (rgb: UInt32, alpha: CGFloat)
    ) -> Color {
        Color(UIColor { traits in
            let token = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(rgb: token.rgb, alpha: token.alpha)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(UIColor(rgb: hex, alpha: 1))
    }
}

private extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}
