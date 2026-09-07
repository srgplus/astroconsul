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
        let _: EmptyResponse = try await send(followPath(id), method: "DELETE", body: Optional<EmptyResponse>.none)
    }

    func followProfile(id: String) async throws {
        let _: EmptyResponse = try await send(followPath(id), method: "POST", body: Optional<EmptyResponse>.none)
    }

    private func followPath(_ id: String) -> String {
        "/api/v1/profiles/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)/follow"
    }

    // MARK: - Discovery

    /// Public profile search. The route drops the caller's own profiles but
    /// says nothing about which of the rest are already followed, so the
    /// caller matches these against the saved list.
    func searchProfiles(query: String) async throws -> [ProfileSummary] {
        let response: ProfileSearchResponse = try await get(
            "/api/v1/profiles/search",
            query: [URLQueryItem(name: "q", value: query)]
        )
        return response.results
    }

    /// What to offer before the first keystroke. Featured profiles are curated
    /// server-side and the list can be empty, which the screen treats as "no
    /// suggestions" rather than as a failure.
    func fetchFeaturedProfiles() async throws -> [ProfileSummary] {
        let response: FeaturedProfilesResponse = try await get("/api/v1/public/featured")
        return response.profiles
    }

    /// The full profile, chart and all. The birth data the edit sheet works
    /// from lives only here — the list payload carries none of it.
    func fetchProfileDetail(id: String) async throws -> ProfileDetailResponse {
        try await get("/api/v1/profiles/\(Self.escape(id))")
    }

    /// Fields the edit sheet can change. Snake case spelled out: the encoder
    /// converts nothing.
    struct ProfileUpdate: Encodable {
        let profile_name: String
        let username: String
        let birth_date: String
        let birth_time: String
        let timezone: String?
        let location_name: String?
        let latitude: Double
        let longitude: Double
        /// `nil` lets the API infer it from the timezone: local when there is
        /// one, UT when there is not.
        let time_basis: String?
    }

    @discardableResult
    func updateProfile(id: String, update: ProfileUpdate) async throws -> ProfileDetailResponse {
        try await send("/api/v1/profiles/\(Self.escape(id))", method: "PATCH", body: update)
    }

    func deleteProfile(id: String) async throws {
        let _: EmptyResponse = try await send(
            "/api/v1/profiles/\(Self.escape(id))",
            method: "DELETE",
            body: Optional<EmptyResponse>.none
        )
    }

    // MARK: - Locations

    /// Geocoder autocomplete. The picked candidate is what supplies the
    /// coordinates and the timezone, so nothing on the edit sheet asks the
    /// person to type either.
    func searchPlaces(query: String) async throws -> [PlaceCandidate] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return [] }
        return try await get("/api/v1/locations/search", query: [URLQueryItem(name: "q", value: term)])
    }

    /// Geocodes a place typed out in full, for a birthplace that was edited
    /// without picking a suggestion. It answers 400 when the name matches
    /// nothing, which is the answer the sheet needs.
    func resolvePlace(name: String) async throws -> ResolvedLocation {
        struct Body: Encodable { let location_name: String }
        return try await send(
            "/api/v1/locations/resolve",
            method: "POST",
            body: Body(location_name: name)
        )
    }

    private static func escape(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }

    // MARK: - Cosmic weather

    /// One call feeds the whole weather screen: today plus the next days, each
    /// with TII, feels-like, top transits, moon phase and retrogrades.
    /// `startDate` is `YYYY-MM-DD`; without one the window starts today, which
    /// is only right while the screen is reading the present moment.
    func fetchForecast(
        profileId: String,
        timezone: String = TimeZone.current.identifier,
        days: Int = 10,
        startDate: String? = nil
    ) async throws -> ForecastResponse {
        let id = profileId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? profileId
        var query = [
            URLQueryItem(name: "timezone", value: timezone),
            URLQueryItem(name: "days", value: String(days)),
        ]
        if let startDate {
            query.append(URLQueryItem(name: "start_date", value: startDate))
        }
        return try await get("/api/v1/profiles/\(id)/transits/forecast", query: query)
    }

    /// Place autocomplete, the same endpoint the web's location field uses.
    func searchLocations(query: String) async throws -> [PlaceCandidate] {
        try await get(
            "/api/v1/locations/search",
            query: [URLQueryItem(name: "q", value: query)]
        )
    }

    /// The transit report for one moment. `includeTiming` is what turns the
    /// aspects' start/peak/end dates on, and it is the slow half of the call,
    /// so the screen asks for it separately from the forecast.
    func fetchTransitReport(
        profileId: String,
        date: String,
        time: String,
        timezone: String,
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        includeTiming: Bool = true
    ) async throws -> TransitReport {
        // Snake case spelled out: the encoder here converts nothing.
        struct Body: Encodable {
            let transit_date: String
            let transit_time: String
            let timezone: String
            let location_name: String?
            let latitude: Double?
            let longitude: Double?
            let include_timing: Bool
            let lang: String
        }

        let id = profileId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? profileId
        return try await send(
            "/api/v1/profiles/\(id)/transits/report",
            method: "POST",
            body: Body(
                transit_date: date,
                transit_time: time,
                timezone: timezone,
                location_name: locationName,
                latitude: latitude,
                longitude: longitude,
                include_timing: includeTiming,
                // The route defaults to Russian; the native screens are English.
                lang: "en"
            )
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
