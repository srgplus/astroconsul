import Foundation

/// Backs the profile form: loads a profile's birth data, geocodes a new
/// birthplace as it is typed, and writes the whole thing back.
///
/// The chart is cast from the birth data on every save, so the fields here
/// are the same ones the web form posts — nothing partial. The same model
/// backs a new profile, which starts with nothing to load and posts instead
/// of patching.
@MainActor
final class ProfileEditViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// The profile being edited, or `nil` while creating one.
    let profile: ProfileSummary?

    @Published private(set) var state: State = .loading

    // Editable fields.
    @Published var profileName = ""
    @Published var username = ""
    @Published var birthDate = Date()
    @Published var birthTime = Date()
    @Published var locationName = ""

    /// Filled in by picking a place, never typed: a hand-typed timezone or
    /// coordinate pair recasts the chart against a birthplace nobody checked.
    @Published private(set) var timezone = ""
    @Published private(set) var latitude: Double = 0
    @Published private(set) var longitude: Double = 0

    @Published private(set) var suggestions: [PlaceCandidate] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isSaving = false
    @Published private(set) var isDeleting = false
    @Published var errorMessage: String?

    /// Seconds of the stored birth time. The picker only offers hours and
    /// minutes, so a birth minute recorded to the second keeps its seconds
    /// instead of being silently rounded to :00 on the next save.
    private var birthSeconds = 0

    /// The place text the coordinates belong to. Typing past it without
    /// picking a suggestion means the coordinates no longer describe what the
    /// field says, so the save geocodes the typed name first rather than
    /// recasting the chart against the old city.
    private var geocodedLocationName = ""

    private let api: APIClient
    private var searchTask: Task<Void, Never>?

    init(profile: ProfileSummary, api: APIClient = .shared) {
        self.profile = profile
        self.api = api
        self.profileName = profile.profileName
        self.username = profile.username
    }

    /// A new profile. There is nothing to fetch, so the form opens ready
    /// rather than under a spinner.
    init(api: APIClient = .shared) {
        self.profile = nil
        self.api = api
        self.birthDate = Self.blankBirthDate
        self.birthTime = Self.noon(on: Self.blankBirthDate)
        self.state = .ready
    }

    #if DEBUG
    /// Seeds a filled-in sheet for previews and the `-uiPreviewWeather`
    /// harness, which have no session to load one over.
    init(previewProfile profile: ProfileSummary) {
        self.profile = profile
        self.api = .shared
        self.profileName = profile.profileName
        self.username = profile.username
        self.locationName = profile.locationName ?? ""
        self.geocodedLocationName = self.locationName
        self.timezone = "Europe/Minsk"
        self.latitude = 52.09375
        self.longitude = 23.68519
        if let stamp = profile.localBirthDatetime {
            if let date = Self.datePart(stamp).flatMap(Self.parseDate) { self.birthDate = date }
            if let time = Self.timePart(stamp).flatMap({ Self.parseTime($0, on: self.birthDate) }) {
                self.birthTime = time.date
                self.birthSeconds = time.seconds
            }
        }
        self.state = .ready
    }
    #endif

    var isCreating: Bool { profile == nil }

    var canSave: Bool {
        state == .ready
            && !isSaving
            && !isDeleting
            && !profileName.trimmingCharacters(in: .whitespaces).isEmpty
            && !cleanUsername.isEmpty
            && (!isCreating || hasBirthplace)
    }

    /// A new profile has no coordinates to fall back on: saving one without a
    /// birthplace casts its chart off the coast of Africa. Typed is enough —
    /// the save geocodes whatever the field says.
    private var hasBirthplace: Bool {
        !locationName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The birthplace was changed but no suggestion was picked, so the
    /// coordinates below still point at the old city. Saving geocodes it.
    var locationNeedsResolving: Bool {
        let typed = locationName.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return false }
        return typed != geocodedLocationName.trimmingCharacters(in: .whitespaces)
    }

    private var cleanUsername: String {
        username
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "^@+", with: "", options: .regularExpression)
    }

    // MARK: - Load

    func load() async {
        guard let profile else { return }

        state = .loading
        do {
            let detail = try await api.fetchProfileDetail(id: profile.profileId)
            apply(detail)
            state = .ready
        } catch {
            // The sheet closing is what cancels this, so there is no one left
            // to read a message about it.
            guard !error.isCancellation else {
                NSLog("[ProfileEdit] load cancelled")
                return
            }
            NSLog("[ProfileEdit] load failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    private func apply(_ detail: ProfileDetailResponse) {
        let birth = detail.chart?.birthInput

        profileName = detail.profile.profileName
        username = detail.profile.username

        let stamp = detail.chart?.localBirthDatetime ?? detail.profile.localBirthDatetime
        let date = birth?.birthDate ?? stamp.flatMap(Self.datePart)
        let time = birth?.birthTime ?? stamp.flatMap(Self.timePart)

        if let date, let parsed = Self.parseDate(date) { birthDate = parsed }
        if let time, let parsed = Self.parseTime(time, on: birthDate) {
            birthTime = parsed.date
            birthSeconds = parsed.seconds
        }

        timezone = birth?.timezone ?? ""
        latitude = birth?.latitude ?? 0
        longitude = birth?.longitude ?? 0
        locationName = birth?.locationName
            ?? detail.chart?.locationName
            ?? detail.profile.locationName
            ?? ""
        geocodedLocationName = locationName
    }

    // MARK: - Birthplace

    /// Debounced so a typed city is one request per pause, not one per key.
    func searchPlaces() {
        searchTask?.cancel()
        let term = locationName.trimmingCharacters(in: .whitespaces)

        guard term.count >= 2, term != geocodedLocationName else {
            suggestions = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }

            do {
                let results = try await self.api.searchPlaces(query: term)
                guard !Task.isCancelled else { return }
                self.suggestions = results
            } catch {
                NSLog("[ProfileEdit] place search failed: \(error.localizedDescription)")
                self.suggestions = []
            }
            self.isSearching = false
        }
    }

    func pick(_ place: PlaceCandidate) {
        locationName = place.displayName
        geocodedLocationName = place.displayName
        latitude = place.latitude
        longitude = place.longitude
        if let zone = place.timezone, !zone.isEmpty { timezone = zone }
        suggestions = []
        searchTask?.cancel()
        isSearching = false
    }

    // MARK: - Write

    /// The profile as the API stored it, so the sheet knows to close and the
    /// list knows which page to turn to. `nil` when nothing was written.
    func save() async -> ProfileSummary? {
        guard canSave else { return nil }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        // A birthplace typed over without picking a suggestion is geocoded
        // here: saving the new name against the old city's coordinates would
        // recast the chart for a place the profile no longer claims.
        if locationNeedsResolving {
            do {
                let resolved = try await api.resolvePlace(
                    name: locationName.trimmingCharacters(in: .whitespaces)
                )
                latitude = resolved.latitude
                longitude = resolved.longitude
                timezone = resolved.timezone
                geocodedLocationName = locationName.trimmingCharacters(in: .whitespaces)
            } catch {
                NSLog("[ProfileEdit] resolve failed: \(error.localizedDescription)")
                errorMessage = L("edit.resolveFailed", locationName)
                return nil
            }
        }

        let zone = timezone.trimmingCharacters(in: .whitespaces)
        let place = locationName.trimmingCharacters(in: .whitespaces)

        let fields = APIClient.ProfileUpdate(
            profile_name: profileName.trimmingCharacters(in: .whitespaces),
            username: cleanUsername,
            birth_date: Self.dateFormatter.string(from: birthDate),
            birth_time: birthTimeString,
            timezone: zone.isEmpty ? nil : zone,
            location_name: place.isEmpty ? nil : place,
            latitude: latitude,
            longitude: longitude,
            // Without a timezone there is no local time to convert, so the
            // API is left to read the birth time as UT.
            time_basis: zone.isEmpty ? nil : "local"
        )

        do {
            if let profile {
                let detail = try await api.updateProfile(id: profile.profileId, update: fields)
                return detail.profile
            }
            let detail = try await api.createProfile(fields)
            return detail.profile
        } catch {
            NSLog("[ProfileEdit] save failed: \(error.localizedDescription)")
            errorMessage = error.isCancellation ? nil : error.localizedDescription
            return nil
        }
    }

    func delete() async -> Bool {
        guard let profile else { return false }

        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await api.deleteProfile(id: profile.profileId)
            return true
        } catch {
            NSLog("[ProfileEdit] delete failed: \(error.localizedDescription)")
            errorMessage = error.isCancellation ? nil : error.localizedDescription
            return false
        }
    }

    // MARK: - Formatting

    /// "23:58:00" — hours and minutes from the picker, seconds carried over
    /// from what was stored.
    private var birthTimeString: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: birthTime)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, birthSeconds)
    }

    /// Where a new profile's date wheel opens. Not today — a birthday is not
    /// today, and starting at the near end of a hundred-year range means
    /// spinning back through every one of them.
    private static let blankBirthDate: Date = {
        DateComponents(calendar: .current, year: 1990, month: 1, day: 1).date ?? Date()
    }()

    /// Noon, the hour a chart is cast at when the birth time is unknown, so a
    /// new profile starts on the convention rather than on midnight.
    private static func noon(on day: Date) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// "1986-04-17T23:58:00+03:00" → "1986-04-17".
    private static func datePart(_ stamp: String) -> String? {
        let head = stamp.prefix(10)
        return head.count == 10 ? String(head) : nil
    }

    /// "1986-04-17T23:58:00+03:00" → "23:58:00".
    private static func timePart(_ stamp: String) -> String? {
        guard let marker = stamp.firstIndex(of: "T") else { return nil }
        let rest = stamp[stamp.index(after: marker)...]
        return rest.count >= 8 ? String(rest.prefix(8)) : nil
    }

    private static func parseDate(_ value: String) -> Date? {
        dateFormatter.date(from: String(value.prefix(10)))
    }

    /// "23:58" or "23:58:30" onto the birth day, so the picker opens on the
    /// stored minute. A UT-basis profile stores a decimal hour instead; that
    /// is read as hours too.
    private static func parseTime(_ value: String, on day: Date) -> (date: Date, seconds: Int)? {
        var hour = 0
        var minute = 0
        var second = 0

        if value.contains(":") {
            let parts = value.split(separator: ":").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
            hour = parts.first ?? 0
            minute = parts.count > 1 ? parts[1] : 0
            second = parts.count > 2 ? parts[2] : 0
        } else if let decimal = Double(value) {
            let total = Int((decimal * 3600).rounded())
            hour = total / 3600
            minute = (total % 3600) / 60
            second = total % 60
        } else {
            return nil
        }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        components.second = 0
        guard let date = Calendar.current.date(from: components) else { return nil }
        return (date, min(max(second, 0), 59))
    }
}
