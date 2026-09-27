import Foundation

/// What the social half of the app has to agree on across screens: the likes
/// on each chart, and how much of Activity is unread.
///
/// A like is for a *state* of a chart's sky — the feels-like word on screen,
/// today. When the word changes, or the day does, that is new content and the
/// heart is empty again. So a heart asks whether the reader liked the state
/// it is drawn over, and shows beside it every like the chart has ever had:
/// a number that only grows, the way a profile's likes do elsewhere.
///
/// The heart is tapped on a weather page, on a search preview or from a row
/// that opened one, and those can be on screen within seconds of each other.
/// Each reading its own copy of the profile payload would show a heart filled
/// on one screen and empty on the next, so they all ask here, and a tap
/// anywhere is seen everywhere.
@MainActor
final class SocialStore: ObservableObject {

    static let shared = SocialStore()

    struct Like: Equatable {
        /// Every like the chart has had, its owner's left out. Nil when the
        /// owner hides their numbers: a heart with nothing beside it.
        var count: Int?
        var isLiked: Bool
    }

    /// One chart's likes: all it has had, and which of today's states the
    /// reader liked.
    struct Snapshot: Equatable {
        var total: Int?
        var mine: Set<String>
    }

    /// Snapshots newer than the payloads — what a like or an unlike answered,
    /// or the optimistic guess while it is out. Cleared per chart when a fresh
    /// listing arrives, so the server's numbers win as soon as there are newer.
    @Published private(set) var snapshots: [String: Snapshot] = [:]

    /// Likes and follows on the reader's charts since Activity was last
    /// opened. Drives the count on the bell.
    @Published private(set) var unreadActivity = 0

    /// One heart: a chart, and the state of its sky the like is for.
    private struct LikeKey: Hashable {
        let profileId: String
        let state: String
    }

    /// What the reader last asked of each heart, while the server has yet to
    /// hear it. A tap changes this and the snapshot and nothing else, so the
    /// heart answers every tap at once, however fast they come.
    private var wanted: [LikeKey: Bool] = [:]

    /// Hearts with a request out. A tap while one is out is not dropped: it
    /// changes `wanted`, and the request, once answered, sends what the
    /// reader wants now if the server does not have it yet.
    private var pending: Set<LikeKey> = []

    /// The last Activity the server sent. The screen opens on it at once and
    /// asks again underneath, rather than standing behind a spinner for a
    /// request that most times brings back the same rows. Not published:
    /// nothing draws from it but the screen, which copies it on open.
    private(set) var activity: [ActivityItem]?

    /// The unread count the cached rows were fetched at. The badge asks the
    /// server on every return to the app; when it answers with another
    /// number, the rows are out of date and are fetched before the tap.
    private var activityUnreadAtFetch: Int?

    /// The Activity request in flight, shared by whoever asks while it is
    /// out: the fetch ahead and the screen opening can land together.
    private var activityRequest: Task<ActivityResponse, Error>?

    /// Who follows each of the reader's charts, as last fetched, for the
    /// people sheet to open on while it asks again.
    private(set) var followers: [String: [SocialPerson]] = [:]

    /// Moved on by every `reset`, so a request that set out for the last
    /// account cannot leave its rows behind for the next one.
    private var generation = 0

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    #if DEBUG
    /// The harness has no account: a tap flips the heart locally and the
    /// bell shows a fixed number.
    private var isOffline: Bool { WeatherPreviewHarness.isEnabled }
    #endif

    /// The state key for a feels-like word: the word itself, or empty for a
    /// chart with no reading yet — the same key the API stores.
    static func state(_ feelsLike: String?) -> String {
        feelsLike?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// The heart over one state of a chart, as the reader should see it.
    func like(for profile: ProfileSummary, state: String) -> Like {
        let snapshot = snapshot(for: profile)
        return Like(count: snapshot.total, isLiked: snapshot.mine.contains(state))
    }

    private func snapshot(for profile: ProfileSummary) -> Snapshot {
        if let newer = snapshots[profile.profileId] { return newer }
        return Self.snapshot(total: profile.likesTotal, mine: profile.myStateLikes)
    }

    private static func snapshot(total: Int?, mine: [String]?) -> Snapshot {
        Snapshot(total: total, mine: Set(mine ?? []))
    }

    /// A snapshot with one state liked or not, the total moved to match.
    private static func snapshot(_ snapshot: Snapshot, liking liked: Bool, state: String) -> Snapshot {
        guard snapshot.mine.contains(state) != liked else { return snapshot }
        var next = snapshot
        if liked {
            next.mine.insert(state)
            next.total = snapshot.total.map { $0 + 1 }
        } else {
            next.mine.remove(state)
            next.total = snapshot.total.map { max($0 - 1, 0) }
        }
        return next
    }

    /// Takes the payload's numbers as the truth again, for every chart a
    /// fresh listing just brought in. Not for a chart whose heart is still
    /// on its way to the server: the listing was read before the tap landed,
    /// and would put the heart back for a moment.
    func adopt(_ profiles: [ProfileSummary]) {
        for profile in profiles where profile.myStateLikes != nil {
            let id = profile.profileId
            guard !pending.contains(where: { $0.profileId == id }) else { continue }
            snapshots[id] = nil
        }
    }

    /// Likes or unlikes one state. The heart flips on every tap, at once:
    /// the server is told behind it, one request at a time per heart, and
    /// only what the reader wants by the time the last answer comes is sent.
    /// Like, unlike, like while the first request is out ends as that one
    /// like and no more. A refused request puts the heart back to what the
    /// server has, and hands the error to the caller to show. Never called
    /// on the reader's own charts: there the heart is a count and nothing to
    /// tap.
    @discardableResult
    func toggleLike(_ profile: ProfileSummary, state: String, tii: Double?) async -> Error? {
        let id = profile.profileId
        let shown = snapshot(for: profile)
        let liked = !shown.mine.contains(state)
        snapshots[id] = Self.snapshot(shown, liking: liked, state: state)

        #if DEBUG
        if isOffline { return nil }
        #endif

        let key = LikeKey(profileId: id, state: state)
        wanted[key] = liked
        // The request out for this heart sends this tap when it answers.
        guard !pending.contains(key) else { return nil }
        pending.insert(key)
        defer { pending.remove(key) }

        let account = generation
        let feelsLike = state.isEmpty ? nil : state
        // What the server has: the heart as it was before the first tap.
        var confirmed = !liked
        while let want = wanted[key], want != confirmed {
            do {
                let response = want
                    ? try await api.likeProfile(id: id, feelsLike: feelsLike, tii: tii)
                    : try await api.unlikeProfile(id: id, feelsLike: feelsLike)
                // Signed out while it was out: the heart was the last account's.
                guard account == generation else { return nil }
                confirmed = want
                // Tapped again meanwhile: the newer guess stays on screen
                // until the request that carries it answers.
                if wanted[key] == want {
                    snapshots[id] = Self.snapshot(total: response.likesTotal, mine: response.myStateLikes)
                }
            } catch {
                guard account == generation else { return nil }
                NSLog("[Social] like toggle failed for \(id): \(error.localizedDescription)")
                wanted[key] = nil
                if let current = snapshots[id] {
                    snapshots[id] = Self.snapshot(current, liking: confirmed, state: state)
                }
                return error.isCancellation ? nil : error
            }
        }
        wanted[key] = nil
        return nil
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
            let count = try await api.fetchUnreadActivityCount()
            unreadActivity = count
            // The app icon says what the bell and the chats button say.
            Task { await PushNotifications.shared.syncBadge() }
            // Something came in since the rows were fetched, or there are no
            // rows yet: fetched now, in the background, so the bell opens on
            // them rather than on a spinner.
            if activity == nil || activityUnreadAtFetch != count {
                prefetchActivity()
            }
        } catch {
            if !error.isCancellation {
                NSLog("[Social] unread count failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Activity

    /// Fetches Activity and keeps it for the next open. A request already
    /// out is joined rather than doubled.
    func fetchActivity() async throws -> [ActivityItem] {
        let request: Task<ActivityResponse, Error>
        if let activityRequest {
            request = activityRequest
        } else {
            request = Task { [api] in try await api.fetchActivity() }
            activityRequest = request
        }
        defer {
            if activityRequest == request { activityRequest = nil }
        }
        let account = generation
        let response = try await request.value
        // Signed out while it was out: these rows are the last account's.
        guard account == generation else { throw CancellationError() }
        activity = response.items
        activityUnreadAtFetch = response.unreadCount
        return response.items
    }

    private func prefetchActivity() {
        Task {
            do {
                _ = try await fetchActivity()
            } catch {
                if !error.isCancellation {
                    NSLog("[Social] activity prefetch failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// The Activity screen was looked at: the count goes at once, and the
    /// server is told so it stays gone on the next launch.
    func markActivitySeen() async {
        unreadActivity = 0
        // Unread messages stay on the icon: Activity is only half of it.
        Task { await PushNotifications.shared.syncBadge() }
        // The kept rows have been read too. Left marked new, the next open
        // would show them under "New" until the refresh moved them down.
        activity = activity?.map { item -> ActivityItem in
            var read = item
            read.isUnread = false
            return read
        }
        activityUnreadAtFetch = 0
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

    // MARK: - Followers

    /// Who follows one of the reader's charts, kept for the next open.
    func fetchFollowers(of profileId: String) async throws -> [SocialPerson] {
        let account = generation
        let people = try await api.fetchFollowers(profileId: profileId)
        if account == generation { followers[profileId] = people }
        return people
    }

    /// Drops a chart's kept followers: after a block, the list it holds has
    /// someone in it who is no longer there.
    func forgetFollowers(of profileId: String) {
        followers[profileId] = nil
    }

    /// Everything here belongs to the account that was signed in.
    func reset() {
        snapshots = [:]
        unreadActivity = 0
        wanted = [:]
        pending = []
        generation += 1
        activityRequest?.cancel()
        activityRequest = nil
        activity = nil
        activityUnreadAtFetch = nil
        followers = [:]
        // The icon's number was the last account's unread.
        Task { await PushNotifications.shared.setBadge(0) }
    }
}
