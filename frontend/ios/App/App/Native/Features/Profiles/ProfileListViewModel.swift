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

    func load(showSpinner: Bool = true) async {
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
            } else {
                state = .failed(error.localizedDescription)
            }
        } catch {
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
            state = .failed(error.localizedDescription)
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
