import Foundation

/// What the social half of the app has to agree on across screens: the likes
/// on each chart, and how much of Activity is unread.
///
/// A like is for a *state* of a chart's sky — the feels-like word on screen,
/// today. When the word changes, or the day does, that is new content and the
/// heart is empty again. So a chart carries likes per state, and a heart asks
/// about the state it is drawn over.
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
        var count: Int
        var isLiked: Bool
    }

    /// Today's likes on one chart: how many each state has, and which of
    /// them the reader liked.
    struct Snapshot: Equatable {
        var byState: [String: Int]
        var mine: Set<String>
    }

    /// Snapshots newer than the payloads — what a like or an unlike answered,
    /// or the optimistic guess while it is out. Cleared per chart when a fresh
    /// listing arrives, so the server's numbers win as soon as there are newer.
    @Published private(set) var snapshots: [String: Snapshot] = [:]

    /// Likes and follows on the reader's charts since Activity was last
    /// opened. Drives the count on the bell.
    @Published private(set) var unreadActivity = 0

    /// Charts with a like request in flight, so a second tap waits for the
    /// first instead of racing it.
    @Published private(set) var pending: Set<String> = []

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
        return Like(count: snapshot.byState[state] ?? 0, isLiked: snapshot.mine.contains(state))
    }

    private func snapshot(for profile: ProfileSummary) -> Snapshot {
        if let newer = snapshots[profile.profileId] { return newer }
        return Self.snapshot(stateLikes: profile.stateLikes, mine: profile.myStateLikes)
    }

    private static func snapshot(stateLikes: [String: Int]?, mine: [String]?) -> Snapshot {
        Snapshot(byState: stateLikes ?? [:], mine: Set(mine ?? []))
    }

    /// Takes the payload's numbers as the truth again, for every chart a
    /// fresh listing just brought in.
    func adopt(_ profiles: [ProfileSummary]) {
        for profile in profiles where profile.stateLikes != nil {
            snapshots[profile.profileId] = nil
        }
    }

    /// Likes or unlikes one state, drawn at once and then corrected to what
    /// the server says. A refused request puts the heart back, and hands the
    /// error to the caller to show.
    @discardableResult
    func toggleLike(_ profile: ProfileSummary, state: String, tii: Double?) async -> Error? {
        let id = profile.profileId
        guard !pending.contains(id) else { return nil }

        let before = snapshot(for: profile)
        var guess = before
        let wasLiked = before.mine.contains(state)
        if wasLiked {
            guess.mine.remove(state)
            guess.byState[state] = max((before.byState[state] ?? 1) - 1, 0)
        } else {
            guess.mine.insert(state)
            guess.byState[state] = (before.byState[state] ?? 0) + 1
        }
        snapshots[id] = guess

        #if DEBUG
        if isOffline { return nil }
        #endif

        pending.insert(id)
        defer { pending.remove(id) }

        do {
            let feelsLike = state.isEmpty ? nil : state
            let response = wasLiked
                ? try await api.unlikeProfile(id: id, feelsLike: feelsLike)
                : try await api.likeProfile(id: id, feelsLike: feelsLike, tii: tii)
            snapshots[id] = Self.snapshot(stateLikes: response.stateLikes, mine: response.myStateLikes)
            return nil
        } catch {
            NSLog("[Social] like toggle failed for \(id): \(error.localizedDescription)")
            snapshots[id] = before
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
            let count = try await api.fetchUnreadActivityCount()
            unreadActivity = count
            // The app icon says the same as the bell.
            Task { await PushNotifications.shared.setBadge(count) }
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
        Task { await PushNotifications.shared.setBadge(0) }
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
