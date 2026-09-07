import Foundation

/// A day on which the forecast's feels-like category differs from the day
/// before it — the thing an alert is fired for.
///
/// The engine casts one reading per local noon and sorts it into one of twelve
/// categories (`Calm` … `Explosive`, the TII × tension matrix), so a change
/// always lands on a day boundary and the whole window is known in advance.
/// That is what lets the alerts be local: this type turns a forecast into a
/// list of dates, and `CategoryAlerts` hands them to iOS.
///
/// Deliberately free of UserNotifications and UIKit so the rule that decides
/// *whether* and *when* to notify can be exercised on its own.
struct CategoryChange: Codable, Equatable {

    /// `YYYY-MM-DD` in the timezone the forecast was asked for.
    let date: String
    let from: String
    let to: String
    let fromTii: Double
    let tii: Double

    /// Every day in the window whose category differs from its predecessor.
    ///
    /// Day zero is left out on purpose. It has no predecessor inside the
    /// window, and an alert for today would arrive after the change is already
    /// on the screen — the run that scheduled the window today fell in has
    /// queued it already.
    static func list(in days: [ForecastDay]) -> [CategoryChange] {
        zip(days, days.dropFirst()).compactMap { previous, day in
            guard day.feelsLike != previous.feelsLike else { return nil }
            return CategoryChange(
                date: day.date,
                from: previous.feelsLike,
                to: day.feelsLike,
                fromTii: previous.tii,
                tii: day.tii
            )
        }
    }

    /// When the alert for this change should fire: the change's own day, at the
    /// chosen hour, in the zone the forecast was cast for.
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
    var subtitle: String { "\(Int(tii.rounded()))°" }

    /// The title names the new category and the subtitle carries the reading,
    /// so the body is only what neither of them says: where the day came from.
    ///
    /// No "today" on the end. The alert is dated by the system the moment it
    /// lands, and an evening reader is being told about a day already half
    /// spent.
    var body: String {
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
