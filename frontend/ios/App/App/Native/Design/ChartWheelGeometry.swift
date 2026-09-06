import CoreGraphics
import Foundation

/// The twelve signs, in the order the backend numbers them.
enum Zodiac {

    static let names = [
        "Aries", "Taurus", "Gemini", "Cancer",
        "Leo", "Virgo", "Libra", "Scorpio",
        "Sagittarius", "Capricorn", "Aquarius", "Pisces",
    ]

    /// The sign glyphs are emoji code points by default, so each carries
    /// U+FE0E to ask for the text form. Without it the system hands back the
    /// colour emoji, or nothing at all inside a `Canvas`.
    static let glyphs = [
        "\u{2648}\u{FE0E}", "\u{2649}\u{FE0E}", "\u{264A}\u{FE0E}", "\u{264B}\u{FE0E}",
        "\u{264C}\u{FE0E}", "\u{264D}\u{FE0E}", "\u{264E}\u{FE0E}", "\u{264F}\u{FE0E}",
        "\u{2650}\u{FE0E}", "\u{2651}\u{FE0E}", "\u{2652}\u{FE0E}", "\u{2653}\u{FE0E}",
    ]

    /// Bodies that ride the outer of the two natal rows. Everything else —
    /// Chiron, Lilith, the nodes, the parts — drops to the inner row, which is
    /// how the web wheel keeps a crowded chart readable.
    static let planets: Set<String> = [
        "Sun", "Moon", "Mercury", "Venus", "Mars",
        "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto",
    ]

    static func index(ofSign name: String) -> Int? {
        names.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func isPlanet(_ id: String) -> Bool { planets.contains(id) }

    static func normalize(_ longitude: Double) -> Double {
        let value = longitude.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}

/// Pure geometry for the chart wheel, ported from
/// `frontend/src/components/NatalZodiacRing.tsx` so the native wheel places
/// everything exactly where the web one does.
///
/// No SwiftUI in here on purpose: the maths is worth being able to reason
/// about, and later to test, without a view around it.
enum WheelMath {

    /// A point on the wheel. Angles are mathematical — counterclockwise from
    /// due east — while the screen's y grows downwards, hence the minus.
    static func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: center.x + radius * cos(radians),
            y: center.y - radius * sin(radians)
        )
    }

    /// Where an ecliptic longitude lands on screen once the chart is rotated
    /// so the ascendant sits on the left horizon.
    static func angle(longitude: Double, asc: Double) -> Double {
        normalizeAngle(180 + longitude - asc)
    }

    /// Unit vector along the circle at `angle`.
    static func tangentUnit(_ angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: sin(radians), y: cos(radians))
    }

    /// Halfway from `start` round to `end`, the short way.
    static func midpoint(from start: Double, to end: Double) -> Double {
        let delta = (end - start).truncatingRemainder(dividingBy: 360)
        let forward = delta < 0 ? delta + 360 : delta
        return (start + forward / 2).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - Glyph spreading

    /// One body placed on a band: where it really is, and where its glyph has
    /// to be drawn so it does not collide with its neighbours.
    struct PlacedGlyph: Identifiable {
        let id: String
        let glyph: String
        let longitude: Double
        /// True screen angle, where the tick mark goes.
        let angle: Double
        /// Nudged screen angle, where the glyph goes.
        let displayAngle: Double
    }

    /// Push overlapping glyphs apart along the band, then let each slide back
    /// towards its true angle if the room is there.
    ///
    /// A direct port of `spreadGlyphs` in the web component. Two glyphs need
    /// more angular separation near the top and bottom of the circle, where
    /// they sit side by side, than at the left and right edges where they
    /// stack — hence the width/height split in `separation`.
    static func spread(
        markers: [(id: String, longitude: Double, glyph: String)],
        asc: Double,
        radius: CGFloat,
        glyphSize: CGFloat
    ) -> [PlacedGlyph] {
        guard !markers.isEmpty else { return [] }

        let gap: CGFloat = 1.4
        let glyphWidth = glyphSize * 0.7 + gap
        let glyphHeight = glyphSize * 1.0 + gap
        let degreesPerRadian = 180.0 / Double.pi

        func separation(at midAngle: Double) -> Double {
            let radians = midAngle * .pi / 180
            let horizontal = abs(cos(radians))
            let vertical = abs(sin(radians))
            var value = Double.infinity
            if horizontal > 0.01 {
                value = min(value, Double(glyphWidth) / (Double(radius) * horizontal) * degreesPerRadian)
            }
            if vertical > 0.01 {
                value = min(value, Double(glyphHeight) / (Double(radius) * vertical) * degreesPerRadian)
            }
            return min(value, Double(glyphHeight) / Double(radius) * degreesPerRadian)
        }

        struct Item {
            let id: String
            let glyph: String
            let longitude: Double
            let trueAngle: Double
            var displayAngle: Double
        }

        var items = markers
            .map { marker -> Item in
                let angle = WheelMath.angle(longitude: marker.longitude, asc: asc)
                return Item(
                    id: marker.id,
                    glyph: marker.glyph,
                    longitude: marker.longitude,
                    trueAngle: angle,
                    displayAngle: angle
                )
            }
            .sorted { $0.displayAngle < $1.displayAngle }

        // Step 1: shove overlapping pairs apart, a little each pass.
        for _ in 0..<20 {
            var moved = false
            for index in items.indices {
                let nextIndex = (index + 1) % items.count
                let midAngle = (items[index].displayAngle + items[nextIndex].displayAngle) / 2
                let minimum = separation(at: midAngle)

                var gap = (items[nextIndex].displayAngle - items[index].displayAngle)
                    .truncatingRemainder(dividingBy: 360)
                if gap < 0 { gap += 360 }
                if gap > 180 { gap -= 360 }

                guard abs(gap) < minimum, abs(gap) < 180 else { continue }

                let push = (minimum - abs(gap)) / 2 + 0.05
                let direction: Double = gap >= 0 ? 1 : -1
                items[index].displayAngle = normalizeAngle(items[index].displayAngle - direction * push)
                items[nextIndex].displayAngle = normalizeAngle(items[nextIndex].displayAngle + direction * push)
                moved = true
            }
            if !moved { break }
        }

        // Step 2: the most-displaced glyph goes home first, if it now fits.
        let byDrift = items.indices
            .map { index -> (index: Int, drift: Double) in
                let raw = (items[index].trueAngle - items[index].displayAngle + 540)
                    .truncatingRemainder(dividingBy: 360) - 180
                return (index, abs(raw))
            }
            .sorted { $0.drift > $1.drift }

        for entry in byDrift {
            let index = entry.index
            guard items.count > 1 else {
                items[index].displayAngle = items[index].trueAngle
                continue
            }

            let previous = items[(index - 1 + items.count) % items.count]
            let next = items[(index + 1) % items.count]
            let home = items[index].trueAngle

            var toPrevious = (home - previous.displayAngle).truncatingRemainder(dividingBy: 360)
            if toPrevious < 0 { toPrevious += 360 }
            var toNext = (next.displayAngle - home).truncatingRemainder(dividingBy: 360)
            if toNext < 0 { toNext += 360 }

            let previousOK = toPrevious >= separation(at: (home + previous.displayAngle) / 2) || toPrevious > 180
            let nextOK = toNext >= separation(at: (home + next.displayAngle) / 2) || toNext > 180

            if previousOK && nextOK {
                items[index].displayAngle = home
            }
        }

        return items.map {
            PlacedGlyph(
                id: $0.id,
                glyph: $0.glyph,
                longitude: $0.longitude,
                angle: $0.trueAngle,
                displayAngle: $0.displayAngle
            )
        }
    }

    private static func normalizeAngle(_ angle: Double) -> Double {
        let value = angle.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
