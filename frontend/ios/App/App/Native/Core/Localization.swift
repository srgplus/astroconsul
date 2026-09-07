import Foundation
import SwiftUI

/// Which language the native screens are drawn in.
///
/// `system` follows the device, which is what a fresh install starts on. The
/// other two are a deliberate override, because an app is often read in one
/// language and lived in another — the web app has offered the same switch
/// since it shipped, and this is the native half of it.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, ru

    var id: String { rawValue }

    /// Each language names itself, the way iOS names languages in its own
    /// picker. `system` is the exception: it is a rule rather than a language,
    /// so it is named in whichever one is currently in force.
    var label: String {
        switch self {
        case .system: return L("settings.language.system")
        case .en: return "English"
        case .ru: return "Русский"
        }
    }

    /// The language this setting actually puts in force. Anything the app has
    /// no strings for reads as English.
    var resolved: Language {
        switch self {
        case .en: return .en
        case .ru: return .ru
        case .system: return Self.deviceLanguage
        }
    }

    /// The device's own choice, as far as this app can honour it.
    ///
    /// Read from the preferred list rather than from `Locale.current`: that
    /// one is narrowed to the languages the bundle declares, so it would keep
    /// answering "en" on a Russian phone whatever the strings say.
    static var deviceLanguage: Language {
        for identifier in Locale.preferredLanguages {
            if let language = Language(identifier: identifier) { return language }
        }
        return .en
    }
}

/// A language the app has strings for.
enum Language: String {
    case en, ru

    /// Matches on the language subtag alone, so "ru-BY" and "ru-Cyrl-RU" both
    /// land on Russian.
    init?(identifier: String) {
        let code = identifier.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
        guard let language = Language(rawValue: code) else { return nil }
        self = language
    }
}

/// The language the strings are read in.
///
/// Deliberately not on `L10n`: an error's `errorDescription`, a date formatter
/// and the notification builder all want a string and none of them is on the
/// main actor. The setting is written from Settings and read from everywhere,
/// so it lives here and `L10n` is the observable face of it.
enum LanguageStore {

    static let key = "nativeLanguage"

    /// Cached so a lookup is a dictionary read rather than a trip through
    /// `UserDefaults`; the strings are asked for once per label per redraw.
    nonisolated(unsafe) private static var cached: AppLanguage = {
        let saved = UserDefaults.standard.string(forKey: key)
        return saved.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }()

    static var setting: AppLanguage {
        get { cached }
        set {
            cached = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    /// The language in force right now.
    static var current: Language { cached.resolved }

    /// `"en"` / `"ru"` — what the API's `lang` parameter wants.
    static var code: String { current.rawValue }

    /// A locale for the date formatters, so a stamp reads "пн, 7 сент." on a
    /// Russian reading and "Mon, 7 Sep" on an English one, whatever the device
    /// itself is set to.
    static var locale: Locale { Locale(identifier: current == .ru ? "ru_RU" : "en_US") }

    static func string(_ key: String) -> String {
        switch current {
        case .en: return Strings.en[key] ?? key
        case .ru: return Strings.ru[key] ?? Strings.en[key] ?? key
        }
    }
}

/// The native side's string table, as an object the screens can watch.
///
/// A dictionary rather than `Localizable.strings` and the bundle's own lookup,
/// for one reason: the language is a setting inside the app, and swapping the
/// bundle out from under `NSLocalizedString` at runtime is a swizzle. Here the
/// switch is a published property, so every screen observing it redraws in the
/// new language on the spot.
///
/// The keys are the web app's — `frontend/src/i18n/{en,ru}.ts` — wherever the
/// two apps say the same thing, so a phrase translated once is translated for
/// both.
@MainActor
final class L10n: ObservableObject {

    static let shared = L10n()

    /// What Settings is set to, `system` included.
    @Published var language: AppLanguage = LanguageStore.setting {
        didSet {
            guard oldValue != language else { return }
            LanguageStore.setting = language
            // The web half of the app reads its own copy of this setting out
            // of localStorage, so it is told as well.
            WebControllerHolder.shared.syncLanguage()
            // The category alerts are written days before they land, so the
            // queue is rebuilt from the changes already stored: without this
            // a banner scheduled this morning would arrive in last week's
            // language.
            Task { await CategoryAlerts.shared.reschedule() }
        }
    }

    private init() {}

    var current: Language { language.resolved }
}

// MARK: - Lookup

/// The whole call site: `Text(L("settings.title"))`.
///
/// A free function rather than a method, because the strings are wanted from
/// view models, from formatters and from the notification builder as well as
/// from views. A view that has to *redraw* when the language changes observes
/// `L10n.shared` on top of this; the function itself only reads.
func L(_ key: String) -> String {
    LanguageStore.string(key)
}

/// The same, with `%@` and `%d` filled in.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: LanguageStore.string(key), locale: LanguageStore.locale, arguments: arguments)
}

/// Russian counts in three forms where English counts in two, and the app has
/// three places that print a count with its noun — the days to the full moon,
/// a chart's age and the number of scheduled alerts. So the noun is picked
/// here rather than by pluralising a single string.
///
/// `key` names a group of three: `<key>.one`, `<key>.few`, `<key>.many`. The
/// English table sets `few` and `many` to the same plural, so the two rules can
/// read from one group of keys.
func L(count: Int, _ key: String) -> String {
    String(
        format: LanguageStore.string("\(key).\(pluralForm(count))"),
        locale: LanguageStore.locale,
        count
    )
}

/// The rule is the language's own, not one rule for both: run through the
/// Russian one, English 21 comes out as "21 year".
private func pluralForm(_ count: Int) -> String {
    let mod100 = abs(count) % 100
    let mod10 = abs(count) % 10

    switch LanguageStore.current {
    case .en:
        return abs(count) == 1 ? "one" : "many"
    case .ru:
        // 1, 21, 31 take the singular; 2-4 and 22-24 the paucal; 11-14 are
        // the exception that has to be tested before the last digit is.
        if mod100 >= 11, mod100 <= 14 { return "many" }
        if mod10 == 1 { return "one" }
        if mod10 >= 2, mod10 <= 4 { return "few" }
        return "many"
    }
}

// MARK: - Dates

/// Date formatters built from a template, cached per language and zone.
///
/// A formatter built once at launch would keep printing "Mon" after the app
/// was switched to Russian: `setLocalizedDateFormatFromTemplate` resolves the
/// template against the locale it is handed at the time. So the cache is keyed
/// by the language too, and a switch simply misses and builds a new one.
enum LocalizedDate {

    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    static func formatter(_ template: String, in zone: TimeZone? = nil) -> DateFormatter {
        let locale = LanguageStore.locale
        let key = "\(template)|\(locale.identifier)|\(zone?.identifier ?? "-")"
        if let cached = cache[key] { return cached }

        let formatter = DateFormatter()
        formatter.locale = locale
        if let zone { formatter.timeZone = zone }
        formatter.setLocalizedDateFormatFromTemplate(template)
        cache[key] = formatter
        return formatter
    }

    static func string(_ date: Date, template: String, in zone: TimeZone? = nil) -> String {
        formatter(template, in: zone).string(from: date)
    }
}

// MARK: - Values from the API

/// The engine's own vocabulary, translated on this side.
///
/// The API answers in English for all of these — the feels-like label is a key
/// into a matrix, the planets and signs are ids, the strength bands are enum
/// names — and every one of them is shown to a reader. So the server's word is
/// kept as the key and the reading is looked up here, which is exactly what
/// the web app does with the same keys.
enum Astro {

    /// "Flowing" → "Поток".
    static func feels(_ label: String?) -> String? {
        guard let label, !label.isEmpty else { return nil }
        return lookup("feels.\(label)", fallback: label)
    }

    /// "Saturn" → "Сатурн", "ASC" → "Асцендент".
    static func object(_ id: String) -> String {
        lookup("planet.\(id)", fallback: id)
    }

    /// "Taurus" → "Телец".
    static func sign(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return lookup("sign.\(name.capitalized)", fallback: name)
    }

    /// "square" → "квадрат".
    static func aspect(_ name: String) -> String {
        lookup("aspect.\(name.lowercased())", fallback: name)
    }

    /// "exact" → "ТОЧНЫЙ". Already upper case in both tables: the label is set
    /// in caps, and `uppercased()` on the Russian word is not what the web's
    /// own table says.
    static func strength(_ name: String) -> String {
        lookup("strength.\(name.lowercased())", fallback: name.uppercased())
    }

    /// "applying" → "сходится".
    static func status(_ name: String) -> String {
        lookup("status.\(name.lowercased())", fallback: name)
    }

    /// "Waxing Gibbous" → "Растущая Луна".
    static func moonPhase(_ name: String) -> String {
        lookup("moon.\(name)", fallback: name)
    }

    /// "Saturn square Moon" → "Сатурн квадрат Луна".
    static func aspectTitle(transit: String, aspect name: String, natal: String) -> String {
        "\(object(transit)) \(aspect(name)) \(object(natal))"
    }

    /// The line under the feels-like label, for the time of day the reading
    /// was cast at. `data/feels_like_time_modifiers.json` is the source of
    /// truth for both halves of these; edits there belong in `Strings` too.
    static func headline(for label: String?, at date: Date, in zone: TimeZone) -> String? {
        guard let label, !label.isEmpty else { return nil }
        let key = "mood.\(label).\(TimeWindow(date: date, in: zone).rawValue)"
        let text = LanguageStore.string(key)
        return text == key ? nil : text
    }

    /// A key the tables may not carry — the engine grows labels — falls back
    /// to the server's own word rather than showing a dotted key to a reader.
    private static func lookup(_ key: String, fallback: String) -> String {
        let text = LanguageStore.string(key)
        return text == key ? fallback : text
    }
}
