import Foundation

@MainActor
final class CosmicWeatherViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var days: [ForecastDay] = []

    /// The transit report is a second, slower request, so it carries its own
    /// state: the forecast draws as soon as it lands rather than waiting.
    @Published private(set) var transitsState: State = .idle
    @Published private(set) var activeAspects: [ActiveAspect] = []
    /// The months-long outer-planet transits, in the order the report ranked
    /// them.
    @Published private(set) var cosmicClimate: [ActiveAspect] = []
    @Published private(set) var retrogradeObjects: Set<String> = []
    @Published private(set) var positions = TransitPositions()

    /// The moment the reading was cast for, and the zone it is read in. The
    /// hero prints these, so they are the request's own values rather than
    /// "now" read a second time.
    @Published private(set) var readingTime = Date()
    @Published private(set) var readingZone = TimeZone.current

    /// What the reader asked for instead of "now, where the profile lives".
    /// Nil is the ordinary case and the one the screen opens in.
    @Published private(set) var chosen: TransitMoment?

    /// A reload of a screen that already has a reading on it — another day,
    /// another place. The cards keep the reading they have until the new one
    /// lands, so without a mark of its own nothing on screen says the app is
    /// working; the hero's spinner rides this.
    @Published private(set) var isRefreshing = false

    /// Choices can overlap — apply a day, then reset to the present before the
    /// first reading is back — and the earlier one finishing must not clear
    /// the spinner the later one is still under.
    private var refreshes = 0

    #if DEBUG
    /// A seeded model has no session to read with, so a chosen moment cannot
    /// be fetched. The harness still has to show what choosing one looks like,
    /// so it holds the refresh for a beat over the reading already on screen.
    private var isSeeded = false
    #endif

    private let api: APIClient

    /// The in-flight reading, owned by the model rather than by whoever asked
    /// for it. See `load(profile:showSpinner:)`.
    private var loadTask: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
    }

    #if DEBUG
    /// Seeds a loaded state for previews and the `-uiPreviewWeather` harness,
    /// so the screens can be checked without an account.
    /// `loadingFor` holds the seeded data behind the loading states for a
    /// moment before revealing it. A seeded model never calls the API — the
    /// view's `.task` returns early for anything but `.idle` — so without this
    /// the harness can never show a spinner, and the loading states go
    /// unchecked until someone signs in on a device.
    init(
        previewDays: [ForecastDay],
        previewAspects: [ActiveAspect] = [],
        previewClimate: [ActiveAspect] = [],
        previewRetrograde: Set<String> = [],
        previewPositions: TransitPositions = .init(),
        loadingFor delay: Duration? = nil
    ) {
        self.api = .shared
        self.isSeeded = true
        self.days = previewDays
        self.activeAspects = previewAspects
        self.cosmicClimate = previewClimate
        self.retrogradeObjects = previewRetrograde
        self.positions = previewPositions

        guard let delay else {
            self.state = .loaded
            self.transitsState = .loaded
            return
        }

        self.state = .loading
        self.transitsState = .loading
        // Held in `loadTask` so the seeded delay reads as a load in flight and
        // no foreground reload fires a real request at the harness.
        self.loadTask = Task { @MainActor [weak self] in
            // The forecast is the fast half in the real app; the report lands
            // a beat later. The harness keeps that order.
            try? await Task.sleep(for: delay)
            self?.state = .loaded
            try? await Task.sleep(for: delay)
            self?.transitsState = .loaded
        }
    }
    #endif

    var today: ForecastDay? { days.first }

    /// High and low across the whole forecast window — the closest honest
    /// analogue to Weather's H/L, since the engine yields one TII per day.
    var high: Double? { days.map(\.tii).max() }
    var low: Double? { days.map(\.tii).min() }

    /// Both halves of the screen at once. They are independent requests, so a
    /// failure in one leaves the other on screen.
    ///
    /// The pair runs in a task of the model's own, not in the caller's. The
    /// page starts this from `.task`, and the pager tears a page's `.task`
    /// down the moment it scrolls off — which cancelled the requests under it
    /// and left "No forecast — cancelled" on the card for whoever swiped back.
    /// An unstructured task does not inherit that cancellation, so a reading
    /// swiped away from finishes and is waiting when the page returns.
    func load(profile: ProfileSummary, showSpinner: Bool = true) async {
        loadTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            async let forecast: Void = self.loadForecast(
                profileId: profile.profileId,
                showSpinner: showSpinner
            )
            async let transits: Void = self.loadTransits(profile: profile)
            _ = await (forecast, transits)
        }
        loadTask = task
        await task.value
        if loadTask == task { loadTask = nil }
    }

    /// True when the page has no full reading to show and none on its way:
    /// what a request cancelled by the system leaves behind, and what one that
    /// failed off the network leaves behind. The page reloads from here when
    /// the app comes back to the foreground, so neither waits on a tap of Try
    /// again.
    var needsReload: Bool {
        guard loadTask == nil else { return false }
        return state != .loaded || transitsState != .loaded
    }

    /// Read the sky for another moment, or pass nil to go back to this one.
    /// Both halves reload: the report is cast for the new instant and the
    /// forecast window starts on its date, so the sky over the cards and the
    /// cards themselves are the same day.
    func choose(_ moment: TransitMoment?, profile: ProfileSummary) async {
        chosen = moment

        refreshes += 1
        isRefreshing = true
        defer {
            refreshes -= 1
            if refreshes == 0 { isRefreshing = false }
        }

        #if DEBUG
        if isSeeded {
            try? await Task.sleep(for: .seconds(2))
            return
        }
        #endif

        await load(profile: profile, showSpinner: false)
    }

    func loadForecast(profileId: String, showSpinner: Bool = true) async {
        if showSpinner, days.isEmpty { state = .loading }

        do {
            let response = try await api.fetchForecast(
                profileId: profileId,
                timezone: chosen?.zone.identifier ?? TimeZone.current.identifier,
                startDate: chosen.flatMap { $0.isToday ? nil : Self.format($0.instant, as: "yyyy-MM-dd", in: $0.zone) }
            )
            days = response.days
            state = .loaded
        } catch {
            // A cancelled request is a page swiped away or an app put down,
            // not a failure. Left alone, so `needsReload` picks it up rather
            // than the reader being shown the word "cancelled".
            guard !error.isCancellation else {
                NSLog("[Weather] forecast cancelled for \(profileId)")
                return
            }
            NSLog("[Weather] forecast failed for \(profileId): \(error.localizedDescription)")
            state = .failed(Self.message(for: error))
        }
    }

    func loadTransits(profile: ProfileSummary) async {
        if activeAspects.isEmpty { transitsState = .loading }

        let moment = Self.moment(for: profile, chosen: chosen)
        let transit = profile.latestTransit
        readingTime = moment.instant
        readingZone = moment.zone

        do {
            let report = try await api.fetchTransitReport(
                profileId: profile.profileId,
                date: moment.date,
                time: moment.time,
                timezone: moment.timezone,
                locationName: chosen?.locationName ?? transit?.locationName,
                latitude: chosen?.latitude ?? transit?.latitude,
                longitude: chosen?.longitude ?? transit?.longitude
            )
            apply(report)
        } catch {
            guard !error.isCancellation else {
                NSLog("[Weather] transit report cancelled for \(profile.profileId)")
                return
            }
            NSLog("[Weather] transit report failed for \(profile.profileId): \(error.localizedDescription)")

            // The profile's saved transit settings can be stale — a renamed
            // place, a timezone the backend no longer resolves. The web app
            // retries on the plain device timezone; so does this.
            guard moment.usedSavedSettings else {
                transitsState = .failed(Self.message(for: error))
                return
            }

            let fallback = Self.moment(for: profile, chosen: chosen, ignoringSavedSettings: true)
            readingTime = fallback.instant
            readingZone = fallback.zone
            do {
                let report = try await api.fetchTransitReport(
                    profileId: profile.profileId,
                    date: fallback.date,
                    time: fallback.time,
                    timezone: fallback.timezone
                )
                apply(report)
            } catch {
                guard !error.isCancellation else {
                    NSLog("[Weather] transit retry cancelled for \(profile.profileId)")
                    return
                }
                NSLog("[Weather] transit retry failed for \(profile.profileId): \(error.localizedDescription)")
                transitsState = .failed(Self.message(for: error))
            }
        }
    }

    private func apply(_ report: TransitReport) {
        activeAspects = (report.activeAspects ?? []).sorted { left, right in
            let leftRank = TransitOrder.rank(left.transitObject)
            let rightRank = TransitOrder.rank(right.transitObject)
            if leftRank != rightRank { return leftRank < rightRank }
            return left.orb < right.orb
        }
        // Already ranked by the engine — longest window, tightest orb first.
        cosmicClimate = report.cosmicClimate ?? []
        retrogradeObjects = Set(
            (report.transitPositions ?? []).filter { $0.retrograde == true }.map(\.id)
        )
        positions = TransitPositions(report: report)
        transitsState = .loaded
    }

    private static func message(for error: Error) -> String {
        (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }

    /// Now, spelled the way the report endpoint wants it: a date and a time in
    /// the profile's own timezone.
    private static func moment(
        for profile: ProfileSummary,
        chosen: TransitMoment? = nil,
        ignoringSavedSettings: Bool = false
    ) -> (date: String, time: String, timezone: String, instant: Date, zone: TimeZone, usedSavedSettings: Bool) {
        // A moment the reader picked is not a guess, so it never falls back:
        // retrying it on the device's zone would answer a question nobody
        // asked. It is spelled out here and used as-is.
        if let chosen {
            return (
                date: format(chosen.instant, as: "yyyy-MM-dd", in: chosen.zone),
                time: format(chosen.instant, as: "HH:mm", in: chosen.zone),
                timezone: chosen.zone.identifier,
                instant: chosen.instant,
                zone: chosen.zone,
                usedSavedSettings: false
            )
        }

        let saved = ignoringSavedSettings ? nil : profile.latestTransit?.timezone
        let zone = saved.flatMap(TimeZone.init(identifier:)) ?? .current
        let now = Date()

        return (
            date: format(now, as: "yyyy-MM-dd", in: zone),
            time: format(now, as: "HH:mm", in: zone),
            timezone: zone.identifier,
            instant: now,
            zone: zone,
            usedSavedSettings: !ignoringSavedSettings
                && (saved != nil
                    || profile.latestTransit?.locationName != nil
                    || profile.latestTransit?.latitude != nil)
        )
    }

    private static func format(_ date: Date, as template: String, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = template
        return formatter.string(from: date)
    }
}
