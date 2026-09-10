import Foundation

/// What each piece of a reading stands for, in one line: the planets and the
/// angles, the twelve signs, the twelve houses, the five aspects.
///
/// Definitions, not a reading. Nothing here knows which chart is on screen or
/// what the orb happens to be today: Saturn is structure and discipline
/// whoever is looking, and the conclusion is the reader's to draw. That is the
/// whole point of the About blocks these feed.
///
/// The text is the web app's own, ported key for key from the "How It Works"
/// sheet (`guide.*` in `frontend/src/i18n/{en,ru}.ts`), so both halves of the
/// app define a square the same way and a line translated once stays
/// translated. `Strings` holds the tables.
enum Glossary {

    /// "Saturn" → "Structure, discipline, limits, lessons…".
    ///
    /// Nil for a point the guide has no line for, so the row is dropped
    /// rather than printed with its own dotted key inside it.
    static func object(_ id: String) -> String? {
        guard let key = objectKeys[id] else { return nil }
        return lookup(key)
    }

    /// "Taurus" → "Builder. Patient, sensual, stubborn."
    static func sign(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return lookup("guide.\(name.lowercased())Desc")
    }

    /// 4 → "Home, family, roots, privacy…".
    static func house(_ number: Int?) -> String? {
        guard let number, (1...12).contains(number) else { return nil }
        return lookup("guide.house\(number)")
    }

    /// "square" → "Tension. Friction that forces action…".
    static func aspect(_ name: String) -> String? {
        lookup("guide.\(name.lowercased())Desc")
    }

    /// "Square, 90°" — the aspect named the way the sheet above says it, with
    /// the angle that defines it, which is the part a table of glyphs never
    /// gets to say.
    static func aspectTerm(_ name: String) -> String {
        let named = Astro.aspect(name).capitalized
        guard let angle = aspectAngles[name.lowercased()] else { return named }
        return "\(named), \(angle)°"
    }

    /// The angle each aspect is an aspect of. Only the five the engine emits;
    /// a name it does not know has no angle rather than a guessed one.
    private static let aspectAngles: [String: Int] = [
        "conjunction": 0,
        "sextile": 60,
        "square": 90,
        "trine": 120,
        "opposition": 180,
    ]

    /// The ids the API answers with, against the web's key for each. Written
    /// out rather than derived: three of them are two words, and four are
    /// abbreviations the guide spells in full.
    private static let objectKeys: [String: String] = [
        "Sun": "guide.sunDesc",
        "Moon": "guide.moonDesc",
        "Mercury": "guide.mercuryDesc",
        "Venus": "guide.venusDesc",
        "Mars": "guide.marsDesc",
        "Jupiter": "guide.jupiterDesc",
        "Saturn": "guide.saturnDesc",
        "Uranus": "guide.uranusDesc",
        "Neptune": "guide.neptuneDesc",
        "Pluto": "guide.plutoDesc",
        "Chiron": "guide.chironDesc",
        "Lilith": "guide.lilithDesc",
        "Selena": "guide.selenaDesc",
        "North Node": "guide.northNodeDesc",
        "South Node": "guide.southNodeDesc",
        "Part of Fortune": "guide.pofDesc",
        "Vertex": "guide.vertexDesc",
        "ASC": "guide.ascendantDesc",
        "DC": "guide.descendantDesc",
        "MC": "guide.midheavenDesc",
        "IC": "guide.imumCoeliDesc",
    ]

    /// A key the tables do not carry answers with itself, which is fine for a
    /// label and useless for a paragraph, so it comes back as nil instead.
    private static func lookup(_ key: String) -> String? {
        let text = LanguageStore.string(key)
        return text == key ? nil : text
    }
}
