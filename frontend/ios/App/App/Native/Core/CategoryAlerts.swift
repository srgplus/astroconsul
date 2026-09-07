import BackgroundTasks
import Foundation
import UserNotifications

/// Notifies the device when the cosmic weather moves to a different feels-like
/// category — one of the twelve the engine can return, `Calm` … `Explosive`.
///
/// These are *local* notifications, not APNs pushes, and that is a deliberate
/// reading of the problem rather than a shortcut. The forecast is deterministic
/// ephemeris: the engine casts one reading per local noon, so every category
/// change for the next fortnight is already knowable, and the device can be
/// handed the whole schedule at once. iOS then fires them whether or not the
/// app is running. A push would need an APNs key, a device-token table and a
/// server cron to arrive at the same banner, and would go silent the moment any
/// of the three broke.
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
        static let changes = "categoryAlertsChanges"
        static let lastRefresh = "categoryAlertsLastRefresh"
    }

    static let defaultHour = 8
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
    /// drops the rest. A fortnight cannot produce this many, so the cap is
    /// belt-and-braces against a horizon someone widens later.
    private static let maximumScheduled = 32

    /// The forecast costs the server a full pass per day, and the home screen
    /// calls this on every foreground. Anything sooner than this is skipped
    /// unless the caller forces it.
    private static let minimumRefreshInterval: TimeInterval = 6 * 3600

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// How many alerts are currently queued. Settings prints it, and it is the
    /// only honest confirmation that the feature is actually armed.
    @Published private(set) var scheduledCount = 0

    private let center = UNUserNotificationCenter.current()
    private let api: APIClient
    private let defaults: UserDefaults
    private var inFlight: Task<Void, Never>?

    init(api: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        defaults.register(defaults: [
            Key.hour: Self.defaultHour,
            Key.minute: Self.defaultMinute,
        ])
    }

    // MARK: - Settings

    var isEnabled: Bool { defaults.bool(forKey: Key.enabled) }

    private var hour: Int { defaults.integer(forKey: Key.hour) }
    private var minute: Int { defaults.integer(forKey: Key.minute) }

    private var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional
    }

    /// Asks for permission. Called when the toggle goes on, not at launch: the
    /// sheet means something next to the switch that caused it.
    @discardableResult
    func requestAuthorization() async -> Bool {
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
        let pending = await center.pendingNotificationRequests()
        scheduledCount = pending.filter { $0.identifier.hasPrefix(Self.identifierPrefix) }.count
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

    /// Re-lays the schedule already on file at a new time of day, without
    /// asking the server for a forecast it just sent.
    func reschedule() async {
        guard isEnabled else {
            await clear()
            return
        }

        await syncAuthorization()
        guard isAuthorized else { return }

        guard let changes = storedChanges(), !changes.isEmpty else {
            await refresh(force: true)
            return
        }
        await apply(changes)
    }

    /// Drops every pending alert. Called when the toggle goes off and when the
    /// session ends — a signed-out device should not keep announcing the
    /// weather of an account it no longer holds.
    func clear() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        guard !ids.isEmpty else {
            scheduledCount = 0
            return
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        scheduledCount = 0
    }

    /// Forgets the account's schedule and the profile it was read for.
    func reset() async {
        await clear()
        defaults.removeObject(forKey: Key.profileId)
        defaults.removeObject(forKey: Key.changes)
        defaults.removeObject(forKey: Key.lastRefresh)
    }

    // MARK: - Internals

    private var isDue: Bool {
        let last = defaults.double(forKey: Key.lastRefresh)
        guard last > 0 else { return true }
        return Date().timeIntervalSince1970 - last >= Self.minimumRefreshInterval
    }

    private func rebuild(profile: ProfileSummary?) async {
        guard let profileId = await resolveProfileId(profile) else { return }

        let zone = TimeZone.current
        let days: [ForecastDay]
        do {
            days = try await api.fetchForecast(
                profileId: profileId,
                timezone: zone.identifier,
                days: Self.horizonDays
            ).days
        } catch {
            NSLog("[Alerts] forecast failed for \(profileId): \(error.localizedDescription)")
            return
        }

        let changes = CategoryChange.list(in: days)
        store(changes)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastRefresh)
        await apply(changes)
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
    private func apply(_ changes: [CategoryChange]) async {
        await clear()

        let now = Date()
        let zone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        var scheduled = 0
        for change in changes where scheduled < Self.maximumScheduled {
            guard let components = change.fireComponents(hour: hour, minute: minute, in: zone),
                  let fireDate = calendar.date(from: components),
                  fireDate > now
            else { continue }

            let request = UNNotificationRequest(
                identifier: Self.identifierPrefix + change.date,
                content: Self.content(for: change),
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )

            do {
                try await center.add(request)
                scheduled += 1
            } catch {
                NSLog("[Alerts] could not schedule \(change.date): \(error.localizedDescription)")
            }
        }

        scheduledCount = scheduled
        NSLog("[Alerts] scheduled \(scheduled) of \(changes.count) category changes")
    }

    /// The banner itself: the category as the headline, the reading on its own
    /// line, and the gradient card as the attachment — which iOS shows as the
    /// notification's thumbnail beside the words and full width once the
    /// banner is expanded.
    static func content(for change: CategoryChange) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = change.title
        content.subtitle = change.subtitle
        content.body = change.body
        content.sound = .default
        // One thread, so a run of changing days does not stack up as a dozen
        // separate conversations in Notification Centre.
        content.threadIdentifier = "cosmic-weather"
        content.userInfo = ["date": change.date, "feelsLike": change.to, "tii": change.tii]

        if let artwork = CategoryArtwork.file(for: change) {
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
                NSLog("[Alerts] artwork rejected for \(change.date): \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: artwork)
            }
        }

        return content
    }

    private func store(_ changes: [CategoryChange]) {
        guard let data = try? JSONEncoder().encode(changes) else { return }
        defaults.set(data, forKey: Key.changes)
    }

    private func storedChanges() -> [CategoryChange]? {
        guard let data = defaults.data(forKey: Key.changes) else { return nil }
        return try? JSONDecoder().decode([CategoryChange].self, from: data)
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

        let changes = CategoryChange.list(in: days)
        store(changes)
        await apply(changes)
        await logPending()
    }

    /// Fires one real alert a few seconds out, built by the same code that
    /// builds the scheduled ones. A calendar trigger cannot land sooner than
    /// tomorrow, so this is the only way to see the banner itself.
    func previewDelivery(after seconds: TimeInterval = 15) async {
        guard isAuthorized, let change = storedChanges()?.first else { return }

        let request = UNNotificationRequest(
            identifier: "category-change.preview-delivery",
            content: Self.content(for: change),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )

        do {
            try await center.add(request)
            NSLog("[Alerts] preview: \"\(change.title) — \(change.body)\" in \(Int(seconds))s")
        } catch {
            NSLog("[Alerts] preview delivery failed: \(error.localizedDescription)")
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
