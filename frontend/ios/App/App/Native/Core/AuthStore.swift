import Foundation

struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    /// Unix seconds. Supabase sends `expires_at`; older payloads only carry
    /// `expires_in`, which the decoder below converts.
    var expiresAt: Double
    var email: String?

    var isExpired: Bool { Date().timeIntervalSince1970 >= expiresAt }

    /// Refresh slightly early so a request never leaves with a token that
    /// expires mid-flight.
    var needsRefresh: Bool { Date().timeIntervalSince1970 >= expiresAt - 60 }
}

/// Owns the Supabase session for the whole app.
///
/// Sign-in is native (email code, Apple, Google, password) and the Keychain is
/// the source of truth. The WebView is kept in step in both directions:
/// `adopt(fromWebSession:)` picks up a session created there before this
/// screen existed, and `adoptFromNativeSignIn` pushes new sessions into it.
@MainActor
final class AuthStore: ObservableObject {

    static let shared = AuthStore()

    @Published private(set) var session: AuthSession?

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.email }

    private static let keychainKey = "session"
    private static let signedOutFlag = "nativeUserSignedOut"
    private var refreshTask: Task<String?, Never>?

    /// Set when the user signs out on purpose.
    ///
    /// The WebView keeps its own session in localStorage, which survives app
    /// restarts. Without this flag, signing out while the Chart tab has never
    /// been opened would leave that copy untouched, and the import bridge
    /// would sign the user back in the next time the tab loads.
    private var didSignOutExplicitly: Bool {
        get { UserDefaults.standard.bool(forKey: Self.signedOutFlag) }
        set { UserDefaults.standard.set(newValue, forKey: Self.signedOutFlag) }
    }

    private init() {
        if let data = KeychainStore.read(key: Self.keychainKey),
           let stored = try? JSONDecoder().decode(AuthSession.self, from: data) {
            session = stored
        }
    }

    // MARK: - Token access

    /// Returns a valid access token, refreshing first when the current one is
    /// about to expire. Concurrent callers share a single refresh.
    func validAccessToken() async -> String? {
        guard let current = session else { return nil }
        guard current.needsRefresh else { return current.accessToken }

        if let inFlight = refreshTask {
            return await inFlight.value
        }

        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            let refreshed = await self.performRefresh(refreshToken: current.refreshToken)
            self.refreshTask = nil
            return refreshed
        }
        refreshTask = task
        return await task.value
    }

    // MARK: - Session lifecycle

    func store(_ newSession: AuthSession) {
        session = newSession
        if let data = try? JSONEncoder().encode(newSession) {
            KeychainStore.save(data, key: Self.keychainKey)
        }
    }

    func signOut() {
        session = nil
        refreshTask?.cancel()
        refreshTask = nil
        KeychainStore.delete(key: Self.keychainKey)
        didSignOutExplicitly = true
        WebControllerHolder.shared.current?.clearWebSession()
    }

    // MARK: - Native sign-in

    func sendEmailCode(to email: String) async throws {
        try await SupabaseAuthAPI.sendEmailCode(email: email.trimmed)
    }

    func signIn(email: String, code: String) async throws {
        let session = try await SupabaseAuthAPI.verifyEmailCode(
            email: email.trimmed,
            code: code.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        adoptFromNativeSignIn(session)
    }

    func signIn(email: String, password: String) async throws {
        let session = try await SupabaseAuthAPI.signIn(email: email.trimmed, password: password)
        adoptFromNativeSignIn(session)
    }

    func signInWithApple() async throws {
        let session = try await AppleSignInController().signIn()
        adoptFromNativeSignIn(session)
    }

    func signInWithGoogle() async throws {
        let session = try await GoogleSignInController().signIn()
        adoptFromNativeSignIn(session)
    }

    /// Stores a session that native sign-in produced and hands it to the
    /// WebView, so the un-ported screens are signed in as the same account.
    ///
    /// If the Chart tab has never been opened there is no WebView yet; it
    /// picks the session up from the Keychain on its first load instead.
    private func adoptFromNativeSignIn(_ newSession: AuthSession) {
        didSignOutExplicitly = false
        store(newSession)
        WebControllerHolder.shared.current?.applyNativeSession(newSession)
    }

    /// Adopts a session read out of the WebView's localStorage.
    ///
    /// Skipped after an explicit sign-out, and skipped when the stored session
    /// is not newer, so a WebView reload cannot resurrect a signed-out user or
    /// downgrade a freshly refreshed native session.
    func adopt(fromWebSession incoming: AuthSession) {
        if didSignOutExplicitly {
            WebControllerHolder.shared.current?.clearWebSession()
            return
        }
        if let current = session, current.expiresAt >= incoming.expiresAt {
            return
        }
        store(incoming)
    }

    // MARK: - Refresh

    private func performRefresh(refreshToken: String) async -> String? {
        var request = URLRequest(
            url: AppConfig.supabaseURL.appendingPathComponent("auth/v1/token")
        )
        request.url = URL(string: request.url!.absoluteString + "?grant_type=refresh_token")
        request.httpMethod = "POST"
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["refresh_token": refreshToken]
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            guard (200..<300).contains(http.statusCode) else {
                NSLog("[Auth] refresh failed: HTTP \(http.statusCode)")
                // 400/401 means the refresh token is spent or revoked; the
                // user has to sign in again.
                if http.statusCode == 400 || http.statusCode == 401 {
                    signOut()
                }
                return nil
            }

            let refreshed = try SupabaseTokenResponse.decode(data)
            store(refreshed)
            return refreshed.accessToken
        } catch {
            NSLog("[Auth] refresh error: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Decodes the `/auth/v1/token` payload into an `AuthSession`.
enum SupabaseTokenResponse {

    private struct Payload: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Double?
        let expires_at: Double?
        let user: User?

        struct User: Decodable { let email: String? }
    }

    static func decode(_ data: Data) throws -> AuthSession {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let expiresAt = payload.expires_at
            ?? Date().timeIntervalSince1970 + (payload.expires_in ?? 3600)
        return AuthSession(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            expiresAt: expiresAt,
            email: payload.user?.email
        )
    }
}

extension String {
    /// Emails are trimmed and lowercased before hitting Supabase: it treats
    /// addresses case-insensitively, but a stray space fails the request.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
