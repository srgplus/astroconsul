import Foundation

/// The partner one weather page is being compared against, and the report for
/// the pair.
///
/// The partner sticks. It is written to `UserDefaults` under the page's own
/// profile id, so the app opens on the pair you last looked at — the same
/// per-profile memory the web keeps in `localStorage`. Only the id is stored
/// and it is resolved against the profiles the account actually has, so a
/// partner unfollowed since simply comes back empty rather than as a row
/// pointing at nothing.
///
/// The report is fetched the moment a partner is picked, not when the sheet is
/// opened: it is one request against two stored charts and it answers fast, so
/// the score is on the card by the time the reader has finished reading the
/// names.
@MainActor
final class CompatibilityViewModel: ObservableObject {

    enum State: Equatable {
        /// Nothing to show: no partner, or a partner whose report has not been
        /// read yet. A cancelled request lands back here, so the card offers
        /// the button again rather than an error nobody caused.
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var partner: ProfileSummary?
    @Published private(set) var report: SynastryReport?

    private let api: APIClient

    /// The in-flight reading, owned by the model rather than by whoever asked
    /// for it: the card starts it from a `.task` that SwiftUI tears down as
    /// soon as the pager page scrolls off, and the request should not go with
    /// it.
    private var loadTask: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
    }

    #if DEBUG
    /// Seeds a loaded pair for previews and the `-uiPreviewWeather` harness,
    /// which has no account to read a report with.
    init(previewPartner: ProfileSummary, previewReport: SynastryReport) {
        self.api = .shared
        self.partner = previewPartner
        self.report = previewReport
        self.state = .loaded
    }

    var isSeeded: Bool { report != nil && partner != nil && loadTask == nil && state == .loaded }
    #endif

    // MARK: - Picking

    /// Puts back the pair this profile was last read with.
    ///
    /// Called from the card's `.task`, so a page that is never scrolled to
    /// asks for nothing. Candidates are the profiles on the account: a saved
    /// id that is no longer among them is dropped, which is what unfollowing
    /// the partner leaves behind.
    func restore(profile: ProfileSummary, among candidates: [ProfileSummary]) async {
        guard partner == nil, state == .idle else { return }
        guard let savedId = Self.savedPartnerId(for: profile.profileId),
              let saved = candidates.first(where: { $0.profileId == savedId })
        else { return }

        await select(saved, for: profile)
    }

    func select(_ chosen: ProfileSummary, for profile: ProfileSummary) async {
        partner = chosen
        report = nil
        Self.savePartnerId(chosen.profileId, for: profile.profileId)
        await load(profile: profile)
    }

    func clear(for profile: ProfileSummary) {
        loadTask?.cancel()
        loadTask = nil
        partner = nil
        report = nil
        state = .idle
        Self.savePartnerId(nil, for: profile.profileId)
    }

    // MARK: - Reading

    func load(profile: ProfileSummary) async {
        guard partner != nil else { return }
        loadTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(profile: profile)
        }
        loadTask = task
        await task.value
        if loadTask == task { loadTask = nil }
    }

    private func performLoad(profile: ProfileSummary) async {
        guard let partner else { return }

        if report == nil { state = .loading }

        #if DEBUG
        // The `-uiPreviewWeather` harness runs without an account, so there is
        // no pair it could actually read. It serves the sample report instead,
        // after the beat a real request would take, so the card can be looked
        // at in all three of its states without signing in.
        if WeatherPreviewHarness.isEnabled {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            report = WeatherPreviewData.synastry
            state = .loaded
            return
        }
        #endif

        do {
            let report = try await api.fetchSynastryReport(
                profileId: profile.profileId,
                partnerId: partner.profileId
            )
            // A second pick while this one was in flight owns the card now,
            // so a report for the partner it replaced is dropped.
            guard self.partner?.profileId == partner.profileId else { return }
            self.report = report
            state = .loaded
        } catch {
            guard !error.isCancellation else {
                NSLog("[Compatibility] load cancelled")
                state = report == nil ? .idle : .loaded
                return
            }
            NSLog("[Compatibility] load failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Stored partner

    /// One key per profile, because the pair belongs to the page: your own
    /// chart against your partner's, a friend's against theirs.
    private static func key(for profileId: String) -> String {
        "compatibility.partner.\(profileId)"
    }

    private static func savedPartnerId(for profileId: String) -> String? {
        UserDefaults.standard.string(forKey: key(for: profileId))
    }

    private static func savePartnerId(_ partnerId: String?, for profileId: String) {
        let key = key(for: profileId)
        if let partnerId {
            UserDefaults.standard.set(partnerId, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
