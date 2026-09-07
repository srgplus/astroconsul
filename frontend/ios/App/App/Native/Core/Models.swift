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
}

struct ProfilesResponse: Codable {
    let profiles: [ProfileSummary]
    let primaryProfileId: String?
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

    /// "Saturn square Moon" — the headline form used across the app.
    var title: String { "\(transitObject) \(aspect) \(natalObject)" }
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
        guard !isToday else { return "Today" }
        guard let day else { return date }
        return Self.weekdayFormatter.string(from: day)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
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

    /// "Saturn square Moon" — the headline form used across the app.
    var title: String { "\(transitObject) \(aspect) \(natalObject)" }

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
enum TimeWindow {
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

struct TimeHeadlines {
    let morning: String
    let afternoon: String
    let evening: String
    let night: String

    subscript(window: TimeWindow) -> String {
        switch window {
        case .morning: return morning
        case .afternoon: return afternoon
        case .evening: return evening
        case .night: return night
        }
    }
}

extension FeelsLike {

    /// The short line under the feels-like label: "Drift into peace" for a
    /// flowing night, "Bold moves time" for a dynamic afternoon.
    ///
    /// The English half of `data/feels_like_time_modifiers.json`, which the
    /// web app reads directly. It is inlined rather than bundled because the
    /// native screens are English only and 48 short strings do not warrant a
    /// resource and a decode path — but that file stays the source of truth,
    /// so edits there belong here too.
    static func headline(for label: String?, at date: Date, in zone: TimeZone) -> String? {
        guard let label, let headlines = headlines[label] else { return nil }
        return headlines[TimeWindow(date: date, in: zone)]
    }

    private static let headlines: [String: TimeHeadlines] = [
        "Calm": TimeHeadlines(
            morning: "Gentle start ahead",
            afternoon: "Calm and steady",
            evening: "Peaceful wind-down",
            night: "Deep stillness"
        ),
        "Subtle pressure": TimeHeadlines(
            morning: "Something stirring beneath",
            afternoon: "Haze of tension",
            evening: "Undercurrent surfaces",
            night: "Restless quiet"
        ),
        "Grinding": TimeHeadlines(
            morning: "Heavy start, pace yourself",
            afternoon: "Endurance mode",
            evening: "Release the weight",
            night: "Let the body recover"
        ),
        "Flowing": TimeHeadlines(
            morning: "Promising start",
            afternoon: "In the flow",
            evening: "Savor the harmony",
            night: "Drift into peace"
        ),
        "Dynamic": TimeHeadlines(
            morning: "Active day building",
            afternoon: "Bold moves time",
            evening: "Process the buzz",
            night: "Mind still racing"
        ),
        "Pressured": TimeHeadlines(
            morning: "Brace for demands",
            afternoon: "Adapt to pressure",
            evening: "Decompress gently",
            night: "Release and restore"
        ),
        "Expansive": TimeHeadlines(
            morning: "Big energy awakening",
            afternoon: "Doors are opening",
            evening: "Celebrate the expansion",
            night: "Dream big tonight"
        ),
        "Charged": TimeHeadlines(
            morning: "Storm energy building",
            afternoon: "Ready to discharge",
            evening: "Let the charge settle",
            night: "Electric dreams ahead"
        ),
        "Intense": TimeHeadlines(
            morning: "Fiery day ahead",
            afternoon: "Fire and pressure",
            evening: "Cool the flames",
            night: "Let the fire die down"
        ),
        "Powerful": TimeHeadlines(
            morning: "Rare launch window",
            afternoon: "Breakthrough energy",
            evening: "Ride the momentum",
            night: "Power in stillness"
        ),
        "Volatile": TimeHeadlines(
            morning: "Expect the unexpected",
            afternoon: "Unpredictable shifts",
            evening: "Ground after the storm",
            night: "Turbulent dreams possible"
        ),
        "Explosive": TimeHeadlines(
            morning: "Maximum intensity day",
            afternoon: "Everything at once",
            evening: "Survive and reflect",
            night: "Deep recovery needed"
        ),
    ]
}
