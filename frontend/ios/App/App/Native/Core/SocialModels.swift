import Foundation

// The social half of the API: likes, Activity, who follows and likes a chart,
// blocks and reports. Mirrors `app/api/v1/routes/social.py`; the decoder
// converts snake case, so `actor_followed` arrives as `actorFollowed`.

/// Another account, shown as its own chart: the profile it marked as its own,
/// or failing that the one it touched last. Every field is optional because an
/// account can like and follow without owning a chart at all, and a card for
/// it still has to be drawn.
struct SocialCard: Codable, Hashable {
    let profileId: String?
    let profileName: String?
    let username: String?
    let natalSummary: NatalSummary?
    /// The last numbers the chart was read at — intensity, tension and the
    /// feels-like word — so the preview a row opens shows the person's day.
    /// Optional so a card from a backend that predates it still decodes.
    var latestTransit: LatestTransit? = nil

    /// The name to print, falling back to what the app calls someone with
    /// nothing of their own to show.
    var displayName: String {
        guard let name = profileName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            return L("social.someone")
        }
        return name
    }

    /// The sign the Sun was in, for the glyph in the avatar circle: the chart
    /// builder writes "Aries 27°04'12\"", so the first word.
    var sunSign: String? {
        natalSummary?.sun?.split(separator: " ").first.map(String.init)
    }

    /// Enough of a profile to open the preview sheet on — the same screen a
    /// search result opens — or nil for an account with no chart to open.
    var profile: ProfileSummary? {
        guard let profileId, let profileName, let username else { return nil }
        return ProfileSummary(
            profileId: profileId,
            profileName: profileName,
            username: username,
            locationName: nil,
            localBirthDatetime: nil,
            latestTransit: latestTransit,
            isOwn: false,
            isFollowing: nil,
            followersCount: nil,
            followingCount: nil,
            natalSummary: natalSummary
        )
    }
}

/// The chart an Activity row is about: one of the reader's own.
struct ActivityTarget: Codable, Hashable {
    let profileId: String
    let profileName: String?
    let username: String?
}

/// One like or follow on one of the reader's profiles.
struct ActivityItem: Codable, Hashable, Identifiable {

    enum Kind: String, Codable {
        case like
        case follow
    }

    /// "like:12" or "follow:40" — unique across both kinds.
    let id: String
    let kind: Kind
    let createdAt: String
    var isUnread: Bool
    let actor: SocialCard
    /// The reader already follows the actor's chart, so the row offers no
    /// "Follow back".
    let actorFollowed: Bool
    let target: ActivityTarget
    /// On a like, the state that was liked: the feels-like word on screen.
    var feelsLike: String? = nil

    var date: Date? { SocialDate.parse(createdAt) }
}

/// `GET /api/v1/activity`.
struct ActivityResponse: Codable {
    let items: [ActivityItem]
    let unreadCount: Int
    let seenAt: String?
}

/// `GET /api/v1/activity/unread` — the badge alone.
struct UnreadActivityResponse: Codable {
    let unreadCount: Int
}

/// One row of "who likes" or "who follows" a chart.
struct SocialPerson: Codable, Hashable {
    let actor: SocialCard
    let createdAt: String
    let actorFollowed: Bool
    var feelsLike: String? = nil

    var date: Date? { SocialDate.parse(createdAt) }
}

/// `GET /api/v1/profiles/{id}/likes` and `.../followers`.
struct SocialPeopleResponse: Codable {
    let people: [SocialPerson]
}

/// What a like or an unlike answers: the chart's counts as they stand after
/// it, so the heart shows the server's number rather than a guess.
struct LikeResponse: Codable {
    let likesCount: Int
    /// Nil when the chart's owner keeps their counts to themselves.
    let followersCount: Int?
    let isLiked: Bool
    /// Today's likes per state and the reader's own, as they stand after it.
    var stateLikes: [String: Int]? = nil
    var myStateLikes: [String]? = nil
}

/// `GET/PUT /api/v1/social/settings`: what the account shows other people
/// about itself. So far one switch, the followers and following counts.
struct SocialSettings: Codable, Equatable {
    let showCounts: Bool
    /// Whether a like, or a new follower, is pushed to the reader's phones.
    /// Optional so an answer from a server that predates the pushes decodes.
    var pushLikes: Bool? = nil
    var pushFollows: Bool? = nil
}

/// One account this reader has blocked.
struct BlockedAccount: Codable, Hashable, Identifiable {
    let blockId: Int
    let createdAt: String
    let actor: SocialCard

    var id: Int { blockId }
}

/// `GET /api/v1/blocks`.
struct BlocksResponse: Codable {
    let blocks: [BlockedAccount]
}

/// `POST /api/v1/reports`.
struct ReportResponse: Codable {
    let reportId: Int?
    let blocked: Bool
}

/// What a person can report a profile for, in the order the sheet offers
/// them. The raw values are the API's.
enum ReportReason: String, CaseIterable, Identifiable {
    case spam
    case harassment
    case impersonation
    case inappropriate
    case other

    var id: String { rawValue }

    var label: String { L("complaint.reason.\(rawValue)") }
}

/// The API's timestamps: ISO 8601 in UTC, with or without a fraction.
enum SocialDate {

    static func parse(_ raw: String) -> Date? {
        plain.date(from: raw) ?? fractional.date(from: raw)
    }

    /// "5 min ago", "2 days ago" — in the app's language, not the device's.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = LanguageStore.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
