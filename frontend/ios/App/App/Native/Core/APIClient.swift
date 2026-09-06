import Foundation

enum APIError: LocalizedError {
    case notSignedIn
    case http(status: Int, detail: String?)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to load your profiles."
        case let .http(status, detail):
            return detail ?? "Request failed (HTTP \(status))."
        case let .transport(error):
            return error.localizedDescription
        case .decoding:
            return "The server sent an unexpected response."
        }
    }

    var isUnauthorized: Bool {
        if case let .http(status, _) = self { return status == 401 }
        return false
    }
}

/// Talks to the same REST API the web app uses, so native screens need no
/// WebView. Auth comes from `AuthStore`.
actor APIClient {

    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    // MARK: - Profiles

    func fetchProfiles() async throws -> ProfilesResponse {
        try await get("/api/v1/profiles")
    }

    func setPrimaryProfile(id: String) async throws {
        struct Body: Encodable { let profile_id: String }
        let _: EmptyResponse = try await send(
            "/api/v1/profiles/primary",
            method: "PUT",
            body: Body(profile_id: id)
        )
    }

    func unfollowProfile(id: String) async throws {
        let path = "/api/v1/profiles/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)/follow"
        let _: EmptyResponse = try await send(path, method: "DELETE", body: Optional<EmptyResponse>.none)
    }

    // MARK: - Cosmic weather

    /// One call feeds the whole weather screen: today plus the next days, each
    /// with TII, feels-like, top transits, moon phase and retrogrades.
    func fetchForecast(
        profileId: String,
        timezone: String = TimeZone.current.identifier,
        days: Int = 10
    ) async throws -> ForecastResponse {
        let id = profileId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? profileId
        return try await get(
            "/api/v1/profiles/\(id)/transits/forecast",
            query: [
                URLQueryItem(name: "timezone", value: timezone),
                URLQueryItem(name: "days", value: String(days)),
            ]
        )
    }

    // MARK: - Request plumbing

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(path, method: "GET", query: query, body: Optional<EmptyResponse>.none)
    }

    private func send<T: Decodable, B: Encodable>(
        _ path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: B?
    ) async throws -> T {
        guard let token = await AuthStore.shared.validAccessToken() else {
            throw APIError.notSignedIn
        }

        var components = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query.isEmpty ? nil : query

        guard let url = components?.url else {
            throw APIError.http(status: -1, detail: "Could not build a URL for \(path).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(status: -1, detail: nil)
        }

        guard (200..<300).contains(http.statusCode) else {
            let detail = Self.errorDetail(from: data)
            NSLog("[API] \(method) \(path) -> HTTP \(http.statusCode): \(detail ?? "no detail")")
            throw APIError.http(status: http.statusCode, detail: detail)
        }

        // Endpoints such as DELETE /follow answer 204 with no body.
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            NSLog("[API] decode failed for \(path): \(error)")
            throw APIError.decoding(error)
        }
    }

    /// FastAPI returns `{"detail": "..."}` on errors.
    private static func errorDetail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["detail"] as? String
    }
}

struct EmptyResponse: Codable {}
