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
