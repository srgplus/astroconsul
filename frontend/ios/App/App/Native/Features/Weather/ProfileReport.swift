import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// One profile's reading, written out as Markdown for a chat model to reason
/// over.
///
/// It costs no request. Everything here is already on the weather page by the
/// time the ••• menu can be opened: the forecast carries the ten days and the
/// Moon, and the transit report carries the natal positions, the house cusps,
/// the natal aspect grid and every aspect currently inside orb. This type only
/// spells them out.
///
/// Written in the language the app is set to, and through the same `Astro`
/// tables the screens read from — so a reader who asks their model in Russian
/// is handed Russian, and the planet a card calls Сатурн is called Сатурн
/// here too.
///
/// The numbers get a glossary of their own (`glossary`). Intensity and tension
/// are ours, not anyone's convention, and a model handed "51 of 100" with no
/// scale will read it as a temperature or as a score out of ten. The wording
/// there tracks `app/domain/astrology/tii.py`; if the weights or the bands
/// move, it moves.
struct ProfileReport {

    let profile: ProfileSummary
    /// The moment the reading was cast for, place and zone included.
    let moment: TransitMoment
    /// Where the reading was cast from, as the hero labels it.
    let placeName: String?
    let days: [ForecastDay]
    let aspects: [ActiveAspect]
    let climate: [ActiveAspect]
    let positions: TransitPositions
    /// Bodies retrograde at the moment of the reading.
    let retrograde: Set<String>

    private var today: ForecastDay? { days.first }

    /// Neither half has landed, so there is nothing worth putting on the
    /// clipboard. The menu item is disabled on this.
    var isEmpty: Bool { days.isEmpty && positions.natal.isEmpty }

    /// The natal table's rows, in the order `NatalChartCard` draws them: the
    /// big three first, then the rest of the personal chart, the outer planets
    /// and the special points. A body the report did not carry is skipped
    /// rather than printed empty.
    private static let bodies = [
        "Sun", "Moon", "ASC", "MC",
        "Mercury", "Venus", "Mars",
        "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto",
        "Chiron", "Lilith", "Selena",
        "North Node", "South Node", "Part of Fortune", "Vertex",
    ]

    var markdown: String {
        var blocks: [String] = [header]

        // The glossary comes before the numbers rather than after them:
        // whoever reads this top to bottom meets the scale first.
        blocks.append(glossary)
        if let now { blocks.append(now) }
        if let natal { blocks.append(natal) }
        if let houses { blocks.append(houses) }
        if let natalAspects { blocks.append(natalAspects) }
        if let transits { blocks.append(transits) }
        if let background { blocks.append(background) }
        if let forecast { blocks.append(forecast) }

        return blocks.joined(separator: "\n\n") + "\n"
    }

    // MARK: - Blocks

    private var header: String {
        var lines = ["# \(profile.profileName) (@\(profile.username))", "", L("report.prompt")]

        if let birth = profile.birthMoment {
            let place = profile.locationName.map { ", \($0)" } ?? ""
            lines.append("")
            lines.append("**\(L("report.birth")):** \(birth.date), \(birth.time)\(place)")
        }

        let stamp = LocalizedDate.string(moment.instant, template: "d MMM yyyy jmm", in: moment.zone)
        let place = placeName.map { ", \($0)" } ?? ""
        lines.append("**\(L("report.reading")):** \(stamp)\(place) (\(moment.zone.identifier))")

        return lines.joined(separator: "\n")
    }

    private var now: String? {
        let tii = today?.tii ?? profile.latestTransit?.tii
        let tension = today?.tensionRatio ?? profile.latestTransit?.tensionRatio
        let feels = today?.feelsLike ?? profile.latestTransit?.feelsLike
        guard tii != nil || tension != nil || feels != nil else { return nil }

        var lines = ["## \(L("report.now"))"]

        if let tii {
            lines.append("- **\(L("report.intensity")):** \(L("report.of100", Self.number(tii)))")
        }
        if let tension {
            lines.append("- **\(L("report.tension")):** \(Int((tension * 100).rounded()))%")
        }
        if let feels, let reading = Astro.feels(feels) {
            lines.append("- **\(L("report.weather")):** \(reading)")
        }
        if let moon = today?.moonPhase {
            lines.append("- **\(L("report.moon")):** \(Self.describe(moon))")
        }

        // The report's own list where there is one; a day without a report
        // still carries the count and the names from the forecast.
        let retrogrades = retrograde.isEmpty ? Set(today?.retrogradePlanets ?? []) : retrograde
        if !retrogrades.isEmpty {
            let names = retrogrades
                .sorted { TransitOrder.rank($0) < TransitOrder.rank($1) }
                .map(Astro.object)
            lines.append("- **\(L("report.retrograde")):** \(names.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    /// What the two numbers are, so they are reasoned from rather than
    /// guessed at.
    private var glossary: String {
        [
            "## \(L("report.glossary"))",
            "- **\(L("report.intensity")):** \(L("report.glossaryIntensity"))",
            "- **\(L("report.tension")):** \(L("report.glossaryTension"))",
            "- **\(L("report.weather")):** \(L("report.glossaryWeather"))",
        ].joined(separator: "\n")
    }

    private var natal: String? {
        let rows = Self.bodies.compactMap { id -> String? in
            guard let position = positions.natal[id] else { return nil }
            return [
                Astro.object(id),
                Astro.sign(position.sign) ?? "",
                position.formattedDegree ?? "",
                position.houseNumber.map(String.init) ?? "",
                position.retrograde == true ? "℞" : "",
            ].joined(separator: " | ")
        }
        guard !rows.isEmpty else { return nil }

        let head = [
            L("report.colObject"), L("report.colSign"),
            L("report.colDegree"), L("report.colHouse"), "℞",
        ].joined(separator: " | ")

        return (["## \(L("report.natal"))", "| \(head) |", "| --- | --- | --- | --- | --- |"]
            + rows.map { "| \($0) |" }).joined(separator: "\n")
    }

    private var houses: String? {
        guard positions.houses.count == 12 else { return nil }

        let cusps = positions.houses.enumerated().map { index, longitude in
            "\(index + 1): \(Self.describe(longitude: longitude))"
        }
        return "## \(L("report.houses"))\n\(cusps.joined(separator: " · "))"
    }

    private var natalAspects: String? {
        guard !positions.natalAspects.isEmpty else { return nil }

        let rows = positions.natalAspects.map { aspect in
            let title = Astro.aspectTitle(transit: aspect.p1, aspect: aspect.aspect, natal: aspect.p2)
            return "- \(title), \(L("detail.orb", Self.orb(aspect.orb)))"
        }
        return (["## \(L("report.natalAspects"))"] + rows).joined(separator: "\n")
    }

    private var transits: String? {
        guard !aspects.isEmpty else { return nil }
        return (["## \(L("report.transits"))"] + aspects.map(line(for:))).joined(separator: "\n")
    }

    /// The slow half, already ranked by the engine. Only printed when the
    /// report picked any out — a chart with no outer-planet contact has no
    /// season behind it to describe.
    private var background: String? {
        guard !climate.isEmpty else { return nil }
        return (["## \(L("report.climate"))"] + climate.map(line(for:))).joined(separator: "\n")
    }

    private var forecast: String? {
        guard !days.isEmpty else { return nil }

        let rows = days.map { day -> String in
            let date = day.day.map { LocalizedDate.string($0, template: "dMMM") } ?? day.date
            let tension = day.tensionRatio.map { "\(Int(($0 * 100).rounded()))%" } ?? ""
            return "| \(date) | \(Self.number(day.tii)) | \(tension) | \(Astro.feels(day.feelsLike) ?? "") |"
        }

        let head = [
            L("report.colDate"), L("report.colIntensity"),
            L("report.colTension"), L("report.colWeather"),
        ].joined(separator: " | ")

        return (["## \(L("report.forecast"))", "| \(head) |", "| --- | --- | --- | --- |"] + rows)
            .joined(separator: "\n")
    }

    // MARK: - Rows

    /// One transit, with both sides placed: where the transiting body is now,
    /// where the natal point it is hitting sits and which house that is. The
    /// orb and the window are the part a model can actually reason from, so
    /// they are spelled out rather than summarised.
    private func line(for aspect: ActiveAspect) -> String {
        let transiting = Self.place(positions.transiting[aspect.transitObject])
        let natalSide = Self.place(positions.natal[aspect.natalObject], house: true)

        var parts = [
            L("detail.orb", Self.orb(aspect.orb)),
            Astro.strength(aspect.strength).localizedLowercase,
        ]

        if let status = aspect.timing?.status {
            parts.append(Astro.status(status))
        }
        if let start = aspect.timing?.start, let end = aspect.timing?.end {
            parts.append(L("report.window", day(start), day(end)))
        }
        if let peak = aspect.timing?.peak {
            parts.append(L("report.exact", day(peak)))
        }

        let title = "\(Astro.object(aspect.transitObject))\(transiting) "
            + "\(Astro.aspect(aspect.aspect)) "
            + "\(Astro.object(aspect.natalObject))\(natalSide)"

        return "- \(title): \(parts.joined(separator: ", "))"
    }

    // MARK: - Formatting

    /// " (Pisces 4°02′, house 7)" — the parenthetical after a body's name, or
    /// nothing at all when the report carried no position for it.
    private static func place(_ position: ChartPosition?, house: Bool = false) -> String {
        guard let position else { return "" }

        var parts: [String] = []
        if let sign = Astro.sign(position.sign), let degree = position.formattedDegree {
            parts.append("\(sign) \(degree)")
        } else if let sign = Astro.sign(position.sign) {
            parts.append(sign)
        }
        if house, let number = position.houseNumber {
            parts.append(L("detail.house", number))
        }

        return parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
    }

    /// A house cusp: the longitude split into its sign and the degrees inside
    /// it, the way the payload already splits a body's own position.
    private static func describe(longitude: Double) -> String {
        let normalized = Zodiac.normalize(longitude)
        let index = Zodiac.index(ofLongitude: normalized)
        let within = normalized - Double(index) * 30
        let degree = Int(within)
        let minute = Int((within - Double(degree)) * 60)
        let sign = Astro.sign(Zodiac.names[index]) ?? Zodiac.names[index]
        return "\(degree)°\(String(format: "%02d", minute))′ \(sign)"
    }

    private static func describe(_ moon: MoonPhase) -> String {
        var parts = [Astro.moonPhase(moon.phaseName)]

        if let illumination = moon.illuminationPct {
            parts.append(L("report.illumination", Int(illumination.rounded())))
        }
        if let sign = Astro.sign(moon.moonSign) {
            parts.append(moon.moonDegree.map { "\(sign) \($0)°" } ?? sign)
        }

        return parts.joined(separator: ", ")
    }

    /// A window's date, in the zone the reading was cast for. In the
    /// device's, a transit perfecting near midnight there lands on the day
    /// either side of the one the rest of the report is about.
    ///
    /// The year is printed only when it is not the reading's own. Most
    /// windows open and close inside a few weeks, and "2 Sep 2026" on every
    /// one of them is noise — but an outer-planet window runs for months,
    /// and "31 Jan" with no year is a date nobody can place.
    private func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = moment.zone
        let sameYear = calendar.component(.year, from: date)
            == calendar.component(.year, from: moment.instant)
        return LocalizedDate.string(date, template: sameYear ? "dMMM" : "dMMMyyyy", in: moment.zone)
    }

    private static func orb(_ orb: Double) -> String {
        String(format: "%.2f", orb)
    }

    /// TII is one decimal from the engine, and a whole number most of the
    /// time. Printed as it came rather than rounded, minus a trailing ".0".
    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    #if canImport(UIKit)
    /// Puts the report on the clipboard. UIKit is reached for here rather
    /// than in the page, so the view file stays SwiftUI-only — and the
    /// formatter above builds on the host, where its output can be read.
    func copyToClipboard() {
        UIPasteboard.general.string = markdown
    }
    #endif
}

