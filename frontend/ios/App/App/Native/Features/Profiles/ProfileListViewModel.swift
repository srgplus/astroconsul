import Foundation

@MainActor
final class ProfileListViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case signedOut
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var profiles: [ProfileSummary] = []
    @Published private(set) var primaryProfileId: String?

    private let api: APIClient

    /// The in-flight load, owned by the model rather than by whoever asked
    /// for it. See `load(showSpinner:)`.
    private var loadTask: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
    }

    #if DEBUG
    /// Seeds a loaded list for previews and the `-uiPreviewWeather` harness.
    init(previewProfiles: [ProfileSummary], primaryProfileId: String?) {
        self.api = .shared
        self.profiles = previewProfiles
        self.primaryProfileId = primaryProfileId
        self.state = .loaded
    }
    #endif

    /// The primary profile, whichever section the API thinks it belongs to.
    ///
    /// On the owner's own account the API can report the primary profile with
    /// `is_own: false`, so a plain `ownedByViewer` filter drops it into
    /// "Following" and buries it below every followed profile.
    private var primaryProfile: ProfileSummary? {
        guard let primaryProfileId else { return nil }
        return profiles.first { $0.profileId == primaryProfileId }
    }

    /// Own profiles sorted by name, primary lifted to the top.
    ///
    /// Sorting first and lifting afterwards, rather than special-casing the
    /// primary inside the comparator: that comparator claimed `lhs < rhs` even
    /// when both were the primary, which is not a strict weak ordering, and
    /// Swift's sort left the primary mid-list. That in turn put the pager's
    /// location arrow in the middle of the dots.
    var ownProfiles: [ProfileSummary] {
        let sorted = profiles
            .filter { $0.ownedByViewer && $0.profileId != primaryProfileId }
            .sorted { $0.profileName.localizedCaseInsensitiveCompare($1.profileName) == .orderedAscending }

        guard let primary = primaryProfile else { return sorted }
        return [primary] + sorted
    }

    var followedProfiles: [ProfileSummary] {
        profiles.filter { !$0.ownedByViewer && $0.profileId != primaryProfileId }
    }

    /// True when the list has nothing to show and nothing on its way: what a
    /// load cancelled by the system leaves behind, and what a request that
    /// failed off the network leaves behind. The screen reloads from here when
    /// the app comes back to the foreground, so neither waits on the reader to
    /// notice and tap Try again.
    var needsReload: Bool {
        guard loadTask == nil else { return false }
        switch state {
        case .idle, .loading, .failed:
            return true
        case .loaded, .signedOut:
            return false
        }
    }

    /// Reloads the list.
    ///
    /// The request runs in a task of the model's own, not in the caller's: the
    /// screen starts this from `.task`, which SwiftUI cancels the moment a
    /// full-screen cover goes up over the home screen. Cancelling that also
    /// cancelled the request under it, and the list came back reading "Could
    /// not load profiles — cancelled". An unstructured task does not inherit
    /// that cancellation, so the load finishes either way.
    func load(showSpinner: Bool = true) async {
        loadTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(showSpinner: showSpinner)
        }
        loadTask = task
        await task.value
        if loadTask == task { loadTask = nil }
    }

    private func performLoad(showSpinner: Bool) async {
        guard AuthStore.shared.isSignedIn else {
            profiles = []
            state = .signedOut
            return
        }

        if showSpinner, profiles.isEmpty { state = .loading }

        do {
            let response = try await api.fetchProfiles()
            profiles = response.profiles
            primaryProfileId = response.primaryProfileId
            state = .loaded
        } catch let error as APIError {
            if error.isUnauthorized || error == .notSignedIn {
                state = .signedOut
            } else if error.isCancellation {
                // A newer load owns the screen, or the app went away
                // mid-request. Left alone, so `needsReload` picks it up.
                NSLog("[Profiles] load cancelled")
            } else {
                NSLog("[Profiles] load failed: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            }
        } catch {
            guard !error.isCancellation else {
                NSLog("[Profiles] load cancelled")
                return
            }
            NSLog("[Profiles] load failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    func setPrimary(_ profile: ProfileSummary) async {
        let previous = primaryProfileId
        primaryProfileId = profile.profileId
        do {
            try await api.setPrimaryProfile(id: profile.profileId)
        } catch {
            NSLog("[Profiles] setPrimary failed: \(error.localizedDescription)")
            primaryProfileId = previous
            guard !error.isCancellation else { return }
            state = .failed(error.localizedDescription)
        }
    }

    /// Every profile already on the list, own or followed. The search screen
    /// asks this before it offers a profile to subscribe to: the search route
    /// drops the caller's own profiles but happily returns ones they already
    /// follow.
    var savedProfileIds: Set<String> {
        Set(profiles.map(\.profileId))
    }

    /// Follows a profile found in search, then reloads so the pager gains its
    /// page. No optimistic insert: a search result carries no reading of its
    /// own worth showing, and the list is the one place that knows the order.
    ///
    /// A failure is reported back rather than pushed into `state`: this is
    /// called from a sheet, and turning the whole pager behind it into an
    /// error screen over one refused subscription is out of proportion.
    func follow(_ profile: ProfileSummary) async -> Error? {
        do {
            try await api.followProfile(id: profile.profileId)
            await load(showSpinner: false)
            return nil
        } catch {
            NSLog("[Profiles] follow failed: \(error.localizedDescription)")
            return error
        }
    }

    func unfollow(_ profile: ProfileSummary) async {
        let snapshot = profiles
        profiles.removeAll { $0.profileId == profile.profileId }
        do {
            try await api.unfollowProfile(id: profile.profileId)
        } catch {
            NSLog("[Profiles] unfollow failed: \(error.localizedDescription)")
            profiles = snapshot
            guard !error.isCancellation else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

extension APIError: Equatable {
    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.notSignedIn, .notSignedIn):
            return true
        case let (.http(l, _), .http(r, _)):
            return l == r
        default:
            return false
        }
    }
}
