import Foundation

#if DEBUG

/// Sample payloads shaped like the API's, so the weather screens can be laid
/// out in Xcode previews and checked on a simulator without an account.
/// Launch the app with `-uiPreviewWeather` to open straight into them.
enum WeatherPreviewData {

    static let profile = ProfileSummary(
        profileId: "preview-profile",
        profileName: "Alena Brama",
        username: "alenabrama",
        // Born in one city, living in another, so the harness shows at a
        // glance that the screens label the reading with the current
        // location and never with the birthplace.
        locationName: "Brest, Belarus",
        localBirthDatetime: "1990-04-17T09:20:00",
        latestTransit: LatestTransit(
            transitDate: "2026-09-06",
            transitTime: "12:00:00",
            timezone: "Europe/Warsaw",
            locationName: "Warsaw, Poland",
            latitude: 52.23,
            longitude: 21.01,
            updatedAt: nil,
            tii: 51,
            tensionRatio: 0.42,
            feelsLike: "Flowing"
        ),
        // The API reports the owner's own primary profile with `is_own: false`,
        // which used to drop it into "Following" and bury it at the bottom of
        // the list. The sample data reproduces that, so the harness shows the
        // primary pinned to the top the way an account does.
        isOwn: false,
        isFollowing: false,
        followersCount: 12,
        followingCount: 8,
        natalSummary: NatalSummary(sun: "Aries 27°04'12\"", moon: "Leo 03°41'55\"", asc: "Cancer 18°22'07\"")
    )

    /// Everyone here was born in one city and lives in another. The two used
    /// to be the same string, which made the harness useless for the question
    /// it exists to answer — a card showing the birthplace and a card showing
    /// the current location looked identical.
    static let profiles: [ProfileSummary] = [
        profile,
        make(name: "Alex Mosendz", handle: "alexmosendz", bornIn: "Khmelnytskyi, Ukraine", livesIn: "Berlin, Germany", tii: 11, feels: "Subtle pressure"),
        make(name: "Asmik", handle: "asmik", bornIn: "Yerevan, Armenia", livesIn: "Lisbon, Portugal", tii: 27, feels: "Flowing"),
        make(name: "Britney Spears", handle: "britneyspears", bornIn: "McComb, Mississippi", livesIn: "Los Angeles, California", tii: 42, feels: "Dynamic"),
        make(name: "Kevin Van Vliet", handle: "kevinvanvliet", bornIn: "Rotterdam, Netherlands", livesIn: "Amsterdam, Netherlands", tii: 65, feels: "Expansive"),
        make(name: "Kim Kardashian", handle: "kimkardashian", bornIn: "Los Angeles, California", livesIn: "Calabasas, California", tii: 73, feels: "Charged"),
        make(name: "Liliia Mosendz", handle: "liliiamosendz", bornIn: "Kyiv, Ukraine", livesIn: "Vienna, Austria", tii: 88, feels: "Explosive"),
    ] + filler

    /// Real accounts follow dozens of profiles; the bar has to survive that.
    private static let filler: [ProfileSummary] = (1...26).map { number in
        let readings: [(Double, String)] = [
            (18, "Calm"), (36, "Flowing"), (57, "Dynamic"), (71, "Charged"), (91, "Volatile"),
        ]
        let reading = readings[number % readings.count]
        return make(
            name: "Profile \(number)",
            handle: "profile\(number)",
            bornIn: "Born \(number)",
            // Every fourth has no reading location on file, so the harness also
            // shows what a profile that never set one falls back to.
            livesIn: number % 4 == 0 ? nil : "Living \(number)",
            tii: reading.0,
            feels: reading.1
        )
    }

    static let days: [ForecastDay] = {
        // The third number is the day's tension. It moves day to day the way
        // the engine's does — the sample used to hold 0.4 ten times over,
        // which drew the forecast's tension column as one number repeated and
        // so proved nothing about it. One day is left without a ratio, since
        // the column has to be looked at empty too.
        let readings: [(Double, String, Double?)] = [
            (51, "Flowing", 0.40), (44, "Dynamic", 0.12), (38, "Subtle pressure", 0.55),
            (62, "Expansive", 0.19), (74, "Charged", 0.86), (69, "Pressured", 0.71),
            (48, "Dynamic", 0.33), (33, "Calm", 0.08), (27, "Calm", nil),
            (58, "Flowing", 1.0),
        ]
        let start = Date()

        return readings.enumerated().map { index, reading in
            ForecastDay(
                date: isoDay(start.addingTimeInterval(Double(index) * 86_400)),
                tii: reading.0,
                tensionRatio: reading.2,
                feelsLike: reading.1,
                retrogradeCount: index < 3 ? 3 : 2,
                retrogradePlanets: ["Mercury", "Saturn", "Neptune"],
                velocityDelta: index == 0 ? nil : 4.2,
                velocityDirection: index == 0 ? nil : "rising",
                topTransits: transits,
                // A real cycle rather than the same phase ten times: the Moon
                // moves about 12° of elongation and 13° of zodiac a day.
                moonPhase: moonPhase(angle: 124.1 + Double(index) * 12.2, degree: 14 + index * 13)
            )
        }
    }()

    /// A moon phase spelled out from one elongation, the way the engine does
    /// it, so the sample illumination and name never disagree with the disc.
    static func moonPhase(angle: Double, degree: Int) -> MoonPhase {
        let elongation = angle.truncatingRemainder(dividingBy: 360)
        let names: [(Double, String, String)] = [
            (3, "New Moon", "🌑"), (87, "Waxing Crescent", "🌒"),
            (93, "First Quarter", "🌓"), (177, "Waxing Gibbous", "🌔"),
            (183, "Full Moon", "🌕"), (267, "Waning Gibbous", "🌖"),
            (273, "Third Quarter", "🌗"), (357, "Waning Crescent", "🌘"),
            (360, "New Moon", "🌑"),
        ]
        let phase = names.first { elongation < $0.0 } ?? names[0]
        let signs = [
            "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
            "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces",
        ]

        return MoonPhase(
            phaseName: phase.1,
            illuminationPct: ((1 - cos(elongation * .pi / 180)) / 2 * 100).rounded(),
            moonSign: signs[(degree / 30) % 12],
            moonDegree: degree % 30,
            phaseEmoji: phase.2,
            phaseAngle: elongation
        )
    }

    /// Shifts the sample readings so day one matches the profile's own TII —
    /// swiping the harness then walks through every sky colour. The Moon is
    /// stepped along with it, an eighth of a cycle per profile, so the swipe
    /// also walks the moon card through every phase it has to draw.
    static func days(for profile: ProfileSummary) -> [ForecastDay] {
        guard let tii = profile.latestTransit?.tii, let first = days.first else { return days }
        let delta = tii - first.tii
        let position = profiles.firstIndex { $0.profileId == profile.profileId } ?? 0

        return days.enumerated().map { index, day in
            ForecastDay(
                date: day.date,
                tii: min(max(day.tii + delta, 4), 96),
                tensionRatio: day.tensionRatio,
                feelsLike: index == 0 ? (profile.latestTransit?.feelsLike ?? day.feelsLike) : day.feelsLike,
                retrogradeCount: day.retrogradeCount,
                retrogradePlanets: day.retrogradePlanets,
                velocityDelta: day.velocityDelta,
                velocityDirection: day.velocityDirection,
                topTransits: day.topTransits,
                moonPhase: moonPhase(
                    angle: 124.1 + Double(index) * 12.2 + Double(position) * 45,
                    degree: 14 + index * 13 + position * 27
                )
            )
        }
    }

    private static let transits: [TopTransit] = [
        TopTransit(
            transitObject: "Saturn",
            natalObject: "Moon",
            aspect: "square",
            orb: 1.2,
            strength: "strong",
            meaning: "Emotional weight settles in — commitments feel heavier than usual, and the day rewards patience over speed.",
            action: "Handle one hard thing early."
        ),
        TopTransit(
            transitObject: "Jupiter",
            natalObject: "Venus",
            aspect: "trine",
            orb: 2.4,
            strength: "moderate",
            meaning: nil,
            action: nil
        ),
        TopTransit(
            transitObject: "Mars",
            natalObject: "Mercury",
            aspect: "sextile",
            orb: 3.8,
            strength: "mild",
            meaning: nil,
            action: nil
        ),
    ]

    /// Aspects inside orb, with the windows the timing engine returns. The
    /// spans are written relative to today so the now-dot lands somewhere
    /// different on each bar.
    /// Every row here is a real aspect between the positions below, named and
    /// measured to the arcminute.
    ///
    /// It was not always: these started as plausible-looking rows, because the
    /// card that showed them only ever printed two glyphs and an orb. Then the
    /// wheel started drawing them, and a "trine" between two bodies 30° apart
    /// is a line that looks like a bug in the renderer. Any row added here has
    /// to survive being drawn.
    static let aspects: [ActiveAspect] = [
        aspect("Sun", "trine", "Neptune", orb: 0.50, strength: "strong", opened: -1.5, closes: 1.5, peaks: 0.4),
        aspect("Moon", "square", "Mars", orb: 0.52, strength: "exact", opened: -0.3, closes: 0.4, peaks: 0.05),
        aspect("Mars", "opposition", "Sun", orb: 5.93, strength: "wide", opened: -4, closes: 5, peaks: 0.6),
        aspect("Saturn", "square", "Moon", orb: 1.23, strength: "moderate", opened: -12, closes: 16, peaks: 3),
        aspect("Uranus", "conjunction", "ASC", orb: 0.18, strength: "exact", opened: -21, closes: 24, peaks: -2),
        aspect("Neptune", "square", "Saturn", orb: 0.25, strength: "exact", opened: -30, closes: 34, peaks: 1),
        aspect("Neptune", "sextile", "ASC", orb: 1.53, strength: "moderate", opened: -130, closes: 160, peaks: -20),
        aspect("Neptune", "square", "Moon", orb: 1.92, strength: "moderate", opened: -150, closes: 210, peaks: 40),
        aspect("Pluto", "trine", "ASC", orb: 0.07, strength: "exact", opened: -44, closes: 47, peaks: 0.8),
        aspect("Lilith", "square", "MC", orb: 1.28, strength: "exact", opened: -9, closes: 8, peaks: -0.5),
        aspect("Chiron", "sextile", "Moon", orb: 3.25, strength: "moderate", opened: -16, closes: 19, peaks: 6),
        aspect("Venus", "square", "Pluto", orb: 1.93, strength: "moderate", opened: -2, closes: 2, peaks: 0.2),
    ]

    /// The climate rows, filtered out of the list above the way the backend
    /// filters them: an outer planet on a personal point or an angle, inside
    /// orb for at least 45 days, ranked by window over orb. Derived rather
    /// than written out a second time, so an aspect cannot carry one window on
    /// the transits card and a different one here.
    static let climate: [ActiveAspect] = {
        let slow: Set<String> = ["Pluto", "Neptune", "Uranus", "Jupiter"]
        let points: Set<String> = ["Sun", "Moon", "Venus", "Mars", "ASC", "MC"]

        func weight(_ aspect: ActiveAspect) -> Double {
            days(aspect) / max(aspect.orb, 0.01)
        }

        func days(_ aspect: ActiveAspect) -> Double {
            (aspect.timing?.durationHours ?? 0) / 24
        }

        return aspects
            .filter { slow.contains($0.transitObject) && points.contains($0.natalObject) }
            .filter { days($0) >= 45 }
            .sorted { weight($0) > weight($1) }
    }()

    /// Transiting bodies drawn with an ℞ on their rows.
    static let retrograde: Set<String> = ["Neptune", "Saturn", "Pluto"]

    /// The positions behind those aspects, enough for the detail sheet.
    static let positions: TransitPositions = {
        var lookup = TransitPositions()
        lookup.transiting = index([
            position("Sun", 14, 19, "Virgo", house: 5),
            position("Moon", 2, 41, "Sagittarius", house: 8),
            position("Mars", 21, 8, "Libra", house: 6),
            position("Saturn", 27, 3, "Pisces", house: 11, retrograde: true),
            position("Uranus", 1, 55, "Gemini", house: 2),
            position("Neptune", 0, 12, "Aries", house: 12, retrograde: true),
            position("Pluto", 1, 40, "Aquarius", house: 10, retrograde: true),
            position("Lilith", 9, 26, "Scorpio", house: 7),
            position("Chiron", 25, 2, "Aries", house: 12),
            position("Venus", 18, 44, "Leo", house: 4),
        ])
        lookup.natal = index([
            position("Neptune", 14, 49, "Capricorn", house: 9, retrograde: true),
            position("Mars", 3, 12, "Pisces", house: 11),
            position("Pluto", 20, 40, "Scorpio", house: 7),
            position("Moon", 28, 17, "Gemini", house: 2),
            position("Sun", 27, 4, "Aries", house: 12),
            position("Saturn", 0, 27, "Capricorn", house: 9),
            position("Venus", 23, 16, "Taurus", house: 1),
            position("Chiron", 12, 30, "Leo", house: 4),
            position("Lilith", 5, 48, "Libra", house: 5),
            position("North Node", 9, 2, "Capricorn", house: 8),
            // Retrograde at birth, so the natal card shows its ℞ column too.
            position("Mercury", 11, 2, "Taurus", house: 1, retrograde: true),
            position("ASC", 1, 44, "Gemini"),
            position("MC", 8, 9, "Aquarius"),
            // The rest of the wheel, so the natal card's drawer has both of
            // its bands to draw rather than half of one.
            position("Jupiter", 4, 33, "Cancer", house: 2),
            position("Uranus", 7, 18, "Capricorn", house: 9, retrograde: true),
            position("Selena", 19, 5, "Aquarius", house: 10),
            position("South Node", 9, 2, "Cancer", house: 2),
            position("Part of Fortune", 2, 57, "Cancer", house: 2),
            position("Vertex", 25, 21, "Libra", house: 6),
        ])
        // Placidus cusps for that ascendant: the opposite pairs line up, so
        // the wheel's house ring reads the way a real chart's would.
        // Every one of these is a real aspect between the positions above, to
        // the arcminute — a made-up grid would draw lines the wheel's own
        // geometry contradicts.
        lookup.natalAspects = [
            NatalAspect(p1: "Sun", p2: "Moon", aspect: "sextile", orb: 1.21),
            NatalAspect(p1: "Moon", p2: "Saturn", aspect: "opposition", orb: 2.17),
            NatalAspect(p1: "Venus", p2: "Pluto", aspect: "opposition", orb: 2.60),
            NatalAspect(p1: "Mars", p2: "Saturn", aspect: "sextile", orb: 2.75),
            NatalAspect(p1: "Neptune", p2: "North Node", aspect: "conjunction", orb: 5.79),
            NatalAspect(p1: "Saturn", p2: "North Node", aspect: "conjunction", orb: 8.58),
            NatalAspect(p1: "North Node", p2: "Lilith", aspect: "square", orb: 3.23),
        ]
        lookup.houses = [
            61.73, 84, 106, 128.15, 156, 195,
            241.73, 264, 286, 308.15, 336, 15,
        ]
        return lookup
    }()

    private static func index(_ positions: [ChartPosition]) -> [String: ChartPosition] {
        Dictionary(positions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func position(
        _ id: String,
        _ degree: Int,
        _ minute: Int,
        _ sign: String,
        house: Int? = nil,
        retrograde: Bool = false
    ) -> ChartPosition {
        ChartPosition(
            id: id,
            longitude: Double(Zodiac.index(ofSign: sign) ?? 0) * 30
                + Double(degree) + Double(minute) / 60,
            degree: degree,
            minute: minute,
            sign: sign,
            retrograde: retrograde,
            natalHouse: house,
            house: house
        )
    }

    private static func aspect(
        _ transit: String,
        _ aspect: String,
        _ natal: String,
        orb: Double,
        strength: String,
        opened: Double,
        closes: Double,
        peaks: Double
    ) -> ActiveAspect {
        ActiveAspect(
            transitObject: transit,
            natalObject: natal,
            aspect: aspect,
            orb: orb,
            strength: strength,
            timing: AspectTiming(
                startUtc: isoInstant(days: opened),
                peakUtc: isoInstant(days: peaks),
                exactUtc: nil,
                endUtc: isoInstant(days: closes),
                peakOrb: orb,
                status: peaks < 0 ? "separating" : "applying",
                willPerfect: true,
                durationHours: (closes - opened) * 24,
                exactPasses: nil
            )
        )
    }

    private static func make(
        name: String,
        handle: String,
        bornIn: String,
        livesIn: String?,
        tii: Double,
        feels: String,
        isOwn: Bool = true
    ) -> ProfileSummary {
        ProfileSummary(
            profileId: "preview-\(handle)",
            profileName: name,
            username: handle,
            locationName: bornIn,
            localBirthDatetime: "19\(70 + abs(handle.hashValue) % 30)-0\(1 + abs(handle.hashValue) % 9)-1\(abs(handle.hashValue) % 9)T0\(abs(handle.hashValue) % 9):\(String(format: "%02d", abs(handle.hashValue) % 60)):00",
            latestTransit: LatestTransit(
                transitDate: nil,
                transitTime: nil,
                timezone: nil,
                locationName: livesIn,
                latitude: nil,
                longitude: nil,
                updatedAt: nil,
                tii: tii,
                tensionRatio: nil,
                feelsLike: feels
            ),
            isOwn: isOwn,
            isFollowing: false,
            followersCount: nil,
            followingCount: nil,
            natalSummary: NatalSummary(
                sun: signs[abs(handle.hashValue) % signs.count] + " 14°12'30\"",
                moon: signs[abs(handle.hashValue + 3) % signs.count] + " 02°55'01\"",
                asc: signs[abs(handle.hashValue + 7) % signs.count] + " 21°08'44\""
            )
        )
    }

    private static let signs = [
        "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
        "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces",
    ]

    /// Profiles the harness account has not subscribed to, so the search
    /// screen has something to put in its "new profiles" group.
    static let discoveries: [ProfileSummary] = [
        make(name: "Ada Lovelace", handle: "adalovelace", bornIn: "London, England", livesIn: "London, England", tii: 34, feels: "Flowing", isOwn: false),
        make(name: "Adam Nowak", handle: "adamnowak", bornIn: "Kraków, Poland", livesIn: "Warsaw, Poland", tii: 61, feels: "Expansive", isOwn: false),
        make(name: "Adele", handle: "adele", bornIn: "Tottenham, England", livesIn: "Los Angeles, California", tii: 79, feels: "Charged", isOwn: false),
        make(name: "Adrian Rossi", handle: "adrianrossi", bornIn: "Milan, Italy", livesIn: "Rome, Italy", tii: 22, feels: "Calm", isOwn: false),
        make(name: "Aisha Karim", handle: "aishakarim", bornIn: "Lahore, Pakistan", livesIn: "Dubai, UAE", tii: 47, feels: "Dynamic", isOwn: false),
    ]

    /// A UTC instant this many days from now, spelled the way the timing
    /// engine spells one.
    private static func isoInstant(days: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date().addingTimeInterval(days * 86_400))
    }

    private static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

#endif
