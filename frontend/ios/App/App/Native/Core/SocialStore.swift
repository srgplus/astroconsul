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
            unreadActivity = try await api.fetchUnreadActivityCount()
        } catch {
            if !error.isCancellation {
                NSLog("[Social] unread count failed: \(error.localizedDescription)")
            }
        }
    }

    /// The Activity screen was looked at: the count goes at once, and the
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
        snapshots = [:]
        unreadActivity = 0
        pending = []
    }
}
