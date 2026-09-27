import Foundation
import UIKit
import UserNotifications

/// Pushes from the server: a like, or a new follower, on one of the reader's
/// charts, the moment it happens, and a message somebody wrote to them.
///
/// The weather alerts next door are local notifications the phone schedules
/// for itself, because a forecast is knowable a fortnight ahead. Nobody knows
/// ahead when someone will like a chart, so these come through APNs: the app
/// hands the server this install's device token, and the server sends the
/// banner, with the icon's badge set to the unread count.
///
/// The permission is the same one the weather alerts ask for. Whoever already
/// said yes to those is registered without a second question; whoever has
/// never been asked is asked once, on the Activity screen, where hearing about
/// likes and follows is the obvious thing to want.
@MainActor
final class PushNotifications: ObservableObject {

    static let shared = PushNotifications()

    /// Set by a tapped push about a like or a follow. The home screen opens
    /// Activity and clears it.
    @Published var opensActivity = false

    /// Set by a tapped push about a message: the chat it came from. The home
    /// screen opens that chat and clears it.
    @Published var opensChat: Int?

    private enum Key {
        static let token = "pushDeviceToken"
        static let asked = "pushPermissionAsked"
    }

    /// The token APNs last gave this install.
    private(set) var token: String? = UserDefaults.standard.string(forKey: Key.token)

    private let center = UNUserNotificationCenter.current()

    /// What the server was last told this session: token, language and
    /// account. A return to the app with none of them changed sends nothing.
    private var uploaded: String?

    /// The APNs host this build's tokens belong to. A debug build is signed
    /// for the sandbox; TestFlight and the App Store for production.
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    /// The pushes a tap can open Activity for.
    nonisolated static func isSocial(kind: String?) -> Bool {
        kind == "like" || kind == "follow"
    }

    /// A push about a message, which a tap opens the chat of.
    nonisolated static func isMessage(kind: String?) -> Bool {
        kind == "message"
    }

    // MARK: - Registration

    /// Asks iOS for this install's token when notifications are allowed. On
    /// every launch and every return to the app: the phone can hand out a
    /// new token, and registering again tells the server the app's current
    /// language, which is the one the push is written in.
    func refresh() async {
        #if DEBUG
        if WeatherPreviewHarness.isEnabled { return }
        #endif
        guard AuthStore.shared.isSignedIn else { return }
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        case .denied, .notDetermined:
            break
        @unknown default:
            break
        }
    }

    /// Asks for permission the first time Activity opens, if nobody has asked
    /// yet — the weather alerts' card asks the same question and usually gets
    /// there first. Once only: after an answer, Settings is where it changes.
    func offerOnce() async {
        #if DEBUG
        if WeatherPreviewHarness.isEnabled { return }
        #endif
        guard AuthStore.shared.isSignedIn else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Key.asked),
              await center.notificationSettings().authorizationStatus == .notDetermined
        else {
            await refresh()
            return
        }
        await ask()
    }

    /// Puts the question when the phone has never answered it, whether or
    /// not Activity already asked: for a switch in Settings just turned on.
    func askIfUndetermined() async {
        guard await center.notificationSettings().authorizationStatus == .notDetermined else {
            await refresh()
            return
        }
        await ask()
    }

    private func ask() async {
        UserDefaults.standard.set(true, forKey: Key.asked)
        do {
            if try await center.requestAuthorization(options: [.alert, .sound, .badge]) {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            NSLog("[Push] authorisation request failed: \(error.localizedDescription)")
        }
        // The weather settings read the same permission.
        await CategoryAlerts.shared.syncAuthorization()
    }

    /// The token arrived from APNs, by way of the app delegate.
    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = hex
        UserDefaults.standard.set(hex, forKey: Key.token)
        Task { await upload(hex) }
    }

    func didFailToRegister(_ message: String) {
        NSLog("[Push] APNs registration failed: \(message)")
    }

    private func upload(_ hex: String) async {
        guard AuthStore.shared.isSignedIn else { return }
        let lang = LanguageStore.code
        let stamp = "\(hex)|\(lang)|\(AuthStore.shared.email ?? "")"
        guard stamp != uploaded else { return }
        do {
            try await APIClient.shared.registerDevice(token: hex, environment: Self.environment, lang: lang)
            uploaded = stamp
        } catch {
            if !error.isCancellation {
                NSLog("[Push] registering the device failed: \(error.localizedDescription)")
            }
        }
    }

    /// Called before signing out, while the access token still works: the
    /// phone stops hearing about the account it is leaving.
    func unregister() async {
        opensActivity = false
        opensChat = nil
        uploaded = nil
        await setBadge(0)
        guard let token else { return }
        do {
            try await APIClient.shared.unregisterDevice(token: token)
        } catch {
            if !error.isCancellation {
                NSLog("[Push] unregistering the device failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Arriving

    /// A push was tapped. One about a like or a follow opens Activity; one
    /// about a message opens its chat.
    func handleTap(kind: String?, chatId: Int? = nil) {
        guard AuthStore.shared.isSignedIn else { return }
        if Self.isSocial(kind: kind) {
            opensActivity = true
        } else if Self.isMessage(kind: kind), let chatId {
            opensChat = chatId
        }
    }

    /// Sets the icon to everything unread: Activity and messages together,
    /// what the bell and the chats button say added up.
    func syncBadge() async {
        await setBadge(SocialStore.shared.unreadActivity + ChatStore.shared.unreadCount)
    }

    /// The number on the app icon: unread Activity and messages, the bell
    /// and the chats button together (`syncBadge`). The server sets it with
    /// each push; the app keeps it true after that.
    func setBadge(_ count: Int) async {
        #if DEBUG
        if WeatherPreviewHarness.isEnabled { return }
        #endif
        // Without the badge permission the call fails every time; nothing to
        // show, and nothing to log about.
        guard await center.notificationSettings().badgeSetting == .enabled else { return }
        do {
            try await center.setBadgeCount(count)
        } catch {
            NSLog("[Push] setting the badge failed: \(error.localizedDescription)")
        }
    }
}
