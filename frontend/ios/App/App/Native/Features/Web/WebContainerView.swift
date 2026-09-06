import SwiftUI
import UIKit

/// Holds the single Capacitor view controller for the app's lifetime.
///
/// The WebView must not be recreated when the user switches tabs: rebuilding
/// it would reload big3.me and throw away scroll position and in-page state.
@MainActor
final class WebControllerHolder {
    static let shared = WebControllerHolder()
    let controller = CustomViewController()
    private init() {}
}

/// Bridges the Capacitor WebView into SwiftUI as one tab.
struct WebContainerView: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> CustomViewController {
        WebControllerHolder.shared.controller
    }

    func updateUIViewController(_ controller: CustomViewController, context: Context) {
        // Nothing to push: the WebView owns its own state.
    }
}
