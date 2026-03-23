import type { NatalPosition, NatalAspect, ActiveAspect, TransitPosition } from "../types"

const G: Record<string, string> = {
  Sun: "\u2609", Moon: "\u263D", Mercury: "\u263F", Venus: "\u2640", Mars: "\u2642",
  Jupiter: "\u2643", Saturn: "\u2644", Uranus: "\u2645", Neptune: "\u2646", Pluto: "\u2647",
  Chiron: "\u26B7", Lilith: "\u26B8", Selena: "\u263E",
  "North Node": "\u260A", "South Node": "\u260B", "Part of Fortune": "\u2297", Vertex: "\u22C1",
  ASC: "AC", MC: "MC",
}

const SG: Record<string, string> = {
  Aries: "\u2648", Taurus: "\u2649", Gemini: "\u264A", Cancer: "\u264B",
  Leo: "\u264C", Virgo: "\u264D", Libra: "\u264E", Scorpio: "\u264F",
  Sagittarius: "\u2650", Capricorn: "\u2651", Aquarius: "\u2652", Pisces: "\u2653",
}

const AG: Record<string, string> = {
  conjunction: "\u260C", sextile: "\u26B9", square: "\u25A1", trine: "\u25B3", opposition: "\u260D",
}

const AC: Record<string, string> = {
  conjunction: "#8b8b8b", sextile: "#3b82f6", trine: "#3b82f6",
  square: "#ef4444", opposition: "#ef4444",
}

const EL: Record<string, string> = {
  Aries: "fire", Taurus: "earth", Gemini: "air", Cancer: "water",
  Leo: "fire", Virgo: "earth", Libra: "air", Scorpio: "water",
  Sagittarius: "fire", Capricorn: "earth", Aquarius: "air", Pisces: "water",
}

const EC: Record<string, string> = {
  fire: "#ef4444", earth: "#22c55e", air: "#eab308", water: "#3b82f6",
}

const PLANET_ORDER = [
  "Sun", "Moon", "Mercury", "Venus", "Mars",
  "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto",
  "Chiron", "Lilith", "Selena", "North Node", "South Node",
  "Part of Fortune", "Vertex", "ASC", "MC",
]

const SN: Record<string, string> = {
  "North Node": "Node", "South Node": "S.Node", "Part of Fortune": "Fortune",
}

type Props = {
  positions: NatalPosition[]
  natalAspects: NatalAspect[]
  mode: "natal" | "transit"
  transitPositions?: TransitPosition[]
  transitAspects?: ActiveAspect[]
  textColor?: string
  mutedColor?: string
  gridColor?: string
}

export default function ChartSidebar({
  positions, natalAspects, mode, transitPositions, transitAspects,
  textColor = "currentColor", mutedColor = "#8e8e93", gridColor = "rgba(128,128,128,0.18)",
}: Props) {
  const byId = new Map(positions.map((p) => [p.id, p]))

  const natalMap = new Map<string, string>()
  for (const a of natalAspects) {
    natalMap.set(`${a.p1}|${a.p2}`, a.aspect)
    natalMap.set(`${a.p2}|${a.p1}`, a.aspect)
  }

  const transitMap = new Map<string, string>()
  if (transitAspects) {
    for (const a of transitAspects) {
      if (!a.is_within_orb) continue
      transitMap.set(`${a.transit_object}|${a.natal_object}`, a.aspect)
    }
  }

  const transitById = new Map((transitPositions ?? []).map((p) => [p.id, p]))
  const cols = PLANET_ORDER.filter((id) => byId.has(id))
  const isTransit = mode === "transit" && transitPositions && transitPositions.length > 0
  const rows = isTransit ? PLANET_ORDER.filter((id) => transitById.has(id)) : cols
  const aspMap = isTransit ? transitMap : natalMap

  if (cols.length < 2) return null

  // SVG grid dimensions — generous sizes for clarity
  const C = 28        // cell size
  const INFO_W = 155  // left info section width
  const LABEL_H = C
  const nCols = cols.length
  const nRows = rows.length
  const totalW = INFO_W + nCols * C + C
  const totalH = nRows * C + LABEL_H

  const fmtDeg = (deg: number, min: number) => `${deg}°${String(min).padStart(2, "0")}′`

  return (
    <svg
      viewBox={`0 0 ${totalW} ${totalH}`}
      width="100%"
      style={{ display: "block" }}
      xmlns="http://www.w3.org/2000/svg"
    >
      <style>{`
        .cs-t { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; }
      `}</style>

      {rows.map((rowP, ri) => {
        const y = ri * C
        const pos = isTransit ? transitById.get(rowP) : byId.get(rowP)
        if (!pos) return null
        const sign = pos.sign
        const elColor = EC[EL[sign] ?? ""] ?? "#888"
        const deg = pos.degree
        const min = pos.minute
        const house = "house" in pos ? (pos as NatalPosition).house : ("natal_house" in pos ? (pos as TransitPosition).natal_house : 0)

        return (
          <g key={rowP}>
            {/* Planet glyph */}
            <text x={3} y={y + C * 0.7} className="cs-t" fontSize={13} fill={textColor} fontWeight={600}>
              {G[rowP] ?? ""}
            </text>
            {/* Name */}
            <text x={22} y={y + C * 0.7} className="cs-t" fontSize={10} fill={textColor} fontWeight={500}>
              {SN[rowP] ?? rowP}
            </text>
            {/* Sign glyph */}
            <text x={82} y={y + C * 0.7} className="cs-t" fontSize={12} fill={elColor}>
              {SG[sign] ?? ""}
            </text>
            {/* Degree */}
            <text x={98} y={y + C * 0.7} className="cs-t" fontSize={9.5} fill={mutedColor}>
              {fmtDeg(deg, min)}
            </text>
            {/* House */}
            <text x={143} y={y + C * 0.7} className="cs-t" fontSize={9.5} fill={mutedColor} textAnchor="middle">
              {house || "—"}
            </text>

            {/* Aspect cells */}
            {cols.map((colP, ci) => {
              const cx = INFO_W + ci * C
              const asp = aspMap.get(`${rowP}|${colP}`)
              const isDiag = rowP === colP && !isTransit
              return (
                <g key={colP}>
                  <rect x={cx} y={y} width={C} height={C} fill={isDiag ? gridColor : "none"} stroke={gridColor} strokeWidth={0.5} />
                  {asp ? (
                    <text
                      x={cx + C / 2} y={y + C * 0.72}
                      className="cs-t" fontSize={12} fill={AC[asp] ?? "#888"}
                      textAnchor="middle" fontWeight={500}
                    >
                      {AG[asp] ?? ""}
                    </text>
                  ) : isDiag ? (
                    <text
                      x={cx + C / 2} y={y + C * 0.72}
                      className="cs-t" fontSize={11} fill={textColor}
                      textAnchor="middle" fontWeight={700}
                    >
                      {G[rowP] ?? ""}
                    </text>
                  ) : null}
                </g>
              )
            })}

            {/* Right label */}
            <text
              x={INFO_W + nCols * C + C / 2} y={y + C * 0.7}
              className="cs-t" fontSize={11} fill={textColor}
              textAnchor="middle" fontWeight={600}
            >
              {G[rowP] ?? ""}
            </text>
          </g>
        )
      })}

      {/* Bottom column labels */}
      {cols.map((p, ci) => (
        <text
          key={p}
          x={INFO_W + ci * C + C / 2}
          y={nRows * C + LABEL_H * 0.78}
          className="cs-t" fontSize={10} fill={textColor}
          textAnchor="middle" fontWeight={600}
        >
          {G[p] ?? ""}
        </text>
      ))}
    </svg>
  )
}
