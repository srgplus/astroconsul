import SwiftUI
import UIKit

/// Holds the single Capacitor view controller for the app's lifetime.
///
/// The WebView must not be recreated when the user switches tabs: rebuilding
/// it would reload big3.me and throw away scroll position and in-page state.
///
/// Creation is lazy and only happens when the Chart tab is first shown. Code
/// that wants to talk to an existing WebView uses `current`, which never
/// forces one into existence outside the view hierarchy.
@MainActor
final class WebControllerHolder {

    static let shared = WebControllerHolder()

    private var controllerIfCreated: CustomViewController?

    private init() {}

    /// Creates the controller on first use. Only the Chart tab calls this.
    func makeOrReuseController() -> CustomViewController {
        if let existing = controllerIfCreated { return existing }
        let created = CustomViewController()
        controllerIfCreated = created
        return created
    }

    /// The live controller, or nil if the Chart tab has never been opened.
    var current: CustomViewController? { controllerIfCreated }

    /// Hands the WebView the language the native side is set to. A no-op when
    /// the web half has never been opened: it reads the setting out of
    /// localStorage on its next boot, and that store is shared.
    func syncLanguage() {
        controllerIfCreated?.syncLanguage()
    }
}

/// Bridges the Capacitor WebView into SwiftUI as one tab.
struct WebContainerView: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> CustomViewController {
        WebControllerHolder.shared.makeOrReuseController()
    }

    func updateUIViewController(_ controller: CustomViewController, context: Context) {
        // Nothing to push: the WebView owns its own state.
    }
}
