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
        followingCount: 8
    )

    static let profiles: [ProfileSummary] = [
        profile,
        make(name: "Alex Mosendz", handle: "alexmosendz", place: "Khmelnytskyi, Ukraine", tii: 11, feels: "Subtle pressure"),
        make(name: "Asmik", handle: "asmik", place: "Yerevan, Armenia", tii: 27, feels: "Flowing"),
        make(name: "Britney Spears", handle: "britneyspears", place: "McComb, Mississippi", tii: 42, feels: "Dynamic"),
        make(name: "Kevin Van Vliet", handle: "kevinvanvliet", place: "Rotterdam, Netherlands", tii: 65, feels: "Expansive"),
        make(name: "Kim Kardashian", handle: "kimkardashian", place: "Los Angeles, California", tii: 73, feels: "Charged"),
        make(name: "Liliia Mosendz", handle: "liliiamosendz", place: "Kyiv, Ukraine", tii: 88, feels: "Explosive"),
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
            place: "Somewhere \(number)",
            tii: reading.0,
            feels: reading.1
        )
    }

    static let days: [ForecastDay] = {
        let readings: [(Double, String)] = [
            (51, "Flowing"), (44, "Dynamic"), (38, "Subtle pressure"), (62, "Expansive"),
            (74, "Charged"), (69, "Pressured"), (48, "Dynamic"), (33, "Calm"),
            (27, "Calm"), (58, "Flowing"),
        ]
        let start = Date()

        return readings.enumerated().map { index, reading in
            ForecastDay(
                date: isoDay(start.addingTimeInterval(Double(index) * 86_400)),
                tii: reading.0,
                tensionRatio: 0.4,
                feelsLike: reading.1,
                retrogradeCount: index < 3 ? 3 : 2,
                retrogradePlanets: ["Mercury", "Saturn", "Neptune"],
                velocityDelta: index == 0 ? nil : 4.2,
                velocityDirection: index == 0 ? nil : "rising",
                topTransits: transits,
                moonPhase: MoonPhase(
                    phaseName: "Waxing Gibbous",
                    illuminationPct: 78,
                    moonSign: "Aquarius",
                    moonDegree: 14,
                    phaseEmoji: "🌔"
                )
            )
        }
    }()

    /// Shifts the sample readings so day one matches the profile's own TII —
    /// swiping the harness then walks through every sky colour.
    static func days(for profile: ProfileSummary) -> [ForecastDay] {
        guard let tii = profile.latestTransit?.tii, let first = days.first else { return days }
        let delta = tii - first.tii

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
                moonPhase: day.moonPhase
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

    private static func make(
        name: String,
        handle: String,
        place: String,
        tii: Double,
        feels: String
    ) -> ProfileSummary {
        ProfileSummary(
            profileId: "preview-\(handle)",
            profileName: name,
            username: handle,
            locationName: place,
            localBirthDatetime: nil,
            latestTransit: LatestTransit(
                transitDate: nil,
                transitTime: nil,
                timezone: nil,
                locationName: place,
                latitude: nil,
                longitude: nil,
                updatedAt: nil,
                tii: tii,
                tensionRatio: nil,
                feelsLike: feels
            ),
            isOwn: true,
            isFollowing: false,
            followersCount: nil,
            followingCount: nil
        )
    }

    private static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

#endif
