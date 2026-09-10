import Foundation

// Mirrors frontend/src/types.ts. The decoder uses
// `.convertFromSnakeCase`, so `profile_id` maps to `profileId` here.

struct LatestTransit: Codable, Hashable {
    let transitDate: String?
    let transitTime: String?
    let timezone: String?
    let locationName: String?
    let latitude: Double?
    let longitude: Double?
    let updatedAt: String?
    let tii: Double?
    let tensionRatio: Double?
    let feelsLike: String?
}

/// When and where a reading is cast for.
///
/// The screen reads "now, where the profile says it lives" until someone picks
/// something else; this is that something else. It carries the instant rather
/// than a date and a time string because everything on the screen — the stamp,
/// the moon, the forecast window — has to agree on one moment.
struct TransitMoment: Equatable {
    var instant: Date
    var zone: TimeZone
    var locationName: String?
    var latitude: Double?
    var longitude: Double?

    /// True when this is today in its own zone, so the screen can tell a
    /// reading for another day from a reading for another place.
    var isToday: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.isDateInToday(instant)
    }
}

struct ProfileSummary: Codable, Hashable, Identifiable {
    let profileId: String
    let profileName: String
    let username: String
    /// Where the person was *born*. Not what the weather screens label the
    /// reading with — see `currentLocationName`.
    let locationName: String?
    let localBirthDatetime: String?
    let latestTransit: LatestTransit?
    let isOwn: Bool?
    let isFollowing: Bool?
    let followersCount: Int?
    let followingCount: Int?
    /// Sun, Moon and Ascendant as formatted strings. The list endpoint leaves
    /// it out; search and discovery send it, and the preview sheet is the only
    /// screen that shows a profile's chart before you follow it.
    let natalSummary: NatalSummary?

    var id: String { profileId }

    /// `true` for the user's own profiles, `false` for followed ones.
    /// The backend omits the flag on some payloads; treat missing as own.
    var ownedByViewer: Bool { isOwn ?? true }

    /// Where the person is *now*: the transit location the last reading ran
    /// with — the one typed by hand on the web app — falling back to the city
    /// of that reading's timezone. Birth location is deliberately not in the
    /// chain; telling the two apart is the point.
    var currentLocationName: String? {
        if let name = latestTransit?.locationName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        guard let timezone = latestTransit?.timezone else { return nil }
        return Self.city(inTimezone: timezone)
    }

    /// "Europe/Minsk" → "Minsk", "America/Argentina/Buenos_Aires" → "Buenos Aires".
    /// A bare zone such as "UTC" names no city, so it yields nothing.
    private static func city(inTimezone identifier: String) -> String? {
        let parts = identifier.split(separator: "/")
        guard parts.count > 1, let city = parts.last else { return nil }
        return city.replacingOccurrences(of: "_", with: " ")
    }

    /// Name, handle, birthplace and current location all match, so typing a
    /// city finds a profile whichever of the two a card happens to show. The
    /// saved list and the search sheet filter through the same test, so the
    /// two never disagree about what "matches" means.
    func matches(_ term: String) -> Bool {
        let needle = term.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }

        return [profileName, username, locationName ?? "", currentLocationName ?? ""]
            .contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    /// The birth moment split for display, taken from the local birth
    /// datetime rather than a `Date`: converting to one and back drags the
    /// device's calendar and time zone into it and can land a day away from
    /// the birth certificate.
    var birthMoment: (date: String, time: String)? {
        guard let raw = localBirthDatetime, raw.count >= 16 else { return nil }
        let parts = raw.split(separator: "T", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let ymd = parts[0].split(separator: "-")
        guard ymd.count == 3 else { return nil }

        return ("\(ymd[2]).\(ymd[1]).\(ymd[0])", String(parts[1].prefix(5)))
    }
}

/// The Big 3 as the chart builder formats them, e.g. "Aries 27°04'12\"".
struct NatalSummary: Codable, Hashable {
    let sun: String?
    let moon: String?
    let asc: String?
}

struct ProfilesResponse: Codable {
    let profiles: [ProfileSummary]
    let primaryProfileId: String?
}

/// `GET /api/v1/profiles/search`. The rows are profile summaries with the
/// birth fields attached, so they decode into `ProfileSummary` like any other
/// — but with no `is_own`/`is_following`, which is why the search screen works
/// out what is already followed from the saved list instead of trusting these.
struct ProfileSearchResponse: Codable {
    let results: [ProfileSummary]
}

/// `GET /api/v1/public/featured` — what the search screen offers before the
/// first keystroke.
struct FeaturedProfilesResponse: Codable {
    let profiles: [ProfileSummary]
}

// MARK: - TII zones

/// Tension Intensity Index bands. Mirrors frontend/src/tii-zones.ts so the
/// native list shows the same colours and labels as the web app.
enum TiiZone: String {
    case quiet, active, hot, extreme

    init(tii: Double) {
        switch tii {
        case ..<25: self = .quiet
        case ..<55: self = .active
        case ..<80: self = .hot
        default: self = .extreme
        }
    }
}

/// The twelve feels-like states the transit engine reports, and the footage
/// each one plays.
///
/// The gradient underneath stays per-zone — four colours the eye can learn —
/// but the clip is this granular, so two readings that share a zone no longer
/// share a sky. Raw values are the clip names in `Design/Sky`.
enum SkyState: String, Equatable {
    case calm
    case subtlePressure = "subtle_pressure"
    case grinding
    case flowing
    case dynamic
    case pressured
    case expansive
    case charged
    case intense
    case powerful
    case volatile
    case explosive

    /// The engine sends the label as prose, not as a code.
    init?(label: String?) {
        switch label {
        case "Calm": self = .calm
        case "Subtle pressure": self = .subtlePressure
        case "Grinding": self = .grinding
        case "Flowing": self = .flowing
        case "Dynamic": self = .dynamic
        case "Pressured": self = .pressured
        case "Expansive": self = .expansive
        case "Charged": self = .charged
        case "Intense": self = .intense
        case "Powerful": self = .powerful
        case "Volatile": self = .volatile
        case "Explosive": self = .explosive
        default: return nil
        }
    }

    /// A reading can carry a TII before its label lands, or a label this build
    /// does not know. Fall back to the calmest state of the zone: its footage
    /// is the one that matches the gradient already on screen.
    init(label: String?, zone: TiiZone) {
        if let known = SkyState(label: label) {
            self = known
        } else {
            switch zone {
            case .quiet: self = .calm
            case .active: self = .flowing
            case .hot: self = .expansive
            case .extreme: self = .powerful
            }
        }
    }

    /// The zone this state sits in, so a caller that needs the colour does not
    /// have to carry the TII alongside the state.
    var zone: TiiZone {
        switch self {
        case .calm, .subtlePressure, .grinding: return .quiet
        case .flowing, .dynamic, .pressured: return .active
        case .expansive, .charged, .intense: return .hot
        case .powerful, .volatile, .explosive: return .extreme
        }
    }
}

enum FeelsLike {
    /// Emoji for each feels-like label produced by the transit engine.
    static let emoji: [String: String] = [
        "Calm": "☁️",
        "Subtle pressure": "🌫️",
        "Grinding": "⛏",
        "Flowing": "☀️",
        "Dynamic": "⚡",
        "Pressured": "🪨",
        "Expansive": "🌅",
        "Charged": "⛈️",
        "Intense": "🔥",
        "Powerful": "🚀",
        "Volatile": "⚔️",
        "Explosive": "💥",
    ]

    static func emoji(for label: String?) -> String? {
        guard let label else { return nil }
        return emoji[label]
    }

    /// SF Symbol per label. The forecast list uses these instead of the emoji
    /// so the icon column matches Weather's, rendered multicolour.
    static func symbol(for label: String?) -> String {
        switch label {
        case "Calm": return "cloud.fill"
        case "Subtle pressure": return "cloud.fog.fill"
        case "Grinding": return "cloud.drizzle.fill"
        case "Flowing": return "sun.max.fill"
        case "Dynamic": return "cloud.sun.bolt.fill"
        case "Pressured": return "cloud.heavyrain.fill"
        case "Expansive": return "sun.horizon.fill"
        case "Charged": return "cloud.bolt.fill"
        case "Intense": return "flame.fill"
        case "Powerful": return "wind"
        case "Volatile": return "tornado"
        case "Explosive": return "cloud.bolt.rain.fill"
        default: return "sparkles"
        }
    }
}

// MARK: - Forecast

/// One transit-to-natal aspect from the forecast payload. Extra keys the API
/// sends (`exact_angle`, `delta`, `keywords`, `_tii_contribution`) are ignored.
struct TopTransit: Codable, Hashable, Identifiable {
    let transitObject: String
    let natalObject: String
    let aspect: String
    let orb: Double?
    let strength: String?
    let meaning: String?
    let action: String?

    var id: String { "\(transitObject)-\(aspect)-\(natalObject)" }

    /// "Saturn square Moon", in the app's language.
    var title: String {
        Astro.aspectTitle(transit: transitObject, aspect: aspect, natal: natalObject)
    }
}

struct MoonPhase: Codable, Hashable {
    let phaseName: String
    let illuminationPct: Double?
    let moonSign: String?
    let moonDegree: Int?
    let phaseEmoji: String?
    /// Sun–Moon elongation: 0° new, 90° first quarter, 180° full, 270° third.
    /// The engine sends it, and the drawn disc and both countdowns follow from
    /// it alone.
    let phaseAngle: Double?

    /// The mean synodic month — new moon to new moon.
    static let synodicMonth: Double = 29.530588853

    /// The elongation to draw with. A response from before the engine sent one
    /// still carries illumination and a name, and those two together say the
    /// same thing: illumination gives the angle up to a reflection, and the
    /// name says which side of full it falls on.
    var angle: Double {
        if let phaseAngle { return phaseAngle.truncatingRemainder(dividingBy: 360) }

        let lit = min(max((illuminationPct ?? 0) / 100, 0), 1)
        let waxingAngle = acos(1 - 2 * lit) * 180 / .pi
        return isWaning ? 360 - waxingAngle : waxingAngle
    }

    var isWaning: Bool {
        if let phaseAngle { return phaseAngle.truncatingRemainder(dividingBy: 360) >= 180 }
        let name = phaseName.lowercased()
        return name.contains("waning") || name.contains("third") || name.contains("last")
    }

    /// Days from now until the elongation next reaches `target`.
    private func days(toAngle target: Double) -> Double {
        let remaining = (target - angle).truncatingRemainder(dividingBy: 360)
        return (remaining < 0 ? remaining + 360 : remaining) / 360 * Self.synodicMonth
    }

    var daysToFullMoon: Double { days(toAngle: 180) }
    var daysToNewMoon: Double { days(toAngle: 360) }

    /// How far into the cycle the Moon is, in days since the new moon.
    var age: Double { angle / 360 * Self.synodicMonth }
}

struct ForecastDay: Codable, Hashable, Identifiable {
    let date: String
    let tii: Double
    let tensionRatio: Double?
    let feelsLike: String
    let retrogradeCount: Int?
    let retrogradePlanets: [String]?
    let velocityDelta: Double?
    let velocityDirection: String?
    let topTransits: [TopTransit]?
    let moonPhase: MoonPhase?

    var id: String { date }

    var zone: TiiZone { TiiZone(tii: tii) }

    /// The forecast sends plain `YYYY-MM-DD` in the profile's timezone.
    var day: Date? { Self.dayFormatter.date(from: date) }

    /// "Today" for the first day, otherwise a short weekday name.
    func label(isToday: Bool) -> String {
        guard !isToday else { return L("common.today") }
        guard let day else { return date }
        return LocalizedDate.string(day, template: "EEE")
    }

    /// "Tuesday, 9 September" — the long form, for a screen about this day
    /// alone rather than a row in a list of ten.
    func longLabel(isToday: Bool) -> String {
        guard let day else { return date }
        let name = LocalizedDate.string(day, template: "EEEEdMMMM")
        return isToday ? L("forecast.todayLong", name) : name
    }

    /// This day as a moment to read: its date at `time`'s hour and minute, in
    /// `zone`. The forecast sends a bare date, so the clock comes from the
    /// reading the screen is already on — the same thing the settings sheet
    /// produces when someone moves only the date wheel.
    func instant(at time: Date, in zone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        // Parsed off the string rather than off `day`, which is midnight in
        // the *device's* zone and so lands on the wrong date either side of
        // the dateline.
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }

        let clock = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            from: DateComponents(
                year: parts[0],
                month: parts[1],
                day: parts[2],
                hour: clock.hour,
                minute: clock.minute
            )
        )
    }

    /// Today, spelled the way the forecast spells its days. A window the
    /// reader moved starts on the day they chose, so which row is "Today" is a
    /// date comparison rather than the first row — and the zone is the one the
    /// reading is cast in, so today means today *there*.
    static func todayKey(in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct ForecastResponse: Codable {
    let days: [ForecastDay]
}

// MARK: - Active transits

/// One moment the aspect is exact. Retrograde transits perfect up to three
/// times, which is why this is a list rather than a single date.
struct ExactPass: Codable, Hashable {
    let utc: String
    let orb: Double?
}

/// When an aspect opens, peaks and closes. The report only carries this when
/// asked for with `include_timing`.
struct AspectTiming: Codable, Hashable {
    let startUtc: String?
    let peakUtc: String?
    let exactUtc: String?
    let endUtc: String?
    let peakOrb: Double?
    let status: String?
    let willPerfect: Bool?
    let durationHours: Double?
    let exactPasses: [ExactPass]?

    /// `exact_utc` is only set under 0.01°, which almost never happens; the
    /// peak is the closest approach and is always there.
    var peak: Date? { Self.date(peakUtc) ?? Self.date(exactUtc) }
    var start: Date? { Self.date(startUtc) }
    var end: Date? { Self.date(endUtc) }

    var passes: [Date] {
        guard let exactPasses, exactPasses.count > 1 else {
            return peak.map { [$0] } ?? []
        }
        return exactPasses.compactMap { Self.date($0.utc) }
    }

    /// The engine writes `datetime.isoformat()` with `+00:00` swapped for `Z`,
    /// so seconds are always there and fractional seconds sometimes are.
    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return fractional.date(from: iso) ?? plain.date(from: iso)
    }

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

/// A transit-to-natal aspect that is inside orb right now. The report also
/// sends `meaning`, `action`, `insight` and `keywords`; nothing reads them
/// yet, so they are left undecoded.
struct ActiveAspect: Codable, Hashable, Identifiable {
    let transitObject: String
    let natalObject: String
    let aspect: String
    let orb: Double
    let strength: String
    let timing: AspectTiming?

    /// Only the tightest aspect per pair survives the engine, so the pair and
    /// the aspect name identify a row.
    var id: String { "\(transitObject)-\(aspect)-\(natalObject)" }

    /// "Saturn square Moon" — the headline form used across the app, in
    /// whichever language the app is being read in. The API answers in
    /// English for all three parts and every one of them is shown, so the
    /// server's words are ids here and the reading is looked up.
    var title: String {
        Astro.aspectTitle(transit: transitObject, aspect: aspect, natal: natalObject)
    }

    /// Exact and strong are what the web app calls "most impact".
    var isImpactful: Bool { strength == "exact" || strength == "strong" }
}

/// Where a body sits, in the chart the report was cast for. One type covers
/// the transiting bodies, the natal ones and the angles: the payloads differ
/// only in which of the optional fields they carry.
struct ChartPosition: Codable, Hashable {
    let id: String
    /// Ecliptic longitude, 0..<360. The only field the wheel draws from; the
    /// sign and degree below are the same number already split up for text.
    let longitude: Double?
    let degree: Int?
    let minute: Int?
    let sign: String?
    let retrograde: Bool?
    /// Natal house the transiting body falls in; the natal payload calls the
    /// same idea `house`.
    let natalHouse: Int?
    let house: Int?

    /// Longitude to draw at. Older payloads and hand-written previews carry
    /// only the sign and the degree inside it, which is the same position to
    /// within the arcsecond the API drops.
    var wheelLongitude: Double? {
        if let longitude { return longitude }
        guard let sign, let index = Zodiac.index(ofSign: sign) else { return nil }
        return Double(index) * 30 + Double(degree ?? 0) + Double(minute ?? 0) / 60
    }

    /// 14°19′ — the form the web chart prints.
    var formattedDegree: String? {
        guard let degree else { return nil }
        return "\(degree)°\(String(format: "%02d", minute ?? 0))′"
    }

    /// Whichever house the payload names, transit or natal.
    var houseNumber: Int? {
        let number = natalHouse ?? house
        return (number ?? 0) > 0 ? number : nil
    }
}

/// One natal-to-natal aspect. The pair is unordered: the engine emits each
/// combination once, in the order the bodies happen to be listed.
struct NatalAspect: Codable, Hashable, Identifiable {
    let p1: String
    let p2: String
    let aspect: String
    let orb: Double

    var id: String { "\(p1)-\(aspect)-\(p2)" }

    /// "Sun opposition Saturn", in the language the app is read in — the same
    /// three-part reading `ActiveAspect.title` builds.
    var title: String {
        Astro.aspectTitle(transit: p1, aspect: aspect, natal: p2)
    }

    /// A birth chart never changes, so the backend bands transits by strength
    /// but sends natal aspects with the orb alone. The bands are the web's
    /// `aspectStrength` in `ProfileDetail.tsx`; both screens have to call the
    /// same 2.9° aspect strong.
    var strength: String {
        if orb < 1 { return "exact" }
        if orb < 3 { return "strong" }
        if orb < 5 { return "moderate" }
        return "wide"
    }

    /// Exact and strong — what the "most impact" switch narrows a list to.
    var isImpactful: Bool { strength == "exact" || strength == "strong" }
}

struct TransitReport: Codable {
    let activeAspects: [ActiveAspect]?
    /// The slow half of the same list, picked out and ranked by the backend:
    /// outer planets on the personal points and the angles, inside orb for
    /// months. The season behind the reading rather than today's weather.
    let cosmicClimate: [ActiveAspect]?
    let transitPositions: [ChartPosition]?
    let natalPositions: [ChartPosition]?
    let anglePositions: [ChartPosition]?
    /// Natal house cusps 1-12, in ecliptic longitude.
    let houses: [Double]?
    let natalAspects: [NatalAspect]?
}

/// Position lookups for one report, so a row can name where each side of an
/// aspect actually sits. The angles arrive in their own list but read as natal
/// points, so they are folded in with them.
struct TransitPositions: Hashable {
    var transiting: [String: ChartPosition] = [:]
    var natal: [String: ChartPosition] = [:]
    /// Natal house cusps 1-12. Empty until a report has landed.
    var houses: [Double] = []
    /// The natal aspect grid, for the wheel's inner lines.
    var natalAspects: [NatalAspect] = []

    init() {}

    init(report: TransitReport) {
        transiting = Self.index(report.transitPositions)
        natal = Self.index((report.natalPositions ?? []) + (report.anglePositions ?? []))
        houses = report.houses ?? []
        natalAspects = report.natalAspects ?? []
    }

    private static func index(_ positions: [ChartPosition]?) -> [String: ChartPosition] {
        Dictionary(
            (positions ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

// MARK: - Time of day

/// The four windows the feels-like headline is written for. Mirrors
/// `frontend/src/time-modifiers.ts`.
enum TimeWindow: String {
    case morning, afternoon, evening, night

    init(hour: Int) {
        switch hour {
        case 6..<12: self = .morning
        case 12..<18: self = .afternoon
        case 18..<23: self = .evening
        default: self = .night
        }
    }

    init(date: Date, in zone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        self.init(hour: calendar.component(.hour, from: date))
    }
}

// MARK: - Profile detail

/// The birth data a profile's chart was cast from. `GET /profiles/{id}`
/// returns it inside the chart payload, and it is the only place the raw
/// date, time, timezone and coordinates survive — everything else on the
/// profile is derived from them.
struct BirthInput: Codable, Hashable {
    let name: String?
    let birthDate: String?
    let birthTime: String?
    let timezone: String?
    let locationName: String?
    let localBirthDatetime: String?
    let latitude: Double?
    let longitude: Double?
    let timeBasis: String?
}

struct ChartDetail: Codable, Hashable {
    let chartId: String?
    let locationName: String?
    let localBirthDatetime: String?
    let birthInput: BirthInput?
}

struct ProfileDetailResponse: Codable {
    let profile: ProfileSummary
    let chart: ChartDetail?
}

/// One geocoder hit from `/locations/search`. Picking one fills in the
/// coordinates and the timezone, which is why they are never typed by hand.
struct PlaceCandidate: Codable, Hashable, Identifiable {
    let displayName: String
    let latitude: Double
    let longitude: Double
    let timezone: String?

    var id: String { "\(displayName)|\(latitude)|\(longitude)" }
}

/// The single best match for a place typed out in full, from
/// `/locations/resolve`. Unlike search, it either geocodes or fails.
struct ResolvedLocation: Codable, Hashable {
    let locationName: String
    let resolvedName: String
    let latitude: Double
    let longitude: Double
    let timezone: String
}
