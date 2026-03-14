import { useId, useState } from "react"

type PlanetMarker = {
  id: string
  longitude: number
  glyph: string
}

type TransitAspect = {
  transit_object: string
  natal_object: string
  aspect: string
  orb: number
  strength: string
}

type NatalZodiacRingProps = {
  asc: number | null
  mc?: number | null
  houses?: Array<number | string> | null
  planets?: PlanetMarker[] | null
  transitPlanets?: PlanetMarker[] | null
  transitAspects?: TransitAspect[] | null
  size?: number
  theme?: "dark" | "light"
  className?: string
}

type Point = {
  x: number
  y: number
}

const PLANETS = new Set([
  "Sun", "Moon", "Mercury", "Venus", "Mars",
  "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto",
])

const SIGNS = [
  "ARIES",
  "TAURUS",
  "GEMINI",
  "CANCER",
  "LEO",
  "VIRGO",
  "LIBRA",
  "SCORPIO",
  "SAGITTARIUS",
  "CAPRICORN",
  "AQUARIUS",
  "PISCES",
] as const

function polar(center: number, radius: number, angle: number): Point {
  const radians = (angle * Math.PI) / 180
  return {
    x: center + radius * Math.cos(radians),
    y: center - radius * Math.sin(radians),
  }
}

function sectorPath(center: number, innerRadius: number, outerRadius: number, startAngle: number, endAngle: number): string {
  const outerStart = polar(center, outerRadius, startAngle)
  const outerEnd = polar(center, outerRadius, endAngle)
  const innerStart = polar(center, innerRadius, startAngle)
  const innerEnd = polar(center, innerRadius, endAngle)
  const delta = ((endAngle - startAngle) + 360) % 360
  const largeArcFlag = delta > 180 ? 1 : 0

  return [
    `M ${outerStart.x.toFixed(3)} ${outerStart.y.toFixed(3)}`,
    `A ${outerRadius} ${outerRadius} 0 ${largeArcFlag} 0 ${outerEnd.x.toFixed(3)} ${outerEnd.y.toFixed(3)}`,
    `L ${innerEnd.x.toFixed(3)} ${innerEnd.y.toFixed(3)}`,
    `A ${innerRadius} ${innerRadius} 0 ${largeArcFlag} 1 ${innerStart.x.toFixed(3)} ${innerStart.y.toFixed(3)}`,
    "Z",
  ].join(" ")
}

function zodiacAngle(zodiacLongitude: number, asc: number): number {
  return (180 + zodiacLongitude - asc + 360) % 360
}

function ringClassName(theme: "dark" | "light", className?: string): string {
  return ["natal-zodiac-ring", `natal-zodiac-ring--${theme}`, className].filter(Boolean).join(" ")
}

function midpointLongitude(start: number, end: number): number {
  const delta = ((end - start) + 360) % 360
  return (start + delta / 2) % 360
}

function labelArcPath(center: number, radius: number, startAngle: number, endAngle: number, reverse: boolean): string {
  const fromAngle = reverse ? endAngle : startAngle
  const toAngle = reverse ? startAngle : endAngle
  const fromPoint = polar(center, radius, fromAngle)
  const toPoint = polar(center, radius, toAngle)
  const sweepFlag = reverse ? 1 : 0

  return [
    `M ${fromPoint.x.toFixed(3)} ${fromPoint.y.toFixed(3)}`,
    `A ${radius} ${radius} 0 0 ${sweepFlag} ${toPoint.x.toFixed(3)} ${toPoint.y.toFixed(3)}`,
  ].join(" ")
}

function normalizeLongitude(longitude: number): number {
  return ((longitude % 360) + 360) % 360
}

function radialUnit(angle: number): Point {
  const radians = (angle * Math.PI) / 180
  return {
    x: Math.cos(radians),
    y: -Math.sin(radians),
  }
}

function tangentUnit(angle: number): Point {
  const radians = (angle * Math.PI) / 180
  return {
    x: Math.sin(radians),
    y: Math.cos(radians),
  }
}

/** Spread markers apart so they don't overlap on the band arc */
function spreadGlyphs(
  markers: Array<{ id: string; longitude: number; glyph: string }>,
  ascLongitude: number,
  radius: number,
  glyphSize: number,
): Array<{ id: string; glyph: string; longitude: number; displayAngle: number }> {
  if (markers.length === 0) return []

  const gap = 1.4 // 0.7px padding on each side
  const glyphW = glyphSize * 0.7 + gap // approximate glyph width
  const glyphH = glyphSize * 1.0 + gap // approximate glyph height
  const degPerRad = 180 / Math.PI

  // Minimum angular separation depends on position on circle:
  // at top/bottom (0°/180°) separation is horizontal → use width
  // at left/right (90°/270°) separation is vertical → use height
  function pairSep(midAngle: number): number {
    const rad = midAngle * Math.PI / 180
    const cosA = Math.abs(Math.cos(rad))
    const sinA = Math.abs(Math.sin(rad))
    let sep = Infinity
    if (cosA > 0.01) sep = Math.min(sep, (glyphW / (radius * cosA)) * degPerRad)
    if (sinA > 0.01) sep = Math.min(sep, (glyphH / (radius * sinA)) * degPerRad)
    return Math.min(sep, (glyphH / radius) * degPerRad) // cap at height-based max
  }

  const items = markers
    .map((m) => ({
      id: m.id,
      glyph: m.glyph,
      longitude: m.longitude,
      displayAngle: zodiacAngle(m.longitude, ascLongitude),
      originalAngle: zodiacAngle(m.longitude, ascLongitude),
    }))
    .sort((a, b) => a.displayAngle - b.displayAngle)

  // Step 1: push overlapping pairs apart
  for (let pass = 0; pass < 20; pass++) {
    let moved = false
    for (let i = 0; i < items.length; i++) {
      const curr = items[i]!
      const next = items[(i + 1) % items.length]!
      const midAngle = (curr.displayAngle + next.displayAngle) / 2
      const minSep = pairSep(midAngle)
      let sepGap = ((next.displayAngle - curr.displayAngle) + 360) % 360
      if (sepGap > 180) sepGap -= 360
      if (Math.abs(sepGap) < minSep && Math.abs(sepGap) < 180) {
        const push = (minSep - Math.abs(sepGap)) / 2 + 0.05
        const sign = sepGap >= 0 ? 1 : -1
        curr.displayAngle = (curr.displayAngle - sign * push + 360) % 360
        next.displayAngle = (next.displayAngle + sign * push + 360) % 360
        moved = true
      }
    }
    if (!moved) break
  }

  // Step 2: snap each glyph back to its true angle if space allows
  const byDrift = items
    .map((it, i) => ({ idx: i, drift: Math.abs(((it.originalAngle - it.displayAngle) + 540) % 360 - 180) }))
    .sort((a, b) => b.drift - a.drift)

  for (const { idx } of byDrift) {
    const curr = items[idx]!
    if (items.length <= 1) {
      curr.displayAngle = curr.originalAngle
      continue
    }

    const prev = items[(idx - 1 + items.length) % items.length]!
    const next = items[(idx + 1) % items.length]!

    const distPrev = ((curr.originalAngle - prev.displayAngle) + 360) % 360
    const distNext = ((next.displayAngle - curr.originalAngle) + 360) % 360

    const sepPrev = pairSep((curr.originalAngle + prev.displayAngle) / 2)
    const sepNext = pairSep((curr.originalAngle + next.displayAngle) / 2)

    const prevOk = distPrev >= sepPrev || distPrev > 180
    const nextOk = distNext >= sepNext || distNext > 180

    if (prevOk && nextOk) {
      curr.displayAngle = curr.originalAngle
    }
  }

  return items
}

function coerceHouseValues(houses: Array<number | string> | null | undefined): number[] {
  if (!Array.isArray(houses)) return []

  return houses
    .map((value) => {
      if (typeof value === "number" && Number.isFinite(value)) return value
      if (typeof value === "string") {
        const numeric = Number(value)
        return Number.isFinite(numeric) ? numeric : null
      }
      return null
    })
    .filter((value): value is number => value !== null)
}

const ASPECT_LINE_STYLES: Record<string, { dash: string; width: number; opacity: number; color: string }> = {
  conjunction: { dash: "none", width: 0.5, opacity: 1, color: "#e74c3c" },
  opposition: { dash: "6,3", width: 0.5, opacity: 0.9, color: "#e74c3c" },
  square: { dash: "2,3", width: 0.5, opacity: 0.9, color: "#e67e22" },
  trine: { dash: "8,4", width: 0.5, opacity: 0.85, color: "#2980b9" },
  sextile: { dash: "1.5,3", width: 0.5, opacity: 0.8, color: "#27ae60" },
}

export function NatalZodiacRing({
  asc,
  mc,
  houses,
  planets,
  transitPlanets,
  transitAspects,
  size = 360,
  theme = "light",
  className,
}: NatalZodiacRingProps) {
  const idBase = useId().replace(/:/g, "")
  const [tooltip, setTooltip] = useState<{ label: string; x: number; y: number } | null>(null)
  const ringSize = Math.max(size, 240)
  const outerPadding = Math.max(ringSize * 0.07, 30)
  const center = ringSize / 2
  const zodiacOuterRadius = center - outerPadding
  const zodiacBandWidth = Math.max(ringSize * 0.046, 18)
  const zodiacInnerRadius = zodiacOuterRadius - zodiacBandWidth
  const outerSpacer = Math.max(ringSize * 0.03, 12)    // zodiac → natal
  const innerGap = Math.max(ringSize * 0.012, 5)        // between pair bands (small)
  const pairSpacer = Math.max(ringSize * 0.03, 12)      // natal → transit (same as house numbers gap)
  const subBandWidth = Math.max(ringSize * 0.046, 18)
  const zodiacLabelRadius = (zodiacOuterRadius + zodiacInnerRadius) / 2
  const houseLabelRadius = zodiacInnerRadius - outerSpacer / 2

  // 4 independent bands
  // Natal upper band (planets)
  const upperBandOuter = zodiacInnerRadius - outerSpacer
  const upperBandInner = upperBandOuter - subBandWidth
  const upperBandMid = (upperBandOuter + upperBandInner) / 2
  const upperBandStroke = subBandWidth

  // Natal lower band (special points) — small gap from upper
  const lowerBandOuter = upperBandInner - innerGap
  const lowerBandInner = lowerBandOuter - subBandWidth
  const lowerBandMid = (lowerBandOuter + lowerBandInner) / 2
  const lowerBandStroke = subBandWidth

  // Compat aliases used by house dividers / outlines
  const houseOuterRadius = upperBandOuter
  const houseInnerRadius = lowerBandInner

  // Transit upper band (planets) — large gap from natal
  const tUpperBandOuter = lowerBandInner - pairSpacer
  const tUpperBandInner = tUpperBandOuter - subBandWidth
  const tUpperBandMid = (tUpperBandOuter + tUpperBandInner) / 2
  const tUpperBandStroke = subBandWidth

  // Transit lower band (special points) — small gap from upper
  const tLowerBandOuter = tUpperBandInner - innerGap
  const tLowerBandInner = tLowerBandOuter - subBandWidth
  const tLowerBandMid = (tLowerBandOuter + tLowerBandInner) / 2
  const tLowerBandStroke = subBandWidth

  const transitOuterRadius = tUpperBandOuter
  const transitInnerRadius = tLowerBandInner
  const centerRadius = transitInnerRadius

  // Axis marker geometry — arrows span zodiac band only
  const axisLineInner = zodiacInnerRadius
  const axisLineOuter = zodiacOuterRadius
  const axisArrowLen = Math.max(ringSize * 0.015, 5)
  const axisArrowWing = axisArrowLen
  const axisLabelOffset = Math.max(ringSize * 0.016, 7)

  // Planet marker geometry — planets on upper band, special points on lower band
  const planetTickOuter = zodiacInnerRadius
  const planetTickInner = houseInnerRadius - Math.max(ringSize * 0.006, 2)
  const planetGlyphSize = Math.max(ringSize * 0.032, 13)
  const planetRowOuter = upperBandMid
  const planetRowInner = lowerBandMid

  // Transit marker geometry
  const transitGlyphSize = Math.max(ringSize * 0.028, 12)
  const transitTickInner = transitInnerRadius - Math.max(ringSize * 0.006, 2)

  const viewBox = `0 0 ${ringSize} ${ringSize}`
  const houseValues = coerceHouseValues(houses)
  const planetMarkers = (planets ?? []).filter(
    (p) => p.id !== "ASC" && p.id !== "MC" && Number.isFinite(p.longitude),
  )
  const transitMarkers = (transitPlanets ?? []).filter(
    (p) => p.id !== "ASC" && p.id !== "MC" && Number.isFinite(p.longitude),
  )

  if (!Number.isFinite(asc)) {
    return (
      <div className="ring-fallback">
        <strong>Natal ring unavailable</strong>
        <span>ASC is missing for the active profile.</span>
      </div>
    )
  }

  const ascLongitude = asc
  const mcLongitude = Number.isFinite(mc) ? mc : null
  const dcLongitude = normalizeLongitude(ascLongitude + 180)
  const icLongitude = mcLongitude !== null ? normalizeLongitude(mcLongitude + 180) : null

  // Planets go on outer row, special points on inner row
  function isPlanet(id: string): boolean {
    return PLANETS.has(id)
  }

  // Full-span axis arrow from house inner edge to zodiac outer edge
  // Chevron tip sits exactly at zodiacOuterRadius, wings angle inward
  function axisArrow(longitude: number) {
    const angle = zodiacAngle(longitude, ascLongitude)
    const inner = polar(center, axisLineInner, angle)
    const tip = polar(center, axisLineOuter, angle)
    const tangent = tangentUnit(angle)
    const wingBase = polar(center, axisLineOuter - axisArrowLen, angle)
    return {
      angle,
      innerPoint: inner,
      tip,
      leftWing: {
        x: wingBase.x + tangent.x * axisArrowWing,
        y: wingBase.y + tangent.y * axisArrowWing,
      },
      rightWing: {
        x: wingBase.x - tangent.x * axisArrowWing,
        y: wingBase.y - tangent.y * axisArrowWing,
      },
    }
  }

  function axisLabelPoint(longitude: number) {
    const angle = zodiacAngle(longitude, ascLongitude)
    return polar(center, zodiacOuterRadius + axisLabelOffset, angle)
  }

  const ascMarker = axisArrow(ascLongitude)
  const mcMarker = mcLongitude !== null ? axisArrow(mcLongitude) : null
  const dcMarker = axisArrow(dcLongitude)
  const icMarker = icLongitude !== null ? axisArrow(icLongitude) : null

  return (
    <svg
      className={ringClassName(theme, className)}
      viewBox={viewBox}
      role="img"
      aria-label="Natal zodiac ring"
    >
      <defs>
        <clipPath id={`${idBase}-zodiac-band-clip`}>
          <path d={sectorPath(center, zodiacInnerRadius, zodiacOuterRadius, 0, 359.999)} />
        </clipPath>

        <clipPath id={`${idBase}-house-band-clip`}>
          <path d={sectorPath(center, houseInnerRadius, houseOuterRadius, 0, 359.999)} />
        </clipPath>

        {SIGNS.map((sign, index) => {
          const startLongitude = index * 30 + 3
          const endLongitude = (index + 1) * 30 - 3
          const labelAngle = zodiacAngle(index * 30 + 15, ascLongitude)
          const reverse = labelAngle > 0 && labelAngle < 180

          return (
            <path
              key={`${sign}-path`}
              id={`${idBase}-${sign.toLowerCase()}-label-path`}
              d={labelArcPath(
                center,
                zodiacLabelRadius,
                zodiacAngle(startLongitude, ascLongitude),
                zodiacAngle(endLongitude, ascLongitude),
                reverse,
              )}
            />
          )
        })}

        {houseValues.map((houseLongitude, index) => {
          const nextHouseLongitude = houseValues[(index + 1) % houseValues.length]
          if (nextHouseLongitude === undefined) return null
          const midLng = midpointLongitude(houseLongitude, nextHouseLongitude)
          const midAngle = zodiacAngle(midLng, ascLongitude)
          const reverse = midAngle > 0 && midAngle < 180
          const pad = 5
          const startLng = normalizeLongitude(houseLongitude + pad)
          const endLng = normalizeLongitude(nextHouseLongitude - pad)

          return (
            <path
              key={`house-path-${index}`}
              id={`${idBase}-house-label-path-${index}`}
              d={labelArcPath(
                center,
                houseLabelRadius,
                zodiacAngle(startLng, ascLongitude),
                zodiacAngle(endLng, ascLongitude),
                reverse,
              )}
            />
          )
        })}
      </defs>

      <circle className="natal-zodiac-ring__backdrop" cx={center} cy={center} r={zodiacOuterRadius} />
      <circle className="natal-zodiac-ring__outline" cx={center} cy={center} r={zodiacOuterRadius} />
      <circle className="natal-zodiac-ring__outline" cx={center} cy={center} r={zodiacInnerRadius} />

      {/* Upper band (planets) */}
      <circle
        className="natal-zodiac-ring__house-band"
        cx={center}
        cy={center}
        r={upperBandMid}
        strokeWidth={upperBandStroke}
      />
      {/* Lower band (special points) */}
      <circle
        className="natal-zodiac-ring__house-band"
        cx={center}
        cy={center}
        r={lowerBandMid}
        strokeWidth={lowerBandStroke}
      />
      <circle className="natal-zodiac-ring__center" cx={center} cy={center} r={centerRadius} />

      {/* Natal per-band notches — ticks on both outer and inner edges of each band */}
      {planetMarkers.map((planet) => {
        const angle = zodiacAngle(planet.longitude, ascLongitude)
        const notchLen = Math.max(ringSize * 0.006, 2)
        const isP = isPlanet(planet.id)
        const bandOuter = isP ? upperBandOuter : lowerBandOuter
        const bandInner = isP ? upperBandInner : lowerBandInner
        const oFrom = polar(center, bandOuter, angle)
        const oTo = polar(center, bandOuter + notchLen, angle)
        const iFrom = polar(center, bandInner, angle)
        const iTo = polar(center, bandInner - notchLen, angle)
        return (
          <g key={`planet-tick-${planet.id}`}>
            <line className="natal-zodiac-ring__planet-tick"
              x1={oFrom.x} y1={oFrom.y} x2={oTo.x} y2={oTo.y} />
            <line className="natal-zodiac-ring__planet-tick"
              x1={iFrom.x} y1={iFrom.y} x2={iTo.x} y2={iTo.y} />
          </g>
        )
      })}

      {SIGNS.map((sign, index) => {
        const startLongitude = index * 30
        const endLongitude = startLongitude + 30
        const startAngle = zodiacAngle(startLongitude, ascLongitude)
        const endAngle = zodiacAngle(endLongitude, ascLongitude)

        return (
          <g key={sign}>
            <path
              className="natal-zodiac-ring__sector"
              d={sectorPath(center, zodiacInnerRadius, zodiacOuterRadius, startAngle, endAngle)}
            />
            <text className="natal-zodiac-ring__label">
              <textPath
                href={`#${idBase}-${sign.toLowerCase()}-label-path`}
                startOffset="50%"
                textAnchor="middle"
              >
                {sign}
              </textPath>
            </text>
          </g>
        )
      })}

      <g clipPath={`url(#${idBase}-zodiac-band-clip)`}>
        {SIGNS.map((_, index) => {
          const angle = zodiacAngle(index * 30, ascLongitude)
          const outerPoint = polar(center, zodiacOuterRadius, angle)
          const innerPoint = polar(center, zodiacInnerRadius, angle)

          return (
            <line
              key={`zodiac-divider-${index}`}
              className="natal-zodiac-ring__zodiac-divider"
              x1={outerPoint.x}
              y1={outerPoint.y}
              x2={innerPoint.x}
              y2={innerPoint.y}
            />
          )
        })}
      </g>

      {/* House dividers — two segments per divider, skipping the gap */}
      <g clipPath={`url(#${idBase}-house-band-clip)`}>
        {houseValues.map((houseLongitude, index) => {
          const angle = zodiacAngle(houseLongitude, ascLongitude)
          const upperOuter = polar(center, upperBandOuter, angle)
          const upperInner = polar(center, upperBandInner, angle)
          const lowerOuter = polar(center, lowerBandOuter, angle)
          const lowerInner = polar(center, lowerBandInner, angle)

          return (
            <g key={`${index}-${houseLongitude}`}>
              <line
                className="natal-zodiac-ring__house-divider"
                x1={upperOuter.x} y1={upperOuter.y}
                x2={upperInner.x} y2={upperInner.y}
              />
              <line
                className="natal-zodiac-ring__house-divider"
                x1={lowerOuter.x} y1={lowerOuter.y}
                x2={lowerInner.x} y2={lowerInner.y}
              />
            </g>
          )
        })}
      </g>

      <circle className="natal-zodiac-ring__house-outline" cx={center} cy={center} r={houseOuterRadius} />
      <circle className="natal-zodiac-ring__house-outline" cx={center} cy={center} r={upperBandInner} />
      <circle className="natal-zodiac-ring__house-outline" cx={center} cy={center} r={lowerBandOuter} />
      <circle className="natal-zodiac-ring__house-outline" cx={center} cy={center} r={houseInnerRadius} />

      {/* Transit bands */}
      {transitMarkers.length > 0 && (
        <>
          {/* Upper transit band (planets) */}
          <circle className="natal-zodiac-ring__transit-band"
            cx={center} cy={center} r={tUpperBandMid} strokeWidth={tUpperBandStroke} />
          {/* Lower transit band (special points) */}
          <circle className="natal-zodiac-ring__transit-band"
            cx={center} cy={center} r={tLowerBandMid} strokeWidth={tLowerBandStroke} />

          {/* Transit per-band notches — ticks on both outer and inner edges of each band,
               plus aspect-anchor tick at tUpperBandOuter for lower-band objects */}
          {transitMarkers.map((planet) => {
            const angle = zodiacAngle(planet.longitude, ascLongitude)
            const notchLen = Math.max(ringSize * 0.006, 2)
            const isP = isPlanet(planet.id)
            const bandOuter = isP ? tUpperBandOuter : tLowerBandOuter
            const bandInner = isP ? tUpperBandInner : tLowerBandInner
            // Outer edge tick
            const oFrom = polar(center, bandOuter, angle)
            const oTo = polar(center, bandOuter + notchLen, angle)
            // Inner edge tick
            const iFrom = polar(center, bandInner, angle)
            const iTo = polar(center, bandInner - notchLen, angle)
            return (
              <g key={`transit-tick-${planet.id}`}>
                <line className="natal-zodiac-ring__planet-tick"
                  x1={oFrom.x} y1={oFrom.y} x2={oTo.x} y2={oTo.y} />
                <line className="natal-zodiac-ring__planet-tick"
                  x1={iFrom.x} y1={iFrom.y} x2={iTo.x} y2={iTo.y} />
              </g>
            )
          })}

          {/* Transit band outlines */}
          <circle className="natal-zodiac-ring__house-outline" cx={center} cy={center} r={transitOuterRadius} />
          <circle className="natal-zodiac-ring__house-outline" cx={center} cy={center} r={tUpperBandInner} />
          <circle className="natal-zodiac-ring__house-outline" cx={center} cy={center} r={tLowerBandOuter} />
          <circle className="natal-zodiac-ring__house-outline" cx={center} cy={center} r={transitInnerRadius} />

          {/* Transit house dividers — two segments */}
          {houseValues.map((houseLongitude, index) => {
            const angle = zodiacAngle(houseLongitude, ascLongitude)
            const tuO = polar(center, tUpperBandOuter, angle)
            const tuI = polar(center, tUpperBandInner, angle)
            const tlO = polar(center, tLowerBandOuter, angle)
            const tlI = polar(center, tLowerBandInner, angle)
            return (
              <g key={`transit-div-${index}`}>
                <line className="natal-zodiac-ring__house-divider" x1={tuO.x} y1={tuO.y} x2={tuI.x} y2={tuI.y} />
                <line className="natal-zodiac-ring__house-divider" x1={tlO.x} y1={tlO.y} x2={tlI.x} y2={tlI.y} />
              </g>
            )
          })}

          {/* Transit axis dividers */}
          {[ascLongitude, dcLongitude, mcLongitude, icLongitude]
            .filter((lng): lng is number => lng !== null)
            .map((lng) => {
              const angle = zodiacAngle(lng, ascLongitude)
              const tuO = polar(center, tUpperBandOuter, angle)
              const tuI = polar(center, tUpperBandInner, angle)
              const tlO = polar(center, tLowerBandOuter, angle)
              const tlI = polar(center, tLowerBandInner, angle)
              return (
                <g key={`transit-axis-${lng}`}>
                  <line className="natal-zodiac-ring__house-divider" x1={tuO.x} y1={tuO.y} x2={tuI.x} y2={tuI.y} />
                  <line className="natal-zodiac-ring__house-divider" x1={tlO.x} y1={tlO.y} x2={tlI.x} y2={tlI.y} />
                </g>
              )
            })}

          {/* Transit planet glyphs — spread to avoid overlaps */}
          {(() => {
            const outerGroup = transitMarkers.filter((p) => isPlanet(p.id))
            const innerGroup = transitMarkers.filter((p) => !isPlanet(p.id))
            const spreadOuter = spreadGlyphs(outerGroup, ascLongitude, tUpperBandMid, transitGlyphSize)
            const spreadInner = spreadGlyphs(innerGroup, ascLongitude, tLowerBandMid, transitGlyphSize)
            return [...spreadOuter.map((p) => ({ ...p, radius: tUpperBandMid })),
                    ...spreadInner.map((p) => ({ ...p, radius: tLowerBandMid }))]
              .map((planet) => {
                const glyphPoint = polar(center, planet.radius, planet.displayAngle)
                return (
                  <g
                    key={`transit-glyph-${planet.id}`}
                    className="natal-zodiac-ring__glyph-hover"
                    onMouseEnter={() => setTooltip({ label: `${planet.id} (transit)`, x: glyphPoint.x, y: glyphPoint.y })}
                    onMouseLeave={() => setTooltip(null)}
                  >
                    <text
                      className="natal-zodiac-ring__transit-glyph"
                      x={glyphPoint.x}
                      y={glyphPoint.y}
                      dy="0.1em"
                      textAnchor="middle"
                      dominantBaseline="central"
                      fontSize={transitGlyphSize}
                    >
                      {planet.glyph}
                    </text>
                  </g>
                )
              })
          })()}
        </>
      )}

      {houseValues.map((_, index) => {
        return (
          <text
            key={`house-label-${index + 1}`}
            className="natal-zodiac-ring__house-label"
            dominantBaseline="central"
          >
            <textPath
              href={`#${idBase}-house-label-path-${index}`}
              startOffset="50%"
              textAnchor="middle"
            >
              {index + 1}
            </textPath>
          </text>
        )
      })}

      {/* Soft axis lines through house bands — simple gray dividers */}
      {[ascLongitude, dcLongitude, mcLongitude, icLongitude]
        .filter((lng): lng is number => lng !== null)
        .map((lng) => {
          const angle = zodiacAngle(lng, ascLongitude)
          const uo = polar(center, upperBandOuter, angle)
          const ui = polar(center, upperBandInner, angle)
          const lo = polar(center, lowerBandOuter, angle)
          const li = polar(center, lowerBandInner, angle)
          return (
            <g key={`axis-house-${lng}`}>
              <line className="natal-zodiac-ring__house-divider" x1={uo.x} y1={uo.y} x2={ui.x} y2={ui.y} />
              <line className="natal-zodiac-ring__house-divider" x1={lo.x} y1={lo.y} x2={li.x} y2={li.y} />
            </g>
          )
        })}

      {/* Planet glyphs — spread to avoid overlaps, centered on band mid-line */}
      {(() => {
        const outerGroup = planetMarkers.filter((p) => isPlanet(p.id))
        const innerGroup = planetMarkers.filter((p) => !isPlanet(p.id))
        const spreadOuter = spreadGlyphs(outerGroup, ascLongitude, planetRowOuter, planetGlyphSize)
        const spreadInner = spreadGlyphs(innerGroup, ascLongitude, planetRowInner, planetGlyphSize)
        return [...spreadOuter.map((p) => ({ ...p, radius: planetRowOuter })),
                ...spreadInner.map((p) => ({ ...p, radius: planetRowInner }))]
          .map((planet) => {
            const glyphPoint = polar(center, planet.radius, planet.displayAngle)
            return (
              <g
                key={`planet-glyph-${planet.id}`}
                className="natal-zodiac-ring__glyph-hover"
                onMouseEnter={() => setTooltip({ label: planet.id, x: glyphPoint.x, y: glyphPoint.y })}
                onMouseLeave={() => setTooltip(null)}
              >
                <text
                  className="natal-zodiac-ring__planet-glyph"
                  x={glyphPoint.x}
                  y={glyphPoint.y}
                  dy="0.1em"
                  textAnchor="middle"
                  dominantBaseline="central"
                  fontSize={planetGlyphSize}
                >
                  {planet.glyph}
                </text>
              </g>
            )
          })
      })()}

      {/* Axis lines + labels — rendered last so they appear on top of all ring layers */}
      {[
        { marker: ascMarker, longitude: ascLongitude, label: "AC", hasArrow: true },
        { marker: dcMarker, longitude: dcLongitude, label: "DC", hasArrow: false },
        { marker: mcMarker, longitude: mcLongitude, label: "MC", hasArrow: true },
        { marker: icMarker, longitude: icLongitude, label: "IC", hasArrow: false },
      ].map(({ marker, longitude, label, hasArrow }) => {
        if (!marker || longitude === null) return null
        const lp = axisLabelPoint(longitude)
        return (
          <g key={label}>
            <line
              className="natal-zodiac-ring__axis-line"
              x1={marker.innerPoint.x}
              y1={marker.innerPoint.y}
              x2={marker.tip.x}
              y2={marker.tip.y}
            />
            {hasArrow ? (
              <polyline
                className="natal-zodiac-ring__axis-chevron"
                points={`${marker.leftWing.x},${marker.leftWing.y} ${marker.tip.x},${marker.tip.y} ${marker.rightWing.x},${marker.rightWing.y}`}
              />
            ) : null}
            <text
              className="natal-zodiac-ring__axis-label-outer"
              x={lp.x}
              y={lp.y}
              textAnchor="middle"
              dominantBaseline="middle"
            >
              {label}
            </text>
          </g>
        )
      })}
      {/* Transit-to-natal aspect lines — on top of all layers */}
      {transitAspects && transitAspects.length > 0 && (() => {
        const natalLongitudes = new Map(planetMarkers.map((p) => [p.id, p.longitude]))
        const natalIsPlanet = new Map(planetMarkers.map((p) => [p.id, isPlanet(p.id)]))
        const transitLongitudes = new Map(transitMarkers.map((p) => [p.id, p.longitude]))
        const transitIsPlanet = new Map(transitMarkers.map((p) => [p.id, isPlanet(p.id)]))
        const notchLen = Math.max(ringSize * 0.006, 2)
        return transitAspects
          .filter((a) => natalLongitudes.has(a.natal_object) && transitLongitudes.has(a.transit_object))
          .map((a, i) => {
            const natalAngle = zodiacAngle(natalLongitudes.get(a.natal_object)!, ascLongitude)
            const transitAngle = zodiacAngle(transitLongitudes.get(a.transit_object)!, ascLongitude)
            // Natal side: inner tick tip of the object's own band
            const natalBandInner = natalIsPlanet.get(a.natal_object) ? upperBandInner : lowerBandInner
            // Transit side: outer tick tip of the object's own band
            const transitBandOuter = transitIsPlanet.get(a.transit_object) ? tUpperBandOuter : tLowerBandOuter
            const p1 = polar(center, natalBandInner - notchLen, natalAngle)
            const p2 = polar(center, transitBandOuter + notchLen, transitAngle)
            const style = ASPECT_LINE_STYLES[a.aspect] ?? ASPECT_LINE_STYLES.sextile!
            return (
              <line
                key={`aspect-${a.transit_object}-${a.natal_object}-${i}`}
                className="natal-zodiac-ring__aspect-line"
                x1={p1.x} y1={p1.y} x2={p2.x} y2={p2.y}
                stroke={style.color}
                strokeDasharray={style.dash}
                strokeWidth={style.width}
                opacity={style.opacity}
              />
            )
          })
      })()}
      {tooltip && (
        <g className="natal-zodiac-ring__tooltip" pointerEvents="none">
          <rect
            x={tooltip.x - 30}
            y={tooltip.y - planetGlyphSize - 14}
            width={Math.max(tooltip.label.length * 6.5, 40)}
            height={16}
            rx={3}
            fill="rgba(0,0,0,0.8)"
          />
          <text
            x={tooltip.x - 30 + Math.max(tooltip.label.length * 6.5, 40) / 2}
            y={tooltip.y - planetGlyphSize - 6}
            textAnchor="middle"
            dominantBaseline="central"
            fill="#fff"
            fontSize={10}
            fontFamily="system-ui, sans-serif"
            fontWeight={400}
          >
            {tooltip.label}
          </text>
        </g>
      )}
    </svg>
  )
}
