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

    private let api: APIClient

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
        Task { @MainActor [weak self] in
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
    func load(profile: ProfileSummary, showSpinner: Bool = true) async {
        async let forecast: Void = loadForecast(profileId: profile.profileId, showSpinner: showSpinner)
        async let transits: Void = loadTransits(profile: profile)
        _ = await (forecast, transits)
    }

    func loadForecast(profileId: String, showSpinner: Bool = true) async {
        if showSpinner, days.isEmpty { state = .loading }

        do {
            let response = try await api.fetchForecast(profileId: profileId)
            days = response.days
            state = .loaded
        } catch let error as APIError {
            NSLog("[Weather] forecast failed for \(profileId): \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        } catch {
            NSLog("[Weather] forecast failed for \(profileId): \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    func loadTransits(profile: ProfileSummary) async {
        if activeAspects.isEmpty { transitsState = .loading }

        let moment = Self.moment(for: profile)
        let transit = profile.latestTransit
        readingTime = moment.instant
        readingZone = moment.zone

        do {
            let report = try await api.fetchTransitReport(
                profileId: profile.profileId,
                date: moment.date,
                time: moment.time,
                timezone: moment.timezone,
                locationName: transit?.locationName,
                latitude: transit?.latitude,
                longitude: transit?.longitude
            )
            apply(report)
        } catch {
            NSLog("[Weather] transit report failed for \(profile.profileId): \(error.localizedDescription)")

            // The profile's saved transit settings can be stale — a renamed
            // place, a timezone the backend no longer resolves. The web app
            // retries on the plain device timezone; so does this.
            guard moment.usedSavedSettings else {
                transitsState = .failed(Self.message(for: error))
                return
            }

            let fallback = Self.moment(for: profile, ignoringSavedSettings: true)
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
        ignoringSavedSettings: Bool = false
    ) -> (date: String, time: String, timezone: String, instant: Date, zone: TimeZone, usedSavedSettings: Bool) {
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
