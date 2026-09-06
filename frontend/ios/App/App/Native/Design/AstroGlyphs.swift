import Foundation

/// Unicode glyphs for planets, points and aspects, ported from
/// `frontend/src/components/DailyWeather.tsx` so a transit reads the same
/// natively as it does on the web.
///
/// Nothing extra ships in the bundle: every code point here resolves through
/// the system's Apple Symbols fallback. Objects with no glyph (the angles) are
/// written out, which is what the web does too.
enum AstroGlyph {

    static func object(_ id: String) -> String { objects[id] ?? id }

    static func aspect(_ id: String) -> String { aspects[id.lowercased()] ?? id }

    private static let objects: [String: String] = [
        "Sun": "\u{2609}",
        "Moon": "\u{263D}",
        "Mercury": "\u{263F}",
        "Venus": "\u{2640}",
        "Mars": "\u{2642}",
        "Jupiter": "\u{2643}",
        "Saturn": "\u{2644}",
        "Uranus": "\u{2645}",
        "Neptune": "\u{2646}",
        "Pluto": "\u{2647}",
        "Chiron": "\u{26B7}",
        "Lilith": "\u{26B8}",
        "Selena": "\u{263E}",
        "North Node": "\u{260A}",
        "South Node": "\u{260B}",
        "Part of Fortune": "\u{2297}",
        "Vertex": "\u{22C1}",
        "ASC": "AC",
        "MC": "MC",
    ]

    private static let aspects: [String: String] = [
        "conjunction": "\u{260C}",
        "opposition": "\u{260D}",
        "trine": "\u{25B3}",
        "square": "\u{25A1}",
        "sextile": "\u{2731}",
    ]
}

/// Order the transiting bodies are listed in — fast personal planets first,
/// then the slow outer ones, then the points. Mirrors the web widget's sort.
enum TransitOrder {

    static func rank(_ object: String) -> Int {
        index[object] ?? order.count
    }

    private static let order = [
        "Sun", "Moon", "Mercury", "Venus", "Mars",
        "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto",
        "Chiron", "Lilith", "Selena",
        "North Node", "South Node", "Part of Fortune", "Vertex",
    ]

    private static let index: [String: Int] = {
        Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
    }()
}

/// The three bands the card groups transits into, in the order they are shown.
/// Mirrors the web widget's `categorizeWidgetAspect`.
enum TransitGroup: String, CaseIterable, Identifiable {
    case personal, outer, special

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: return "Personal planets"
        case .outer: return "Outer planets"
        case .special: return "Special points"
        }
    }

    init(transitObject: String) {
        if Self.personalIds.contains(transitObject) {
            self = .personal
        } else if Self.outerIds.contains(transitObject) {
            self = .outer
        } else {
            self = .special
        }
    }

    private static let personalIds: Set<String> = ["Sun", "Moon", "Mercury", "Venus", "Mars"]
    private static let outerIds: Set<String> = ["Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"]
}
