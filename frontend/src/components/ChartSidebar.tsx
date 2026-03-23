import type { NatalPosition, NatalAspect } from "../types"

const OBJECT_GLYPHS: Record<string, string> = {
  Sun: "\u2609", Moon: "\u263D", Mercury: "\u263F", Venus: "\u2640", Mars: "\u2642",
  Jupiter: "\u2643", Saturn: "\u2644", Uranus: "\u2645", Neptune: "\u2646", Pluto: "\u2647",
  Chiron: "\u26B7", Lilith: "\u26B8", Selena: "\u263E",
  "North Node": "\u260A", "South Node": "\u260B", "Part of Fortune": "\u2297", Vertex: "\u22C1",
  ASC: "AC", MC: "MC",
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

  const aspectMap = new Map<string, NatalAspect>()
  for (const a of aspects) {
    aspectMap.set(`${a.p1}|${a.p2}`, a)
    aspectMap.set(`${a.p2}|${a.p1}`, a)
  }

  const pyramidPlanets = PLANET_ORDER.filter((id) => byId.has(id))

  if (pyramidPlanets.length < 2 || !aspects.length) return null

  return (
    <div className="cs">
      <div className="cs-title">ASPECT GRID</div>
      <div className="cs-pyramid">
        {pyramidPlanets.map((rowPlanet, ri) => {
          if (ri === 0) return null
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
    </div>
  )
}
