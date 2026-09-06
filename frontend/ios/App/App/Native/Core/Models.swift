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
}
