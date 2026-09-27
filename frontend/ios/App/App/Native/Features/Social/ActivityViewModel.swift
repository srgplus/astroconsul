import Foundation

/// Feeds the Activity screen: who liked and who followed the reader's charts.
@MainActor
final class ActivityViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var items: [ActivityItem] = []

    /// Charts with a "Follow back" in flight.
    @Published private(set) var following: Set<String> = []

    /// Charts followed back from this screen, so the row says "Following"
    /// straight away rather than after the next load.
    @Published private(set) var followedHere: Set<String> = []

    @Published var errorText: String?

    /// Rows newer than the last visit, and the rest. Split on what the server
    /// said when the screen opened, so rows do not move from "New" to
    /// "Earlier" under the reader's finger once the visit is recorded.
    var unread: [ActivityItem] { items.filter(\.isUnread) }
    var earlier: [ActivityItem] { items.filter { !$0.isUnread } }

    func load() async {
        #if DEBUG
        if WeatherPreviewHarness.isEnabled {
            items = WeatherPreviewData.activity.items
            state = .loaded
            return
        }
        #endif

        // The rows from the last fetch, which the home screen asks for ahead
        // whenever the bell's count changes: the screen opens on them and the
        // request below freshens them in place. A kept empty list counts too:
        // the empty state is the answer, not a spinner in front of it.
        if items.isEmpty {
            if let kept = SocialStore.shared.activity {
                items = kept
                state = .loaded
            } else {
                state = .loading
            }
        }
        do {
            items = try await SocialStore.shared.fetchActivity()
            state = .loaded
        } catch {
            guard !error.isCancellation else { return }
            NSLog("[Activity] load failed: \(error.localizedDescription)")
            // Only over a spinner: kept rows, or a kept empty list, stay up.
            if state == .loading { state = .failed(error.localizedDescription) }
        }
    }

    /// Whether the reader follows this person's chart: what the server said,
    /// what they did on this screen, or what is already on their list.
    func isFollowed(_ item: ActivityItem, saved: Set<String>) -> Bool {
        guard let id = item.actor.profileId else { return true }
        return item.actorFollowed || followedHere.contains(id) || saved.contains(id)
    }

    /// Follows the person back through the list model, so the new page turns
    /// up in the pager behind the screen.
    ///
    /// The row says "Following" at the tap and the request catches up, the
    /// way the heart does; a refusal takes it back and says why.
    func followBack(_ card: SocialCard, using list: ProfileListViewModel) async {
        guard let profile = card.profile, !following.contains(profile.profileId) else { return }
        let id = profile.profileId
        followedHere.insert(id)

        #if DEBUG
        if WeatherPreviewHarness.isEnabled { return }
        #endif

        following.insert(id)
        defer { following.remove(id) }

        if let error = await list.follow(profile, waitingForList: false) {
            followedHere.remove(id)
            errorText = error.isCancellation ? nil : error.localizedDescription
        }
    }
}
