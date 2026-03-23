import type { NatalPosition, NatalAspect, ActiveAspect, TransitPosition } from "../types"

const OBJECT_GLYPHS: Record<string, string> = {
  Sun: "\u2609", Moon: "\u263D", Mercury: "\u263F", Venus: "\u2640", Mars: "\u2642",
  Jupiter: "\u2643", Saturn: "\u2644", Uranus: "\u2645", Neptune: "\u2646", Pluto: "\u2647",
  Chiron: "\u26B7", Lilith: "\u26B8", Selena: "\u263E",
  "North Node": "\u260A", "South Node": "\u260B", "Part of Fortune": "\u2297", Vertex: "\u22C1",
  ASC: "AC", MC: "MC",
}

const SIGN_GLYPHS: Record<string, string> = {
  Aries: "\u2648", Taurus: "\u2649", Gemini: "\u264A", Cancer: "\u264B",
  Leo: "\u264C", Virgo: "\u264D", Libra: "\u264E", Scorpio: "\u264F",
  Sagittarius: "\u2650", Capricorn: "\u2651", Aquarius: "\u2652", Pisces: "\u2653",
}

const ASPECT_GLYPHS: Record<string, string> = {
  conjunction: "\u260C", sextile: "\u26B9", square: "\u25A1", trine: "\u25B3", opposition: "\u260D",
}

const ASPECT_COLORS: Record<string, string> = {
  conjunction: "#8b8b8b",
  sextile: "#3b82f6",
  trine: "#3b82f6",
  square: "#ef4444",
  opposition: "#ef4444",
}

const SIGN_ELEMENT: Record<string, string> = {
  Aries: "fire", Taurus: "earth", Gemini: "air", Cancer: "water",
  Leo: "fire", Virgo: "earth", Libra: "air", Scorpio: "water",
  Sagittarius: "fire", Capricorn: "earth", Aquarius: "air", Pisces: "water",
}

const ELEMENT_COLORS: Record<string, string> = {
  fire: "#ef4444",
  earth: "#22c55e",
  air: "#eab308",
  water: "#3b82f6",
}

const PLANET_ORDER = [
  "Sun", "Moon", "Mercury", "Venus", "Mars",
  "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto",
  "Chiron", "Lilith", "Selena", "North Node", "South Node",
  "Part of Fortune", "Vertex", "ASC", "MC",
]

const SHORT_NAMES: Record<string, string> = {
  "North Node": "Node",
  "South Node": "S.Node",
  "Part of Fortune": "Fortune",
  ASC: "ASC",
  MC: "MC",
}

type Props = {
  positions: NatalPosition[]
  natalAspects: NatalAspect[]
  mode: "natal" | "transit"
  transitPositions?: TransitPosition[]
  transitAspects?: ActiveAspect[]
}

export default function ChartSidebar({ positions, natalAspects, mode, transitPositions, transitAspects }: Props) {
  const byId = new Map(positions.map((p) => [p.id, p]))

  // Natal aspect lookup
  const natalAspectMap = new Map<string, { aspect: string }>()
  for (const a of natalAspects) {
    natalAspectMap.set(`${a.p1}|${a.p2}`, a)
    natalAspectMap.set(`${a.p2}|${a.p1}`, a)
  }

  // Transit aspect lookup: transit_object → natal_object
  const transitAspectMap = new Map<string, { aspect: string }>()
  if (transitAspects) {
    for (const a of transitAspects) {
      if (!a.is_within_orb) continue
      transitAspectMap.set(`${a.transit_object}|${a.natal_object}`, a)
    }
  }

  // Transit positions map
  const transitById = new Map((transitPositions ?? []).map((p) => [p.id, p]))

  const planets = PLANET_ORDER.filter((id) => byId.has(id))
  if (planets.length < 2) return null

  // In transit mode: rows = transit planets, columns = natal planets
  // In natal mode: classic pyramid (rows & cols are same planets)
  const isTransit = mode === "transit" && transitPositions && transitPositions.length > 0

  // Transit planets that exist
  const transitPlanets = isTransit
    ? PLANET_ORDER.filter((id) => transitById.has(id))
    : []

  return (
    <div className="cs">
      <table className="cs-table">
        <tbody>
          {isTransit ? (
            // Transit mode: full grid (transit rows × natal columns)
            <>
              {transitPlanets.map((rowPlanet) => {
                const tp = transitById.get(rowPlanet)!
                const elColor = ELEMENT_COLORS[SIGN_ELEMENT[tp.sign] ?? ""] ?? "#888"
                return (
                  <tr key={rowPlanet} className="cs-tr">
                    <td className="cs-td-glyph">{OBJECT_GLYPHS[rowPlanet] ?? ""}</td>
                    <td className="cs-td-name">{SHORT_NAMES[rowPlanet] ?? rowPlanet}</td>
                    <td className="cs-td-sign" style={{ color: elColor }}>{SIGN_GLYPHS[tp.sign] ?? ""}</td>
                    <td className="cs-td-deg">{tp.degree}°{String(tp.minute).padStart(2, "0")}′</td>
                    <td className="cs-td-house">{tp.natal_house || "—"}</td>
                    {planets.map((colPlanet) => {
                      const asp = transitAspectMap.get(`${rowPlanet}|${colPlanet}`)
                      return (
                        <td key={colPlanet} className="cs-td-asp">
                          {asp ? (
                            <span style={{ color: ASPECT_COLORS[asp.aspect] ?? "#888" }}>
                              {ASPECT_GLYPHS[asp.aspect] ?? ""}
                            </span>
                          ) : null}
                        </td>
                      )
                    })}
                    <td className="cs-td-diag">{OBJECT_GLYPHS[rowPlanet] ?? ""}</td>
                  </tr>
                )
              })}
              {/* Bottom labels: natal planets */}
              <tr className="cs-tr cs-tr--footer">
                <td colSpan={5} />
                {planets.map((p) => (
                  <td key={p} className="cs-td-foot">{OBJECT_GLYPHS[p] ?? ""}</td>
                ))}
                <td />
              </tr>
            </>
          ) : (
            // Natal mode: pyramid with planet info on left
            <>
              {planets.map((rowPlanet, ri) => {
                const pos = byId.get(rowPlanet)!
                const elColor = ELEMENT_COLORS[SIGN_ELEMENT[pos.sign] ?? ""] ?? "#888"
                return (
                  <tr key={rowPlanet} className="cs-tr">
                    <td className="cs-td-glyph">{OBJECT_GLYPHS[rowPlanet] ?? ""}</td>
                    <td className="cs-td-name">{SHORT_NAMES[rowPlanet] ?? rowPlanet}</td>
                    <td className="cs-td-sign" style={{ color: elColor }}>{SIGN_GLYPHS[pos.sign] ?? ""}</td>
                    <td className="cs-td-deg">{pos.degree}°{String(pos.minute).padStart(2, "0")}′</td>
                    <td className="cs-td-house">{pos.house || "—"}</td>
                    {/* Aspect cells: only up to current index (pyramid) */}
                    {planets.slice(0, ri).map((colPlanet) => {
                      const asp = natalAspectMap.get(`${rowPlanet}|${colPlanet}`)
                      return (
                        <td key={colPlanet} className="cs-td-asp">
                          {asp ? (
                            <span style={{ color: ASPECT_COLORS[asp.aspect] ?? "#888" }}>
                              {ASPECT_GLYPHS[asp.aspect] ?? ""}
                            </span>
                          ) : null}
                        </td>
                      )
                    })}
                    {/* Diagonal label */}
                    <td className="cs-td-diag">{OBJECT_GLYPHS[rowPlanet] ?? ""}</td>
                  </tr>
                )
              })}
              {/* Bottom labels */}
              <tr className="cs-tr cs-tr--footer">
                <td colSpan={5} />
                {planets.slice(0, -1).map((p) => (
                  <td key={p} className="cs-td-foot">{OBJECT_GLYPHS[p] ?? ""}</td>
                ))}
              </tr>
            </>
          )}
        </tbody>
      </table>
    </div>
  )
}
