import Foundation

/// The remote half of the search screen: profiles the viewer has not saved
/// yet. The saved half is filtered locally out of `ProfileListViewModel`,
/// which already holds it, so this model never touches it.
@MainActor
final class ProfileSearchViewModel: ObservableObject {

    enum State: Equatable {
        /// Nothing typed yet — the screen is showing suggestions.
        case suggestions
        case searching
        case results
        case failed(String)
    }

    @Published private(set) var state: State = .suggestions
    /// Remote matches for the current query, or the featured profiles when
    /// nothing is typed.
    @Published private(set) var discoveries: [ProfileSummary] = []
    /// Profiles subscribed to during this visit. The saved list reloads after
    /// each follow, but a row that is mid-request would otherwise offer its
    /// plus button a second time.
    @Published private(set) var followed: Set<String> = []
    @Published private(set) var following: Set<String> = []
    /// A refused subscription. Kept apart from `state` so a failed follow
    /// leaves the results on screen instead of replacing them with a message.
    @Published var followError: String?

    private let api: APIClient
    private var featured: [ProfileSummary] = []
    private var loadedFeatured = false
    /// Seeded previews search their own sample rows: the harness runs without
    /// an account, so a real request would only ever answer 401.
    private var isPreview = false

    init(api: APIClient = .shared) {
        self.api = api
    }

    #if DEBUG
    /// Seeds results for previews and the `-uiPreviewWeather` harness, which
    /// runs without a signed-in account to search with.
    init(previewDiscoveries: [ProfileSummary]) {
        self.api = .shared
        self.featured = previewDiscoveries
        self.loadedFeatured = true
        self.discoveries = previewDiscoveries
        self.isPreview = true
    }
    #endif

    /// Suggestions for an empty search field. Featured profiles are curated
    /// server-side and there may be none, which is an empty screen rather than
    /// an error.
    func loadSuggestions() async {
        guard !loadedFeatured else { return }
        loadedFeatured = true

        do {
            featured = try await api.fetchFeaturedProfiles()
        } catch {
            // Suggestions are a nicety. A failure here leaves the screen
            // saying "search for a profile", which is the honest state.
            NSLog("[Search] featured failed: \(error.localizedDescription)")
            featured = []
        }

        if case .suggestions = state {
            discoveries = featured
        }
    }

    /// Runs one search. The caller debounces by re-issuing this from a
    /// `.task(id:)`, so a cancelled keystroke never lands on the screen.
    func search(_ text: String) async {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !term.isEmpty else {
            state = .suggestions
            discoveries = featured
            return
        }

        state = .searching

        if isPreview {
            discoveries = featured.filter { $0.matches(term) }
            state = .results
            return
        }

        do {
            let results = try await api.searchProfiles(query: term)
            try Task.checkCancellation()
            discoveries = results
            state = .results
        } catch {
            // A newer keystroke owns the screen now, or the app was put down
            // mid-request; either way, leave it alone.
            guard !error.isCancellation, !Task.isCancelled else { return }
            NSLog("[Search] query \"\(term)\" failed: \(error.localizedDescription)")
            discoveries = []
            state = .failed(error.localizedDescription)
        }
    }

    /// Subscribes, delegating to the list model so the pager and the saved
    /// list gain the profile at the same moment.
    @discardableResult
    func follow(_ profile: ProfileSummary, using list: ProfileListViewModel) async -> Bool {
        guard !following.contains(profile.profileId) else { return false }
        following.insert(profile.profileId)
        defer { following.remove(profile.profileId) }

        if let error = await list.follow(profile) {
            followError = error.isCancellation ? nil : error.localizedDescription
            return false
        }

        followed.insert(profile.profileId)
        return true
    }
}
