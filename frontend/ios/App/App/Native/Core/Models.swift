import Foundation

// Mirrors frontend/src/types.ts. The decoder uses
// `.convertFromSnakeCase`, so `profile_id` maps to `profileId` here.

struct LatestTransit: Codable, Hashable {
    let transitDate: String?
    let transitTime: String?
    let timezone: String?
    let locationName: String?
    let latitude: Double?
    let longitude: Double?
    let updatedAt: String?
    let tii: Double?
    let tensionRatio: Double?
    let feelsLike: String?
}

struct ProfileSummary: Codable, Hashable, Identifiable {
    let profileId: String
    let profileName: String
    let username: String
    /// Where the person was *born*. Not what the weather screens label the
    /// reading with — see `currentLocationName`.
    let locationName: String?
    let localBirthDatetime: String?
    let latestTransit: LatestTransit?
    let isOwn: Bool?
    let isFollowing: Bool?
    let followersCount: Int?
    let followingCount: Int?

    var id: String { profileId }

    /// `true` for the user's own profiles, `false` for followed ones.
    /// The backend omits the flag on some payloads; treat missing as own.
    var ownedByViewer: Bool { isOwn ?? true }

    /// Where the person is *now*: the transit location the last reading ran
    /// with — the one typed by hand on the web app — falling back to the city
    /// of that reading's timezone. Birth location is deliberately not in the
    /// chain; telling the two apart is the point.
    var currentLocationName: String? {
        if let name = latestTransit?.locationName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        guard let timezone = latestTransit?.timezone else { return nil }
        return Self.city(inTimezone: timezone)
    }

    /// "Europe/Minsk" → "Minsk", "America/Argentina/Buenos_Aires" → "Buenos Aires".
    /// A bare zone such as "UTC" names no city, so it yields nothing.
    private static func city(inTimezone identifier: String) -> String? {
        let parts = identifier.split(separator: "/")
        guard parts.count > 1, let city = parts.last else { return nil }
        return city.replacingOccurrences(of: "_", with: " ")
    }
}

struct ProfilesResponse: Codable {
    let profiles: [ProfileSummary]
    let primaryProfileId: String?
}

// MARK: - TII zones

/// Tension Intensity Index bands. Mirrors frontend/src/tii-zones.ts so the
/// native list shows the same colours and labels as the web app.
enum TiiZone: String {
    case quiet, active, hot, extreme

    init(tii: Double) {
        switch tii {
        case ..<25: self = .quiet
        case ..<55: self = .active
        case ..<80: self = .hot
        default: self = .extreme
        }
    }
}

enum FeelsLike {
    /// Emoji for each feels-like label produced by the transit engine.
    static let emoji: [String: String] = [
        "Calm": "☁️",
        "Subtle pressure": "🌫️",
        "Grinding": "⛏",
        "Flowing": "☀️",
        "Dynamic": "⚡",
        "Pressured": "🪨",
        "Expansive": "🌅",
        "Charged": "⛈️",
        "Intense": "🔥",
        "Powerful": "🚀",
        "Volatile": "⚔️",
        "Explosive": "💥",
    ]

    static func emoji(for label: String?) -> String? {
        guard let label else { return nil }
        return emoji[label]
    }

    /// SF Symbol per label. The forecast list uses these instead of the emoji
    /// so the icon column matches Weather's, rendered multicolour.
    static func symbol(for label: String?) -> String {
        switch label {
        case "Calm": return "cloud.fill"
        case "Subtle pressure": return "cloud.fog.fill"
        case "Grinding": return "cloud.drizzle.fill"
        case "Flowing": return "sun.max.fill"
        case "Dynamic": return "cloud.sun.bolt.fill"
        case "Pressured": return "cloud.heavyrain.fill"
        case "Expansive": return "sun.horizon.fill"
        case "Charged": return "cloud.bolt.fill"
        case "Intense": return "flame.fill"
        case "Powerful": return "wind"
        case "Volatile": return "tornado"
        case "Explosive": return "cloud.bolt.rain.fill"
        default: return "sparkles"
        }
    }
}

// MARK: - Forecast

/// One transit-to-natal aspect from the forecast payload. Extra keys the API
/// sends (`exact_angle`, `delta`, `keywords`, `_tii_contribution`) are ignored.
struct TopTransit: Codable, Hashable, Identifiable {
    let transitObject: String
    let natalObject: String
    let aspect: String
    let orb: Double?
    let strength: String?
    let meaning: String?
    let action: String?

    var id: String { "\(transitObject)-\(aspect)-\(natalObject)" }

    /// "Saturn square Moon" — the headline form used across the app.
    var title: String { "\(transitObject) \(aspect) \(natalObject)" }
}

struct MoonPhase: Codable, Hashable {
    let phaseName: String
    let illuminationPct: Double?
    let moonSign: String?
    let moonDegree: Int?
    let phaseEmoji: String?
}

struct ForecastDay: Codable, Hashable, Identifiable {
    let date: String
    let tii: Double
    let tensionRatio: Double?
    let feelsLike: String
    let retrogradeCount: Int?
    let retrogradePlanets: [String]?
    let velocityDelta: Double?
    let velocityDirection: String?
    let topTransits: [TopTransit]?
    let moonPhase: MoonPhase?

    var id: String { date }

    var zone: TiiZone { TiiZone(tii: tii) }

    /// The forecast sends plain `YYYY-MM-DD` in the profile's timezone.
    var day: Date? { Self.dayFormatter.date(from: date) }

    /// "Today" for the first day, otherwise a short weekday name.
    func label(isToday: Bool) -> String {
        guard !isToday else { return "Today" }
        guard let day else { return date }
        return Self.weekdayFormatter.string(from: day)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()
}

struct ForecastResponse: Codable {
    let days: [ForecastDay]
}
