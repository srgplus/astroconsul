import Combine
import UIKit

/// Whether the app is in front, as UIKit says it.
///
/// Not SwiftUI's `scenePhase`: the window here is made by hand in
/// `AppDelegate` around a `UIHostingController`, with no SwiftUI scene above
/// it, and a view hosted that way does not get a phase that follows the app.
/// The chat read it as its "on screen and in front" and so, on a phone,
/// never polled and never marked anything read. UIKit's own notices are
/// what this app can trust.
@MainActor
final class AppActivity: ObservableObject {

    static let shared = AppActivity()

    /// In front and taking touches: not in the background, not under Control
    /// Centre or a call.
    @Published private(set) var isActive: Bool

    private var observers: Set<AnyCancellable> = []

    private init() {
        isActive = UIApplication.shared.applicationState == .active
        let center = NotificationCenter.default
        center.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.set(true) }
            .store(in: &observers)
        center.publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.set(false) }
            .store(in: &observers)
    }

    private func set(_ active: Bool) {
        if isActive != active { isActive = active }
    }
}
