import { useId } from "react"

type NatalZodiacRingProps = {
  asc: number | null
  mc?: number | null
  houses?: Array<number | string> | null
  size?: number
  theme?: "dark" | "light"
  className?: string
}

type Point = {
  x: number
  y: number
}

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

export function NatalZodiacRing({
  asc,
  mc,
  houses,
  size = 360,
  theme = "light",
  className,
}: NatalZodiacRingProps) {
  const idBase = useId().replace(/:/g, "")
  const ringSize = Math.max(size, 240)
  const center = ringSize / 2
  const zodiacOuterRadius = center - 10
  const zodiacBandWidth = Math.max(ringSize * 0.058, 22)
  const zodiacInnerRadius = zodiacOuterRadius - zodiacBandWidth
  const spacerWidth = Math.max(ringSize * 0.05, 18)
  const houseOuterRadius = zodiacInnerRadius - Math.max(spacerWidth * 0.62, 13)
  const houseBandWidth = Math.max(ringSize * 0.082, 28)
  const houseInnerRadius = houseOuterRadius - houseBandWidth
  const houseMidRadius = (houseOuterRadius + houseInnerRadius) / 2
  const houseLabelRadius = (zodiacInnerRadius + houseOuterRadius) / 2
  const zodiacLabelRadius = (zodiacOuterRadius + zodiacInnerRadius) / 2
  const centerRadius = houseInnerRadius

  // Axis marker geometry — ticks sit inside the house band with a small inset
  const axisTickInner = houseInnerRadius + Math.max(ringSize * 0.012, 4)
  const axisTickOuter = houseOuterRadius - Math.max(ringSize * 0.012, 4)
  const axisArrowLen = Math.max(ringSize * 0.022, 7)
  const axisArrowWing = Math.max(ringSize * 0.011, 3.5)
  const axisLabelOffset = Math.max(ringSize * 0.034, 11)

  const viewBox = `0 0 ${ringSize} ${ringSize}`
  const houseValues = coerceHouseValues(houses)

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

  // Short radial tick for DC / IC
  function axisTick(longitude: number) {
    const angle = zodiacAngle(longitude, ascLongitude)
    return {
      angle,
      outerPoint: polar(center, axisTickOuter, angle),
      innerPoint: polar(center, axisTickInner, angle),
    }
  }

  // Tick + outward-pointing chevron for ASC / MC
  function axisChevron(longitude: number) {
    const angle = zodiacAngle(longitude, ascLongitude)
    const tip = polar(center, axisTickOuter, angle)
    const radial = radialUnit(angle)
    const tangent = tangentUnit(angle)
    return {
      angle,
      outerPoint: tip,
      innerPoint: polar(center, axisTickInner, angle),
      tip,
      leftWing: {
        x: tip.x - radial.x * axisArrowLen + tangent.x * axisArrowWing,
        y: tip.y - radial.y * axisArrowLen + tangent.y * axisArrowWing,
      },
      rightWing: {
        x: tip.x - radial.x * axisArrowLen - tangent.x * axisArrowWing,
        y: tip.y - radial.y * axisArrowLen - tangent.y * axisArrowWing,
      },
    }
  }

  function axisLabelPoint(longitude: number) {
    const angle = zodiacAngle(longitude, ascLongitude)
    return polar(center, houseOuterRadius + axisLabelOffset, angle)
  }

  const ascMarker = axisChevron(ascLongitude)
  const mcMarker = mcLongitude !== null ? axisChevron(mcLongitude) : null
  const dcMarker = axisTick(dcLongitude)
  const icMarker = icLongitude !== null ? axisTick(icLongitude) : null

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
      </defs>

      <circle className="natal-zodiac-ring__backdrop" cx={center} cy={center} r={zodiacOuterRadius} />
      <circle className="natal-zodiac-ring__outline" cx={center} cy={center} r={zodiacOuterRadius} />
      <circle className="natal-zodiac-ring__outline" cx={center} cy={center} r={zodiacInnerRadius} />
      <circle
        className="natal-zodiac-ring__house-band"
        cx={center}
        cy={center}
        r={houseMidRadius}
        strokeWidth={houseBandWidth}
      />
      <circle className="natal-zodiac-ring__center" cx={center} cy={center} r={centerRadius} />

      {/* ASC — tick + chevron + label */}
      <line
        className="natal-zodiac-ring__axis-line"
        x1={ascMarker.outerPoint.x}
        y1={ascMarker.outerPoint.y}
        x2={ascMarker.innerPoint.x}
        y2={ascMarker.innerPoint.y}
      />
      <polyline
        className="natal-zodiac-ring__axis-chevron"
        points={`${ascMarker.leftWing.x},${ascMarker.leftWing.y} ${ascMarker.tip.x},${ascMarker.tip.y} ${ascMarker.rightWing.x},${ascMarker.rightWing.y}`}
      />
      <text
        className="natal-zodiac-ring__axis-label"
        x={axisLabelPoint(ascLongitude).x}
        y={axisLabelPoint(ascLongitude).y}
        textAnchor="middle"
        dominantBaseline="middle"
      >
        ASC
      </text>

      {/* MC — tick + chevron + label */}
      {mcMarker ? (
        <>
          <line
            className="natal-zodiac-ring__axis-line"
            x1={mcMarker.outerPoint.x}
            y1={mcMarker.outerPoint.y}
            x2={mcMarker.innerPoint.x}
            y2={mcMarker.innerPoint.y}
          />
          <polyline
            className="natal-zodiac-ring__axis-chevron"
            points={`${mcMarker.leftWing.x},${mcMarker.leftWing.y} ${mcMarker.tip.x},${mcMarker.tip.y} ${mcMarker.rightWing.x},${mcMarker.rightWing.y}`}
          />
          <text
            className="natal-zodiac-ring__axis-label"
            x={axisLabelPoint(mcLongitude!).x}
            y={axisLabelPoint(mcLongitude!).y}
            textAnchor="middle"
            dominantBaseline="middle"
          >
            MC
          </text>
        </>
      ) : null}

      {/* DC — short tick + label */}
      <line
        className="natal-zodiac-ring__axis-line natal-zodiac-ring__axis-line--minor"
        x1={dcMarker.outerPoint.x}
        y1={dcMarker.outerPoint.y}
        x2={dcMarker.innerPoint.x}
        y2={dcMarker.innerPoint.y}
      />
      <text
        className="natal-zodiac-ring__axis-label natal-zodiac-ring__axis-label--minor"
        x={axisLabelPoint(dcLongitude).x}
        y={axisLabelPoint(dcLongitude).y}
        textAnchor="middle"
        dominantBaseline="middle"
      >
        DC
      </text>

      {/* IC — short tick + label */}
      {icMarker ? (
        <>
          <line
            className="natal-zodiac-ring__axis-line natal-zodiac-ring__axis-line--minor"
            x1={icMarker.outerPoint.x}
            y1={icMarker.outerPoint.y}
            x2={icMarker.innerPoint.x}
            y2={icMarker.innerPoint.y}
          />
          <text
            className="natal-zodiac-ring__axis-label natal-zodiac-ring__axis-label--minor"
            x={axisLabelPoint(icLongitude!).x}
            y={axisLabelPoint(icLongitude!).y}
            textAnchor="middle"
            dominantBaseline="middle"
          >
            IC
          </text>
        </>
      ) : null}

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

      <g clipPath={`url(#${idBase}-house-band-clip)`}>
        {houseValues.map((houseLongitude, index) => {
          const angle = zodiacAngle(houseLongitude, ascLongitude)
          const outerPoint = polar(center, houseOuterRadius, angle)
          const innerPoint = polar(center, houseInnerRadius, angle)

          return (
            <line
              key={`${index}-${houseLongitude}`}
              className="natal-zodiac-ring__house-divider"
              x1={outerPoint.x}
              y1={outerPoint.y}
              x2={innerPoint.x}
              y2={innerPoint.y}
            />
          )
        })}
      </g>

      <circle className="natal-zodiac-ring__house-outline" cx={center} cy={center} r={houseOuterRadius} />
      <circle className="natal-zodiac-ring__house-outline" cx={center} cy={center} r={houseInnerRadius} />

      {houseValues.map((houseLongitude, index) => {
        const nextHouseLongitude = houseValues[(index + 1) % houseValues.length]
        if (nextHouseLongitude === undefined) return null

        const labelAngle = zodiacAngle(midpointLongitude(houseLongitude, nextHouseLongitude), ascLongitude)
        const labelPoint = polar(center, houseLabelRadius, labelAngle)

        return (
          <text
            key={`house-label-${index + 1}`}
            className="natal-zodiac-ring__house-label"
            x={labelPoint.x}
            y={labelPoint.y}
            textAnchor="middle"
            dominantBaseline="middle"
          >
            {index + 1}
          </text>
        )
      })}
    </svg>
  )
}
