import Foundation

/// One named block of the saved list.
///
/// The list screen draws these as its sections and the weather pager flattens
/// them into its pages, so the two can never disagree about what order the
/// cards are in — which they did while each worked it out for itself.
struct ProfileGroup: Identifiable {

    enum Kind: String {
        /// The primary profile and everything the reader starred, at the top.
        case favorites
        /// The reader's own profiles that are not starred.
        case mine
        /// Followed profiles that are not starred.
        case following
    }

    let kind: Kind
    /// The cards in this group, in the order they were dragged into. The
    /// primary profile is not among them even in `.favorites`: it is pinned
    /// above them and takes no part in a drag.
    let profiles: [ProfileSummary]

    var id: String { kind.rawValue }
}

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

    /// The Favourites group, in its own order. Its order lives here rather
    /// than in `profileOrder` so a profile starred today lands directly under
    /// the primary without the rest of the list having to be rewritten.
    @Published private(set) var favoriteProfileIds: [String] = []

    /// The order the Mine and Following cards were dragged into, the two
    /// groups' ids one after the other. Anything absent — never moved, or just
    /// arrived — falls to the end of its group in name order.
    @Published private(set) var profileOrder: [String] = []

    private let api: APIClient

    /// The in-flight load, owned by the model rather than by whoever asked
    /// for it. See `load(showSpinner:)`.
    private var loadTask: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
    }

    #if DEBUG
    /// Seeds a loaded list for previews and the `-uiPreviewWeather` harness.
    init(
        previewProfiles: [ProfileSummary],
        primaryProfileId: String?,
        favoriteProfileIds: [String] = [],
        profileOrder: [String] = []
    ) {
        self.api = .shared
        self.profiles = previewProfiles
        self.primaryProfileId = primaryProfileId
        self.favoriteProfileIds = favoriteProfileIds
        self.profileOrder = profileOrder
        self.state = .loaded
    }
    #endif

    /// The primary profile, whichever section the API thinks it belongs to.
    ///
    /// On the owner's own account the API can report the primary profile with
    /// `is_own: false`, so a plain `ownedByViewer` filter drops it into
    /// "Following" and buries it below every followed profile.
    ///
    /// It heads the Favourites group and is not draggable: the pager keeps it
    /// at page one the way Weather keeps My Location there, so there is no
    /// second place on the list for it to be.
    var primaryProfile: ProfileSummary? {
        guard let primaryProfileId else { return nil }
        return profiles.first { $0.profileId == primaryProfileId }
    }

    /// Own profiles in the reader's order, primary lifted to the top.
    ///
    /// Every profile the account owns, starred or not — what tells an Edit
    /// Profile from an Unfollow whichever group a card is sitting in. The
    /// list screen draws `listGroups` instead.
    ///
    /// Sorting first and lifting afterwards, rather than special-casing the
    /// primary inside the comparator: that comparator claimed `lhs < rhs` even
    /// when both were the primary, which is not a strict weak ordering, and
    /// Swift's sort left the primary mid-list. That in turn put the pager's
    /// location arrow in the middle of the dots.
    var ownProfiles: [ProfileSummary] {
        let sorted = arranged(profiles.filter { $0.ownedByViewer && $0.profileId != primaryProfileId })
        guard let primary = primaryProfile else { return sorted }
        return [primary] + sorted
    }

    var followedProfiles: [ProfileSummary] {
        arranged(profiles.filter { !$0.ownedByViewer && $0.profileId != primaryProfileId })
    }

    /// The ids of every profile this account owns, taken from the model's own
    /// split rather than from each profile's `is_own`: the API has reported an
    /// owner's own primary profile as `is_own: false`, and trusting that would
    /// offer its owner "Unfollow" instead of "Edit Profile".
    /// Read straight off the loaded list rather than through `ownProfiles`:
    /// the list screen asks this per row, and there is no reason to sort every
    /// card into order to answer whether one of them is yours.
    var ownedProfileIds: Set<String> {
        var ids = Set(profiles.filter(\.ownedByViewer).map(\.profileId))
        if let primaryProfile { ids.insert(primaryProfile.profileId) }
        return ids
    }

    // MARK: - Groups

    /// The saved list as the screen draws it: Favourites first, then the
    /// reader's own profiles, then the ones they follow. Empty groups are left
    /// out, so an account with nothing starred and no primary reads exactly as
    /// it did before Favourites existed.
    var listGroups: [ProfileGroup] {
        let starred = Set(favoriteProfileIds)

        func unstarred(own: Bool) -> [ProfileSummary] {
            arranged(profiles.filter {
                $0.ownedByViewer == own
                    && $0.profileId != primaryProfileId
                    && !starred.contains($0.profileId)
            })
        }

        var groups: [ProfileGroup] = []

        let favorites = favoriteProfiles
        if primaryProfile != nil || !favorites.isEmpty {
            groups.append(ProfileGroup(kind: .favorites, profiles: favorites))
        }

        let mine = unstarred(own: true)
        if !mine.isEmpty { groups.append(ProfileGroup(kind: .mine, profiles: mine)) }

        let following = unstarred(own: false)
        if !following.isEmpty { groups.append(ProfileGroup(kind: .following, profiles: following)) }

        return groups
    }

    /// The starred profiles in their own order, primary excluded — it is
    /// pinned above them. Resolved against the loaded list, so an id left
    /// over from a profile since deleted simply drops out.
    var favoriteProfiles: [ProfileSummary] {
        favoriteProfileIds.compactMap { id in
            guard id != primaryProfileId else { return nil }
            return profiles.first { $0.profileId == id }
        }
    }

    /// Every profile in the order the list shows them, the pager's pages. The
    /// primary is page one, then Favourites, then Mine, then Following.
    var orderedProfiles: [ProfileSummary] {
        var ordered: [ProfileSummary] = []
        if let primaryProfile { ordered.append(primaryProfile) }
        ordered.append(contentsOf: listGroups.flatMap(\.profiles))
        return ordered
    }

    func isFavorite(_ profile: ProfileSummary) -> Bool {
        profile.profileId == primaryProfileId || favoriteProfileIds.contains(profile.profileId)
    }

    /// Whether this profile's star can be taken off. The primary is in
    /// Favourites because it is the primary, so there is nothing to unstar.
    func canToggleFavorite(_ profile: ProfileSummary) -> Bool {
        profile.profileId != primaryProfileId
    }

    /// The manual order as a lookup. Built with a uniquing rule rather than
    /// `uniqueKeysWithValues`, which traps: the route dedupes what it stores,
    /// and a crash here would be a poor way to find out it ever stopped.
    private var orderIndex: [String: Int] {
        Dictionary(profileOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The given profiles in the reader's order. Anything they have never
    /// dragged has no place in that order and goes after everything that
    /// does, by name — so a profile added today lands at the end of its group
    /// instead of somewhere in the middle of an order it was never part of.
    private func arranged(_ profiles: [ProfileSummary]) -> [ProfileSummary] {
        let index = orderIndex
        return profiles.sorted { lhs, rhs in
            switch (index[lhs.profileId], index[rhs.profileId]) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.profileName.localizedCaseInsensitiveCompare(rhs.profileName) == .orderedAscending
            }
        }
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
            if !arrangementIsUnsaved {
                favoriteProfileIds = response.favoriteProfileIds ?? []
                profileOrder = response.profileOrder ?? []
            }
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

    // MARK: - Arrangement

    /// Stars a profile into Favourites, or takes it back out.
    ///
    /// A new star goes to the head of the group, directly under the primary:
    /// the reader has just said this one matters, and it is the one place they
    /// can be sure to find it. Unstarring drops it back into Mine or
    /// Following, at the end of whichever it belongs to.
    func toggleFavorite(_ profile: ProfileSummary) {
        guard canToggleFavorite(profile) else { return }
        let id = profile.profileId

        if favoriteProfileIds.contains(id) {
            favoriteProfileIds.removeAll { $0 == id }
        } else {
            favoriteProfileIds.removeAll { $0 == id }
            favoriteProfileIds.insert(id, at: 0)
        }

        // The card is leaving one group for another, so the order it held in
        // the old one means nothing now.
        profileOrder.removeAll { $0 == id }
        saveArrangement()
    }

    /// Applies a drag inside one group.
    ///
    /// Only the dragged group is rewritten and the others are copied through
    /// as they read, so a move can never reshuffle a group the finger never
    /// touched.
    func move(in kind: ProfileGroup.Kind, from source: IndexSet, to destination: Int) {
        let groups = listGroups
        guard var moved = groups.first(where: { $0.kind == kind })?.profiles else { return }
        moved.move(fromOffsets: source, toOffset: destination)

        switch kind {
        case .favorites:
            // Favourites keep their own order, and the primary is not in it.
            favoriteProfileIds = moved.map(\.profileId)
        case .mine, .following:
            profileOrder = groups
                .filter { $0.kind == .mine || $0.kind == .following }
                .flatMap { $0.kind == kind ? moved : $0.profiles }
                .map(\.profileId)
        }

        saveArrangement()
    }

    /// Set the moment the reader rearranges the list, cleared once the server
    /// has taken it. A load that lands in between keeps what is on screen
    /// rather than replacing it with the copy the server answered from —
    /// which is the one the reader has just changed.
    private var arrangementIsUnsaved = false

    /// The write in flight, replaced rather than queued: a drag lands as a run
    /// of moves and only where the card came to rest is worth sending.
    private var saveTask: Task<Void, Never>?

    private func saveArrangement() {
        arrangementIsUnsaved = true
        let favorites = favoriteProfileIds
        let order = profileOrder

        saveTask?.cancel()
        saveTask = Task { [weak self] in
            // Long enough to swallow the moves of one drag, short enough that
            // closing the screen straight afterwards still catches it.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.api.setProfileArrangement(
                    favoriteProfileIds: favorites,
                    profileOrder: order
                )
                // Only if nothing has been dragged since: a later change owns
                // the flag, and its own save will clear it.
                if favorites == self.favoriteProfileIds, order == self.profileOrder {
                    self.arrangementIsUnsaved = false
                }
            } catch {
                // Left on screen rather than snapped back, and the unsaved
                // flag left standing so a reload does not overwrite it either:
                // undoing a drag under the finger over one refused request is
                // worse than a list the server has yet to hear about. The next
                // rearrangement sends the whole arrangement again; if none
                // comes, the server's copy wins at the next launch.
                NSLog("[Profiles] arrangement save failed: \(error.localizedDescription)")
            }
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
        let starred = favoriteProfileIds
        let order = profileOrder
        profiles.removeAll { $0.profileId == profile.profileId }
        // The star goes with the card. Left behind it would come back the
        // moment the profile were followed again, having never been starred.
        favoriteProfileIds.removeAll { $0 == profile.profileId }
        profileOrder.removeAll { $0 == profile.profileId }
        do {
            try await api.unfollowProfile(id: profile.profileId)
            saveArrangement()
        } catch {
            NSLog("[Profiles] unfollow failed: \(error.localizedDescription)")
            profiles = snapshot
            favoriteProfileIds = starred
            profileOrder = order
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
