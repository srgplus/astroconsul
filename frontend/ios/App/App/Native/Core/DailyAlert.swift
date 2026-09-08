import Foundation

/// One day of the forecast, ready to be fired as a notification.
///
/// The engine casts one reading per local noon and sorts it into one of twelve
/// categories (`Calm` … `Explosive`, the TII × tension matrix), so a day is the
/// unit the whole feature is built on and the entire window is known in
/// advance. That is what lets the alerts be local: this type turns a forecast
/// into a list of days, and `CategoryAlerts` hands them to iOS.
///
/// One alert per day, not one per change. Alerting only on the days the
/// category moved is a smaller promise than it sounds: a calm fortnight has
/// nothing to say, and Settings then shows a next alert six days out for
/// someone who asked to hear from the app every day at noon. The day it *did*
/// change is still marked — `changed` is what the wording turns on — but the
/// schedule no longer skips the days it did not.
///
/// Deliberately free of UserNotifications and UIKit so the rule that decides
/// *what* to say and *when* can be exercised on its own.
struct DailyAlert: Codable, Equatable {

    /// `YYYY-MM-DD` in the timezone the forecast was asked for.
    let date: String
    /// The day before's category, which is what makes the wording possible.
    let from: String
    let to: String
    let fromTii: Double
    let tii: Double

    /// Whether the category moved overnight. Only the copy reads this now;
    /// the schedule covers both kinds of day.
    var changed: Bool { from != to }

    /// Every day in the window except the first.
    ///
    /// Day zero is the anchor, not a result: it has no predecessor inside the
    /// window, so there is nothing to say the day came from. That is why
    /// `CategoryAlerts` asks for a window starting the day *before* the first
    /// one it wants to alert on — otherwise today could never be alerted for,
    /// and a rebuild on the morning of an alert would drop that day instead of
    /// re-laying it.
    static func list(in days: [ForecastDay]) -> [DailyAlert] {
        zip(days, days.dropFirst()).map { previous, day in
            DailyAlert(
                date: day.date,
                from: previous.feelsLike,
                to: day.feelsLike,
                fromTii: previous.tii,
                tii: day.tii
            )
        }
    }

    /// When this day's alert should fire: the day itself, at the chosen hour,
    /// in the zone the forecast was cast for.
    ///
    /// Returned as components rather than a `Date` because that is what
    /// `UNCalendarNotificationTrigger` takes, and because carrying the zone
    /// through means a person who flies somewhere still gets the alert on the
    /// day the reading belongs to.
    func fireComponents(hour: Int, minute: Int, in zone: TimeZone) -> DateComponents? {
        guard let day = Self.day(from: date) else { return nil }

        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = hour
        components.minute = minute
        components.timeZone = zone
        return components
    }

    /// `YYYY-MM-DD` split by hand. `DateFormatter` would do it too, but it
    /// carries a timezone of its own, and the day here is a calendar date
    /// rather than an instant.
    private static func day(from iso: String) -> (year: Int, month: Int, day: Int)? {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        return (year, month, day)
    }

    // MARK: - Copy

    var title: String {
        let category = Astro.feels(to) ?? to
        guard let emoji = FeelsLike.emoji(for: to) else { return category }
        return "\(emoji) \(category)"
    }

    /// The reading, on a line of its own.
    ///
    /// It is also drawn on the artwork, which is the version worth looking at —
    /// but an attachment is a thumbnail the system renders, and a system that
    /// declines to render it must not take the temperature down with it. The
    /// subtitle always shows.
    var subtitle: String { L("weather.intensityValue", Int(tii.rounded())) }

    /// The title names the day's category and the subtitle carries the
    /// reading, so the body is only what neither of them says: where the day
    /// came from.
    ///
    /// A day that held its category says so plainly. Naming the same category
    /// twice — "shifting from Calm" on a second calm day — is the wording that
    /// makes a daily alert read as broken.
    ///
    /// No "today" on the end. The alert is dated by the system the moment it
    /// lands, and an evening reader is being told about a day already half
    /// spent.
    var body: String {
        guard changed else { return L("alert.steady") }

        let verb: String
        if tii > fromTii {
            verb = L("alert.rising")
        } else if tii < fromTii {
            verb = L("alert.easing")
        } else {
            verb = L("alert.shifting")
        }
        return L("alert.body", verb, Astro.feels(from) ?? from)
    }
}
