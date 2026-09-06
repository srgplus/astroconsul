import Foundation

/// Direct calls to Supabase's auth REST API.
///
/// Deliberately does not go through Capacitor: the `@capacitor/browser` and
/// `@capacitor/app` plugins are not linked into the iOS binary, which is why
/// the WebView's Google and Apple buttons do nothing. Native sign-in has no
/// such dependency.
enum SupabaseAuthAPI {

    enum AuthAPIError: LocalizedError {
        case http(status: Int, message: String?)
        case transport(Error)
        case badResponse

        var errorDescription: String? {
            switch self {
            case let .http(status, message):
                if let message, !message.isEmpty { return message }
                switch status {
                case 429: return "Too many attempts. Wait a minute and try again."
                case 400, 401, 403: return "That did not work. Check the details and try again."
                default: return "Request failed (HTTP \(status))."
                }
            case let .transport(error):
                return error.localizedDescription
            case .badResponse:
                return "The server sent an unexpected response."
            }
        }
    }

    // MARK: - Email code (OTP)

    /// Asks Supabase to email a sign-in code.
    ///
    /// Whether the message carries a 6-digit code or only a magic link depends
    /// on the "Magic Link" email template in the Supabase dashboard: the
    /// template must include `{{ .Token }}` for the code to be shown.
    static func sendEmailCode(email: String) async throws {
        _ = try await post(
            path: "auth/v1/otp",
            query: nil,
            body: ["email": email, "create_user": true],
            decodeSession: false
        )
    }

    /// Exchanges the emailed code for a session.
    static func verifyEmailCode(email: String, code: String) async throws -> AuthSession {
        guard let session = try await post(
            path: "auth/v1/verify",
            query: nil,
            body: ["type": "email", "email": email, "token": code],
            decodeSession: true
        ) else {
            throw AuthAPIError.badResponse
        }
        return session
    }

    // MARK: - Password

    static func signIn(email: String, password: String) async throws -> AuthSession {
        guard let session = try await post(
            path: "auth/v1/token",
            query: "grant_type=password",
            body: ["email": email, "password": password],
            decodeSession: true
        ) else {
            throw AuthAPIError.badResponse
        }
        return session
    }

    // MARK: - Apple

    /// Trades the identity token from `ASAuthorizationController` for a
    /// Supabase session. `nonce` is the raw (unhashed) value that was hashed
    /// into the Apple request.
    static func signInWithApple(idToken: String, nonce: String?) async throws -> AuthSession {
        var body: [String: Any] = ["provider": "apple", "id_token": idToken]
        if let nonce { body["nonce"] = nonce }

        guard let session = try await post(
            path: "auth/v1/token",
            query: "grant_type=id_token",
            body: body,
            decodeSession: true
        ) else {
            throw AuthAPIError.badResponse
        }
        return session
    }

    // MARK: - Google

    /// URL to open in `ASWebAuthenticationSession` for a provider redirect flow.
    static func authorizeURL(provider: String, redirectTo: String) -> URL {
        var components = URLComponents(
            url: AppConfig.supabaseURL.appendingPathComponent("auth/v1/authorize"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirectTo),
        ]
        return components.url!
    }

    /// Reads a session out of the OAuth callback URL.
    ///
    /// The client uses Supabase's default implicit flow, so tokens arrive in
    /// the URL fragment. PKCE (`?code=`) is handled too, in case the flow type
    /// is switched later.
    static func session(fromCallback url: URL) async throws -> AuthSession? {
        if let fragment = url.fragment, !fragment.isEmpty {
            let values = parseQuery(fragment)
            if let access = values["access_token"], let refresh = values["refresh_token"] {
                let expiresAt = values["expires_at"].flatMap(Double.init)
                    ?? Date().timeIntervalSince1970 + (values["expires_in"].flatMap(Double.init) ?? 3600)
                return AuthSession(
                    accessToken: access,
                    refreshToken: refresh,
                    expiresAt: expiresAt,
                    email: nil
                )
            }
            if let error = values["error_description"] ?? values["error"] {
                throw AuthAPIError.http(status: 400, message: error.replacingOccurrences(of: "+", with: " "))
            }
        }

        if let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value {
            return try await post(
                path: "auth/v1/token",
                query: "grant_type=pkce",
                body: ["auth_code": code],
                decodeSession: true
            )
        }

        return nil
    }

    // MARK: - Plumbing

    private static func post(
        path: String,
        query: String?,
        body: [String: Any],
        decodeSession: Bool
    ) async throws -> AuthSession? {
        var url = AppConfig.supabaseURL.appendingPathComponent(path)
        if let query {
            url = URL(string: url.absoluteString + "?" + query)!
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthAPIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthAPIError.badResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = errorMessage(from: data)
            NSLog("[Auth] POST \(path) -> HTTP \(http.statusCode): \(message ?? "no message")")
            throw AuthAPIError.http(status: http.statusCode, message: message)
        }

        guard decodeSession else { return nil }
        return try SupabaseTokenResponse.decode(data)
    }

    /// Supabase returns `error_description`, `msg` or `message` depending on
    /// which part of GoTrue rejected the call.
    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["error_description", "msg", "message", "error"] {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func parseQuery(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            result[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
        }
        return result
    }
}
