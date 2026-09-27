import SwiftUI
import UIKit

/// The Appearance setting on the Settings screen: follow the device, or pin
/// light or dark.
///
/// The choice is applied to the window, not with SwiftUI's
/// `preferredColorScheme`. That modifier is a *preference*, read by the
/// enclosing SwiftUI presentation, and the root here is a
/// `UIHostingController` in a window built by hand in `AppDelegate` — there is
/// no `WindowGroup` above it to read the preference, so it was dropped without
/// a word and the app stayed on whatever the device was set to.
///
/// `overrideUserInterfaceStyle` is the one switch that moves everything the
/// choice has to move: SwiftUI's `colorScheme`, the trait-resolved colours in
/// `Theme`, the sheets, the keyboard, and the `prefers-color-scheme` the
/// still-web screens are styled with.
enum Appearance: String, CaseIterable, Identifiable {

    case system, light, dark

    /// The `@AppStorage` key, shared by the picker that writes it and the
    /// window that reads it.
    static let storageKey = "nativeAppearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L("settings.theme.system")
        case .light: return L("settings.theme.light")
        case .dark: return L("settings.theme.dark")
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The Home Screen icon that goes with the choice. `nil` is the primary
    /// icon, which carries a light and a dark variant and leaves the pick to
    /// iOS, as "System" leaves the screens to the device. A pinned choice pins
    /// the icon too, from the alternates the asset catalogue builds
    /// (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`).
    var iconName: String? {
        switch self {
        case .system: return nil
        case .light: return "AppIconLight"
        case .dark: return "AppIconDark"
        }
    }

    /// The stored choice, falling back to following the device — which is also
    /// where a value written by some other build lands.
    static var stored: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// Every window in the scene, not only the app's own: sign-in and the
    /// system's own presentations can each be handed one, and a window left on
    /// the device's style flips the app back mid-use.
    ///
    /// At launch there is no scene yet, so `AppDelegate` sets the style on the
    /// window it makes instead of calling this.
    @MainActor
    static func apply(_ appearance: Appearance = .stored) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        for window in windows {
            window.overrideUserInterfaceStyle = appearance.interfaceStyle
        }
    }

    /// Puts the icon that goes with the choice on the Home Screen. iOS
    /// announces every icon change in an alert of its own, and no public API
    /// skips it, so this runs only when the reader changes the setting, never
    /// at launch, where the alert would come out of nowhere.
    @MainActor
    static func applyIcon(_ appearance: Appearance) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != appearance.iconName else { return }
        app.setAlternateIconName(appearance.iconName) { error in
            if let error {
                NSLog("[Appearance] icon change failed: \(error.localizedDescription)")
            }
        }
    }
}
