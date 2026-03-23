import type { NatalPosition, NatalAspect } from "../types"

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

const DISPLAY_NAMES: Record<string, string> = {
  ASC: "Ascendent",
  MC: "Mid Heaven",
  "North Node": "North Node",
  "South Node": "South Node",
  "Part of Fortune": "Part of Fortune",
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

type GroupDef = { label: string; ids: string[] }

const GROUPS: GroupDef[] = [
  { label: "PERSONAL PLANETS", ids: ["Sun", "Moon", "ASC", "MC", "Mercury", "Venus", "Mars"] },
  { label: "OUTER PLANETS", ids: ["Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"] },
  { label: "SPECIAL POINTS", ids: ["Chiron", "Lilith", "Selena", "North Node", "South Node", "Part of Fortune", "Vertex"] },
]

const PLANET_ORDER = [
  "Sun", "Moon", "Mercury", "Venus", "Mars",
  "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto",
  "Chiron", "Lilith", "Selena", "North Node", "South Node",
  "Part of Fortune", "Vertex", "ASC", "MC",
]

type Props = {
  positions: NatalPosition[]
  aspects: NatalAspect[]
}

export default function ChartSidebar({ positions, aspects }: Props) {
  const byId = new Map(positions.map((p) => [p.id, p]))

  // Build aspect lookup for pyramid: key = "p1|p2" sorted by PLANET_ORDER
  const aspectMap = new Map<string, NatalAspect>()
  for (const a of aspects) {
    const key = `${a.p1}|${a.p2}`
    aspectMap.set(key, a)
    aspectMap.set(`${a.p2}|${a.p1}`, a)
  }

  // Filter to only planets that exist in positions
  const pyramidPlanets = PLANET_ORDER.filter((id) => byId.has(id))

  return (
    <div className="cs">
      {/* Positions table */}
      <div className="cs-title">PLANETS & HOUSES</div>
      {GROUPS.map((group) => {
        const rows = group.ids.map((id) => byId.get(id)).filter(Boolean) as NatalPosition[]
        if (!rows.length) return null
        return (
          <div key={group.label}>
            <div className="cs-group">{group.label}</div>
            {rows.map((p) => {
              const elColor = ELEMENT_COLORS[SIGN_ELEMENT[p.sign] ?? ""] ?? "#888"
              return (
                <div key={p.id} className="cs-row">
                  <span className="cs-glyph">{OBJECT_GLYPHS[p.id] ?? ""}</span>
                  <span className="cs-name">{DISPLAY_NAMES[p.id] ?? p.id}</span>
                  <span className="cs-sign">
                    <span className="cs-sign-name">{p.sign}</span>
                    <span className="cs-sign-glyph" style={{ color: elColor }}>{SIGN_GLYPHS[p.sign] ?? ""}</span>
                  </span>
                  <span className="cs-house">{"\u25B3"}{p.house || "—"}</span>
                  <span className="cs-deg">{p.degree}°{String(p.minute).padStart(2, "0")}′</span>
                </div>
              )
            })}
          </div>
        )
      })}

      {/* Aspect pyramid */}
      {pyramidPlanets.length > 1 && aspects.length > 0 ? (
        <>
          <div className="cs-title cs-title--aspects">ASPECTS</div>
          <div className="cs-pyramid" style={{ "--cols": pyramidPlanets.length } as React.CSSProperties}>
            {pyramidPlanets.map((rowPlanet, ri) => {
              if (ri === 0) return null // first row has no cells
              return (
                <div key={rowPlanet} className="cs-pyr-row">
                  {pyramidPlanets.slice(0, ri).map((colPlanet) => {
                    const asp = aspectMap.get(`${rowPlanet}|${colPlanet}`)
                    return (
                      <div key={colPlanet} className="cs-pyr-cell">
                        {asp ? (
                          <span style={{ color: ASPECT_COLORS[asp.aspect] ?? "#888" }}>
                            {ASPECT_GLYPHS[asp.aspect] ?? asp.aspect[0]}
                          </span>
                        ) : null}
                      </div>
                    )
                  })}
                  <div className="cs-pyr-label">{OBJECT_GLYPHS[rowPlanet] ?? rowPlanet.slice(0, 2)}</div>
                </div>
              )
            })}
            {/* Bottom row: column labels */}
            <div className="cs-pyr-row cs-pyr-row--labels">
              {pyramidPlanets.slice(0, -1).map((planet) => (
                <div key={planet} className="cs-pyr-label">{OBJECT_GLYPHS[planet] ?? planet.slice(0, 2)}</div>
              ))}
            </div>
          </div>
        </>
      ) : null}
    </div>
  )
}
