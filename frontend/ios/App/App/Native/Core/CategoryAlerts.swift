import BackgroundTasks
import Foundation
import UserNotifications

/// Tells the device the day's cosmic weather — one of the twelve feels-like
/// categories the engine can return, `Calm` … `Explosive` — at the hour the
/// person chose, either every day or only on the days the category turns.
///
/// The cadence is theirs to set and defaults to the turns. A banner that says
/// "holding, same as yesterday" for the ninth morning running is the kind of
/// notification people switch off wholesale, and switching it off takes the
/// rare "tomorrow is Explosive" with it. But a fortnight can hold four turns
/// and none of them this week, which reads as a broken feature to someone who
/// has just set a time — so the choice is put in Settings rather than decided
/// here, and both readings of it are honest.
///
/// These are *local* notifications, not APNs pushes, and that is a deliberate
/// reading of the problem rather than a shortcut. The forecast is deterministic
/// ephemeris: the engine casts one reading per local noon, so every day of the
/// next fortnight is already knowable, and the device can be handed the whole
/// schedule at once. iOS then fires them whether or not the app is running. A
/// push would need an APNs key, a device-token table and a server cron to
/// arrive at the same banner, and would go silent the moment any of the three
/// broke.
///
/// The schedule is rebuilt whenever the home screen comes forward and from a
/// `BGAppRefreshTask`, so it does not run dry for someone who leaves the app
/// closed.
@MainActor
final class CategoryAlerts: ObservableObject {

    static let shared = CategoryAlerts()

    /// Defaults keys, shared with the `@AppStorage` bindings in `SettingsView`.
    enum Key {
        static let enabled = "categoryAlertsEnabled"
        static let hour = "categoryAlertsHour"
        static let minute = "categoryAlertsMinute"
        static let profileId = "categoryAlertsProfileId"
        static let cadence = "categoryAlertsCadence"
        /// The forecast, every day of it, whether or not the category turned.
        ///
        /// A key of its own rather than the `categoryAlertsChanges` the old
        /// build wrote: that one held only the turning days, and a device
        /// upgrading with it on disk would lay a "every day" schedule of four
        /// days. An unreadable key reads as nothing stored, which sends
        /// `reschedule()` to fetch a real forecast — see `legacyDaysKey`.
        static let days = "categoryAlertsDays"
        /// Written by builds up to 1.2 (12). Swept once, never read.
        static let legacyDays = "categoryAlertsChanges"
        static let lastRefresh = "categoryAlertsLastRefresh"
        /// Whether the first-run card has had its answer. Written either way,
        /// so "Not now" is not asked again on the next launch.
        static let offered = "categoryAlertsOffered"
        /// The time of day the queue on file was actually laid at, which is
        /// not always the time now set — see `refresh(profile:force:)`.
        static let scheduledHour = "categoryAlertsScheduledHour"
        static let scheduledMinute = "categoryAlertsScheduledMinute"
        /// The cadence the queue on file was laid for, for the same reason.
        static let scheduledCadence = "categoryAlertsScheduledCadence"
    }

    /// How often a banner is owed. Stored as its raw value so `@AppStorage`
    /// in Settings can bind straight to it.
    enum Cadence: String, CaseIterable, Identifiable {
        /// Only the days whose category differs from the day before.
        case changes
        /// Every day of the window.
        case daily

        var id: String { rawValue }
        var label: String { L("settings.cadence.\(rawValue)") }
    }

    /// The turns, unless someone says otherwise. See the note on the class.
    static let defaultCadence = Cadence.changes

    /// On by default. The alerts are the feature, not an opt-in extra, and the
    /// switch in Settings is there to turn them *off* — an account that never
    /// opens Settings still hears what its weather is doing.
    static let defaultEnabled = true

    /// Local noon. The engine casts one reading per local noon, so that is the
    /// hour the notification is actually describing. It also competes with an
    /// app that rebuilds its schedule whenever it comes forward, and an early
    /// hour is the one most likely to be overtaken by someone opening the app
    /// before it fires.
    static let defaultHour = 12
    static let defaultMinute = 0

    static let backgroundTaskIdentifier = "me.big3.app.category-alerts"

    /// Every request this class queues carries this prefix, so a rebuild can
    /// clear its own work without touching anything else the app schedules.
    private static let identifierPrefix = "category-change."

    /// How far ahead the schedule reaches. The endpoint allows 30 days, but
    /// each one is a separate ephemeris pass on the server, and a fortnight is
    /// longer than anyone goes between opening the app and still wanting to
    /// hear from it.
    static let horizonDays = 14

    /// iOS keeps at most 64 pending local notifications per app and silently
    /// drops the rest. A fortnight of daily alerts is fifteen at most, so the
    /// cap is belt-and-braces against a horizon someone widens later.
    private static let maximumScheduled = 32

    /// The forecast costs the server a full pass per day, and the home screen
    /// calls this on every foreground. Anything sooner than this is skipped
    /// unless the caller forces it.
    private static let minimumRefreshInterval: TimeInterval = 6 * 3600

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// How many alerts are currently queued. Settings prints it, and it is the
    /// only honest confirmation that the feature is actually armed.
    @Published private(set) var scheduledCount = 0

    /// When the first of them fires.
    ///
    /// A count on its own is what made the feature look broken: eight changes
    /// spread over a fortnight can mean nothing at all for the next six days,
    /// and there was no way to tell that apart from a schedule that had
    /// silently failed to arrive.
    @Published private(set) var nextAlert: Date?

    private let center = UNUserNotificationCenter.current()
    private let api: APIClient
    private let defaults: UserDefaults
    private var inFlight: Task<Void, Never>?

    /// One permission request per app run. `notDetermined` already stops a
    /// second sheet from appearing, but two calls can read that status before
    /// either has written the answer back.
    private var hasRequestedAuthorization = false

    init(api: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        // The registration domain, so someone who has switched the alerts off
        // or moved the time keeps their answer: an explicit choice is written
        // to the standard domain, which wins over anything registered here.
        defaults.register(defaults: [
            Key.enabled: Self.defaultEnabled,
            Key.hour: Self.defaultHour,
            Key.minute: Self.defaultMinute,
            Key.cadence: Self.defaultCadence.rawValue,
        ])
        // The old list, in the old shape, under the old key. Nothing reads it;
        // this is only so it does not sit in defaults for the life of the app.
        defaults.removeObject(forKey: Key.legacyDays)
    }

    // MARK: - Settings

    var isEnabled: Bool { defaults.bool(forKey: Key.enabled) }

    /// Whether a forecast has been read and turned into a list of days.
    /// Settings' test row needs one to build a banner from.
    var hasStoredDays: Bool { !(storedDays() ?? []).isEmpty }

    /// Whether the first-run card should put the question.
    ///
    /// Once only, and only while iOS itself has not been asked: someone who
    /// has already answered the system prompt — in this app or in Settings —
    /// has answered, and a card offering them the choice again is a card that
    /// cannot act on either reply.
    ///
    /// Deliberately not gated on `isEnabled`. The switch is on by default, so
    /// that test would never pass; what decides whether to ask is whether the
    /// *permission* question is still open.
    var shouldOffer: Bool {
        !defaults.bool(forKey: Key.offered)
            && !hasRequestedAuthorization
            && authorization == .notDetermined
    }

    /// Turns the feature on from outside Settings: the permission sheet, then
    /// the switch, then a schedule.
    ///
    /// The switch is set only once permission is granted, so a refused sheet
    /// does not leave Settings showing a toggle with nothing behind it.
    @discardableResult
    func acceptOffer(profile: ProfileSummary? = nil) async -> Bool {
        markOffered()
        guard await requestAuthorization() else { return false }
        defaults.set(true, forKey: Key.enabled)
        await refresh(profile: profile, force: true)
        return true
    }

    /// Records that the question has been put. Idempotent.
    func markOffered() {
        defaults.set(true, forKey: Key.offered)
    }

    /// "Not now" — including a refused system sheet and a card swiped away,
    /// both of which are answers.
    ///
    /// The switch has to come off with it. It is on by default, so leaving it
    /// alone would show Settings a feature switched on with no permission
    /// behind it and nothing scheduled — a toggle that lies. Off is honest,
    /// and switching it back on asks again.
    func declineOffer() {
        markOffered()
        defaults.set(false, forKey: Key.enabled)
    }

    private var hour: Int { defaults.integer(forKey: Key.hour) }
    private var minute: Int { defaults.integer(forKey: Key.minute) }

    /// What the queue is currently laid for. An unreadable value — a build
    /// that wrote something else, a hand-edited plist — is the default.
    var cadence: Cadence {
        defaults.string(forKey: Key.cadence).flatMap(Cadence.init(rawValue:)) ?? Self.defaultCadence
    }

    private var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional
    }

    /// Asks for permission outright. Two callers, and never a launch: the
    /// first-run card, and the toggle in Settings when it goes back on after a
    /// refusal. Both have already said what the alerts are for by the time the
    /// system sheet appears.
    @discardableResult
    func requestAuthorization() async -> Bool {
        hasRequestedAuthorization = true

        var granted = false
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            NSLog("[Alerts] authorisation request failed: \(error.localizedDescription)")
        }
        await syncAuthorization()
        return granted
    }

    func syncAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Reads back what iOS is actually holding. Settings calls this on
    /// appearing: `scheduledCount` is otherwise only written by a rebuild, so
    /// a launch that did not need one would report zero alerts while a
    /// fortnight of them sat in the queue.
    func syncState() async {
        await syncAuthorization()
        await readPending()
    }

    /// Reads the queue back off iOS: how many of ours are in it, and when the
    /// first one fires.
    ///
    /// Only the calendar-triggered ones count. A test banner queued from
    /// Settings carries the same prefix so that `clear()` sweeps it up, and it
    /// has no business being reported as a category change.
    private func readPending() async {
        let ours = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(Self.identifierPrefix) }
            .compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        scheduledCount = ours.count
        nextAlert = ours.compactMap { $0.nextTriggerDate() }.min()
    }

    // MARK: - Scheduling

    /// Rebuilds the schedule from a fresh forecast.
    ///
    /// - Parameters:
    ///   - profile: the profile to read. Passing the one the home screen
    ///     already has saves a round trip; `nil` resolves the primary profile.
    ///   - force: skip the refresh interval. Used when a setting changed or a
    ///     background task ran, where the point is to refresh.
    func refresh(profile: ProfileSummary? = nil, force: Bool = false) async {
        guard isEnabled else {
            await clear()
            return
        }

        await syncAuthorization()
        guard isAuthorized else {
            // Permission can be revoked in iOS Settings long after the toggle
            // went on, which would otherwise leave the switch lying.
            NSLog("[Alerts] not authorised (status \(authorization.rawValue)); nothing scheduled")
            await clear()
            return
        }

        // A queue laid for different settings than the ones now in force.
        // `reschedule()` only runs when the picker is touched, so without this
        // a change to the *default* hour — 8 became 12 — would leave Settings
        // saying noon over a fortnight of eight o'clocks until the next
        // rebuild happened to fall due.
        await readPending()
        if scheduledCount > 0, wasLaidForOtherSettings, let days = storedDays(), !days.isEmpty {
            await apply(days)
        }

        let switchedProfile = profile.map { $0.profileId != defaults.string(forKey: Key.profileId) } ?? false
        guard force || switchedProfile || isDue else { return }

        // The home screen's foreground refresh and a background task can land
        // together; the second one waits for the first rather than racing it.
        if let inFlight {
            await inFlight.value
            return
        }

        let task = Task { await rebuild(profile: profile) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Re-lays the schedule already on file at a new time of day, or for a
    /// new cadence, without asking the server for a forecast it just sent.
    ///
    /// Nothing on file — including the day this build first runs, where the
    /// old build's list is under a key nothing reads — falls through to a real
    /// refresh, so switching to "every day" cannot lay a fortnight of four.
    func reschedule() async {
        guard isEnabled else {
            await clear()
            return
        }

        await syncAuthorization()
        guard isAuthorized else { return }

        guard let days = storedDays(), !days.isEmpty else {
            await refresh(force: true)
            return
        }
        await apply(days)
    }

    /// Drops every pending alert. Called when the toggle goes off and when the
    /// session ends — a signed-out device should not keep announcing the
    /// weather of an account it no longer holds.
    func clear() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        guard !ids.isEmpty else {
            scheduledCount = 0
            nextAlert = nil
            return
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        scheduledCount = 0
        nextAlert = nil
    }

    /// Forgets the account's schedule and the profile it was read for.
    func reset() async {
        await clear()
        defaults.removeObject(forKey: Key.profileId)
        defaults.removeObject(forKey: Key.days)
        defaults.removeObject(forKey: Key.lastRefresh)
        defaults.removeObject(forKey: Key.scheduledHour)
        defaults.removeObject(forKey: Key.scheduledMinute)
        defaults.removeObject(forKey: Key.scheduledCadence)
    }

    // MARK: - Internals

    private var isDue: Bool {
        let last = defaults.double(forKey: Key.lastRefresh)
        guard last > 0 else { return true }
        return Date().timeIntervalSince1970 - last >= Self.minimumRefreshInterval
    }

    /// Whether the pending queue was laid at some other hour, or for some
    /// other cadence, than the one now set. A queue built before these keys
    /// existed reads as 0 and `nil`, neither of which anything was ever
    /// scheduled for, so it counts as stale.
    private var wasLaidForOtherSettings: Bool {
        defaults.integer(forKey: Key.scheduledHour) != hour
            || defaults.integer(forKey: Key.scheduledMinute) != minute
            || defaults.string(forKey: Key.scheduledCadence) != cadence.rawValue
    }

    private func rebuild(profile: ProfileSummary?) async {
        guard let profileId = await resolveProfileId(profile) else { return }

        let zone = TimeZone.current
        let days: [ForecastDay]
        do {
            // Starting yesterday, not today, and one day longer to pay for it.
            //
            // `DailyAlert.list` cannot word the first day of a window — it has
            // nothing to say where the day came from — so a window that
            // started today could never alert for today. That was not merely a
            // missing alert: this rebuild runs on every foreground, and it
            // clears the queue before re-laying it. Opening the app in the
            // morning, before the alert fired, deleted that day's alert and
            // did not put it back. With an 8am default, opening the app at
            // breakfast destroyed the very notification being waited for.
            days = try await api.fetchForecast(
                profileId: profileId,
                timezone: zone.identifier,
                days: Self.horizonDays + 1,
                startDate: Self.isoDay(before: Date(), in: zone)
            ).days
        } catch {
            NSLog("[Alerts] forecast failed for \(profileId): \(error.localizedDescription)")
            return
        }

        let alerts = DailyAlert.list(in: days)
        store(alerts)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastRefresh)
        await apply(alerts)
    }

    private func resolveProfileId(_ profile: ProfileSummary?) async -> String? {
        if let profile {
            defaults.set(profile.profileId, forKey: Key.profileId)
            return profile.profileId
        }
        if let stored = defaults.string(forKey: Key.profileId) {
            return stored
        }
        do {
            let response = try await api.fetchProfiles()
            guard let id = response.primaryProfileId ?? response.profiles.first?.profileId else {
                return nil
            }
            defaults.set(id, forKey: Key.profileId)
            return id
        } catch {
            NSLog("[Alerts] could not resolve a profile: \(error.localizedDescription)")
            return nil
        }
    }

    /// Replaces the queue wholesale. Rebuilding rather than diffing keeps the
    /// pending list a straight function of the latest forecast, so a revised
    /// day can never leave yesterday's alert behind.
    private func apply(_ days: [DailyAlert]) async {
        await clear()

        let now = Date()
        let zone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        // The stored list is every day either way; the cadence decides which
        // of them are owed a banner. Filtering here rather than at the point
        // the forecast is read is what lets the switch in Settings re-lay the
        // queue from what is already on file, with no round trip.
        let owed = cadence == .daily ? days : days.filter(\.changed)

        var scheduled = 0
        for day in owed where scheduled < Self.maximumScheduled {
            guard let components = day.fireComponents(hour: hour, minute: minute, in: zone),
                  let fireDate = calendar.date(from: components),
                  fireDate > now
            else { continue }

            let request = UNNotificationRequest(
                identifier: Self.identifierPrefix + day.date,
                content: Self.content(for: day),
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )

            do {
                try await center.add(request)
                scheduled += 1
            } catch {
                NSLog("[Alerts] could not schedule \(day.date): \(error.localizedDescription)")
            }
        }

        defaults.set(hour, forKey: Key.scheduledHour)
        defaults.set(minute, forKey: Key.scheduledMinute)
        defaults.set(cadence.rawValue, forKey: Key.scheduledCadence)
        await readPending()
        NSLog("[Alerts] scheduled \(scheduled) of \(owed.count) owed, \(cadence.rawValue)")
    }

    /// `YYYY-MM-DD` for the day before the given one, in the zone the forecast
    /// is cast for. Hand-formatted for the same reason `DailyAlert` splits
    /// dates by hand: this is a calendar date, not an instant.
    private static func isoDay(before date: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"

        return formatter.string(from: calendar.date(byAdding: .day, value: -1, to: date) ?? date)
    }

    /// Fires one alert a few seconds out, built by the same code that builds
    /// the scheduled ones, from the next day on file.
    ///
    /// A calendar trigger cannot land sooner than the day it names, so this is
    /// the only way to establish that delivery works on a given device without
    /// waiting for tomorrow. It carries the shared prefix so a toggle switched
    /// off in the meantime takes it with everything else.
    @discardableResult
    func sendTestAlert(after seconds: TimeInterval = 5) async -> Bool {
        await syncAuthorization()
        // The first day the cadence would actually fire for, so the banner
        // under test is the banner that gets sent. On "on changes" the first
        // stored day is usually a day that held, whose wording is the one
        // thing this row is not testing.
        let days = storedDays() ?? []
        guard isAuthorized,
              let day = days.first(where: { cadence == .daily || $0.changed }) ?? days.first
        else { return false }

        let request = UNNotificationRequest(
            identifier: Self.identifierPrefix + "test",
            content: Self.content(for: day),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )

        do {
            try await center.add(request)
            return true
        } catch {
            NSLog("[Alerts] test alert failed: \(error.localizedDescription)")
            return false
        }
    }

    /// The banner itself: the category as the headline, the reading on its own
    /// line, and the gradient card as the attachment — which iOS shows as the
    /// notification's thumbnail beside the words and full width once the
    /// banner is expanded.
    static func content(for day: DailyAlert) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = day.title
        content.subtitle = day.subtitle
        content.body = day.body
        content.sound = .default
        // One thread, so a fortnight of daily banners does not stack up as
        // fourteen separate conversations in Notification Centre.
        content.threadIdentifier = "cosmic-weather"
        content.userInfo = ["date": day.date, "feelsLike": day.to, "tii": day.tii]

        if let artwork = CategoryArtwork.file(for: day) {
            do {
                content.attachments = [
                    try UNNotificationAttachment(
                        identifier: "temperature",
                        url: artwork,
                        options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"]
                    )
                ]
            } catch {
                // The words alone still say what changed, so a card that fails
                // to attach costs the picture and nothing else.
                NSLog("[Alerts] artwork rejected for \(day.date): \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: artwork)
            }
        }

        return content
    }

    private func store(_ days: [DailyAlert]) {
        guard let data = try? JSONEncoder().encode(days) else { return }
        defaults.set(data, forKey: Key.days)
    }

    private func storedDays() -> [DailyAlert]? {
        guard let data = defaults.data(forKey: Key.days) else { return nil }
        return try? JSONDecoder().decode([DailyAlert].self, from: data)
    }
}

// MARK: - Background refresh

extension CategoryAlerts {

    /// Must run before `didFinishLaunchingWithOptions` returns — `BGTaskScheduler`
    /// traps if an identifier in `BGTaskSchedulerPermittedIdentifiers` has no
    /// handler by then.
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            Task { @MainActor in await shared.handle(task) }
        }
    }

    /// Asks for the next background pass. iOS decides when — or whether — it
    /// runs, so this is a top-up for the foreground refresh rather than the
    /// thing the feature stands on.
    func scheduleBackgroundRefresh() {
        guard isEnabled else { return }

        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulators reject this outright, and so does a device with
            // Background App Refresh switched off. Neither is fatal.
            NSLog("[Alerts] background refresh not submitted: \(error.localizedDescription)")
        }
    }

    private func handle(_ task: BGTask) async {
        // Queued first: an early return below would otherwise end the chain,
        // and there is nothing to ask for a next pass afterwards.
        scheduleBackgroundRefresh()

        let work = Task { await refresh(force: true) }
        task.expirationHandler = { work.cancel() }
        await work.value
        task.setTaskCompleted(success: !work.isCancelled)
    }
}

#if DEBUG

// MARK: - Preview harness

extension CategoryAlerts {

    /// Schedules straight from a forecast in hand, skipping the API, and
    /// reports what iOS actually holds afterwards.
    ///
    /// Launch with `-uiPreviewAlerts` to exercise the queue on a simulator
    /// without an account: permission, the calendar triggers and their dates,
    /// and — from `previewDelivery` — one banner that really arrives.
    func scheduleForPreview(days: [ForecastDay]) async {
        await requestAuthorization()
        guard isAuthorized else {
            NSLog("[Alerts] preview: permission refused, nothing to schedule")
            return
        }

        let alerts = DailyAlert.list(in: days)
        store(alerts)
        await apply(alerts)
        await logPending()
    }

    /// Fires one real alert a few seconds out, built by the same code that
    /// builds the scheduled ones. A calendar trigger cannot land sooner than
    /// tomorrow, so this is the only way to see the banner itself.
    func previewDelivery(after seconds: TimeInterval = 15) async {
        if await sendTestAlert(after: seconds) {
            NSLog("[Alerts] preview: a banner in \(Int(seconds))s")
        } else {
            NSLog("[Alerts] preview: nothing to deliver")
        }
    }

    func logPending() async {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm zzz"

        let pending = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("category-change.") }
            .sorted { $0.identifier < $1.identifier }

        NSLog("[Alerts] pending: \(pending.count)")
        for request in pending {
            let fires = (request.trigger as? UNCalendarNotificationTrigger)?
                .nextTriggerDate()
                .map(formatter.string(from:)) ?? "—"
            NSLog("[Alerts]   \(fires) | \(request.content.title) | \(request.content.body)")
        }
    }
}

#endif
