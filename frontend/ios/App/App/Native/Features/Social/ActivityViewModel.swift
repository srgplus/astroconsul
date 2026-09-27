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

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

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

        if items.isEmpty { state = .loading }
        do {
            let response = try await api.fetchActivity()
            items = response.items
            state = .loaded
        } catch {
            guard !error.isCancellation else { return }
            NSLog("[Activity] load failed: \(error.localizedDescription)")
            if items.isEmpty { state = .failed(error.localizedDescription) }
        }
    }

    /// Whether the reader follows this person's chart: what the server said,
    /// what they did on this screen, or what is already on their list.
    func isFollowed(_ item: ActivityItem, saved: Set<String>) -> Bool {
        guard let id = item.actor.profileId else { return true }
        return item.actorFollowed || followedHere.contains(id) || saved.contains(id)
    }

    /// Follows the person back through the list model, so the new page turns
    /// up in the pager the moment the screen is closed.
    func followBack(_ card: SocialCard, using list: ProfileListViewModel) async {
        guard let profile = card.profile, !following.contains(profile.profileId) else { return }

        #if DEBUG
        if WeatherPreviewHarness.isEnabled {
            followedHere.insert(profile.profileId)
            return
        }
        #endif

        following.insert(profile.profileId)
        defer { following.remove(profile.profileId) }

        if let error = await list.follow(profile) {
            errorText = error.localizedDescription
        } else {
            followedHere.insert(profile.profileId)
        }
    }
}
