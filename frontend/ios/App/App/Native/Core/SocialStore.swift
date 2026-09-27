import Foundation

/// What the social half of the app has to agree on across screens: the like
/// on each chart, and how much of Activity is unread.
///
/// A like is tapped on a weather page, on a search preview or on an Activity
/// row, and all three can be on screen within seconds of each other. Each
/// reading its own copy of the profile payload would show a heart filled on
/// one screen and empty on the next, so they all ask here, and a tap anywhere
/// is seen everywhere.
@MainActor
final class SocialStore: ObservableObject {

    static let shared = SocialStore()

    struct Like: Equatable {
        var count: Int
        var isLiked: Bool
    }

    /// Likes the reader changed this session, keyed by profile id, on top of
    /// what the payloads said. Cleared per profile when a fresh payload
    /// arrives, so the server's number wins as soon as there is a newer one.
    @Published private(set) var likes: [String: Like] = [:]

    /// Likes and follows on the reader's profiles since Activity was last
    /// opened. Drives the dot on the Activity button.
    @Published private(set) var unreadActivity = 0

    /// Profiles with a like request in flight, so a second tap waits for the
    /// first instead of racing it.
    @Published private(set) var pending: Set<String> = []

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    #if DEBUG
    /// The harness has no account: a tap flips the heart locally and the
    /// Activity dot shows a fixed number.
    private var isOffline: Bool { WeatherPreviewHarness.isEnabled }
    #endif

    /// The like on a chart as the reader should see it: their own change if
    /// they made one, the payload's otherwise.
    func like(for profile: ProfileSummary) -> Like {
        likes[profile.profileId] ?? Like(count: profile.likesCount ?? 0, isLiked: profile.isLiked ?? false)
    }

    /// Takes the payload's numbers as the truth again, for every profile a
    /// fresh listing just brought in.
    func adopt(_ profiles: [ProfileSummary]) {
        for profile in profiles where profile.likesCount != nil {
            likes[profile.profileId] = nil
        }
    }

    /// Likes or unlikes, drawn at once and then corrected to whatever the
    /// server says the count is. A refused request puts the heart back, and
    /// hands the error to the caller to show.
    @discardableResult
    func toggleLike(_ profile: ProfileSummary) async -> Error? {
        let id = profile.profileId
        guard !pending.contains(id) else { return nil }

        let before = like(for: profile)
        let after = Like(count: max(before.count + (before.isLiked ? -1 : 1), 0), isLiked: !before.isLiked)
        likes[id] = after

        #if DEBUG
        if isOffline { return nil }
        #endif

        pending.insert(id)
        defer { pending.remove(id) }

        do {
            let response = before.isLiked
                ? try await api.unlikeProfile(id: id)
                : try await api.likeProfile(id: id)
            likes[id] = Like(count: response.likesCount, isLiked: response.isLiked)
            return nil
        } catch {
            NSLog("[Social] like toggle failed for \(id): \(error.localizedDescription)")
            likes[id] = before
            return error.isCancellation ? nil : error
        }
    }

    /// Asks for the unread count. Quiet on failure: a badge that misses one
    /// refresh is not worth a message over the weather.
    func refreshUnread() async {
        #if DEBUG
        if isOffline {
            unreadActivity = WeatherPreviewData.activity.items.filter(\.isUnread).count
            return
        }
        #endif
        guard AuthStore.shared.isSignedIn else {
            unreadActivity = 0
            return
        }
        do {
            unreadActivity = try await api.fetchUnreadActivityCount()
        } catch {
            if !error.isCancellation {
                NSLog("[Social] unread count failed: \(error.localizedDescription)")
            }
        }
    }

    /// The Activity screen was looked at: the dot goes at once, and the
    /// server is told so it stays gone on the next launch.
    func markActivitySeen() async {
        unreadActivity = 0
        #if DEBUG
        if isOffline { return }
        #endif
        do {
            try await api.markActivitySeen()
        } catch {
            if !error.isCancellation {
                NSLog("[Social] mark seen failed: \(error.localizedDescription)")
            }
        }
    }

    /// Everything here belongs to the account that was signed in.
    func reset() {
        likes = [:]
        unreadActivity = 0
        pending = []
    }
}
