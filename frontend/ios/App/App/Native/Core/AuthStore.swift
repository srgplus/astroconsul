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

/// Owns the Supabase session for the native layer.
///
/// During the migration the WebView is still the place where the user signs
/// in, so `adopt(fromWebSession:)` imports the session that supabase-js keeps
/// in localStorage. Once sign-in itself is native this import goes away and
/// the Keychain becomes the only source.
@MainActor
final class AuthStore: ObservableObject {

    static let shared = AuthStore()

    @Published private(set) var session: AuthSession?

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.email }

    private static let keychainKey = "session"
    private var refreshTask: Task<String?, Never>?

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
    }

    /// Adopts a session read out of the WebView's localStorage.
    /// Ignores payloads that are not newer than what is already stored, so a
    /// WebView reload cannot downgrade a freshly refreshed native session.
    func adopt(fromWebSession incoming: AuthSession) {
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
