import { Fragment, useState } from "react"
import type {
  NatalAspect,
  NatalInterpretations,
  NatalPosition,
  ProfileDetailResponse,
  TopTransit,
  TransitReportResponse,
} from "../types"
import { useLanguage } from "../contexts/LanguageContext"
import { useMobileTap } from "../lib/useMobileTap"

type ProfileDetailProps = {
  activeDetail: ProfileDetailResponse | null
  detailLoading: boolean
  detailError: string | null
  activeProfileId: string | null
  transitReport: TransitReportResponse | null
  onEditClick: () => void
}

function coerceNumber(value: number | string | null | undefined): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value === "string") {
    const n = Number(value)
    return Number.isFinite(n) ? n : null
  }
  return null
}

const OBJECT_GLYPHS: Record<string, string> = {
  Sun: "\u2609",
  Moon: "\u263D",
  Mercury: "\u263F",
  Venus: "\u2640",
  Mars: "\u2642",
  Jupiter: "\u2643",
  Saturn: "\u2644",
  Uranus: "\u2645",
  Neptune: "\u2646",
  Pluto: "\u2647",
  Chiron: "\u26B7",
  Lilith: "\u26B8",
  Selena: "\u263E",
  "North Node": "\u260A",
  "South Node": "\u260B",
  "Part of Fortune": "\u2297",
  Vertex: "\u22C1",
  ASC: "AC",
  MC: "MC",
}

const SIGN_GLYPHS: Record<string, string> = {
  Aries: "\u2648",
  Taurus: "\u2649",
  Gemini: "\u264A",
  Cancer: "\u264B",
  Leo: "\u264C",
  Virgo: "\u264D",
  Libra: "\u264E",
  Scorpio: "\u264F",
  Sagittarius: "\u2650",
  Capricorn: "\u2651",
  Aquarius: "\u2652",
  Pisces: "\u2653",
}

type ObjectGroup = { labelKey: string; ids: string[] }

const GROUPS: ObjectGroup[] = [
  { labelKey: "transits.personalPlanets", ids: ["Sun", "Moon", "ASC", "MC", "Mercury", "Venus", "Mars"] },
  { labelKey: "transits.outerPlanets", ids: ["Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"] },
  { labelKey: "transits.specialPoints", ids: ["Chiron", "Lilith", "Selena", "North Node", "South Node", "Part of Fortune", "Vertex"] },
]

function formatPosition(p: NatalPosition): string {
  return `${p.sign} ${p.degree}\u00B0${String(p.minute).padStart(2, "0")}'${String(Math.round(p.second)).padStart(2, "0")}"`
}

export function NatalPositionsTable({
  positions,
  interpretations,
}: {
  positions: NatalPosition[]
  interpretations?: NatalInterpretations | null
}) {
  const { t } = useLanguage()
  const tap = useMobileTap()
  const byId = new Map(positions.map((p) => [p.id, p]))
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

  const toggle = (id: string) => {
    setExpanded((prev) => {
      const next = new Set(prev)
      next.has(id) ? next.delete(id) : next.add(id)
      return next
    })
  }

  // ASC = house 1 cusp, MC = house 10 cusp
  const ANGLE_HOUSE_MAP: Record<string, string> = { ASC: "house_1", MC: "house_10" }

  const getInterps = (p: NatalPosition) => {
    if (!interpretations) return { inSign: undefined, inHouse: undefined, cuspInterp: undefined }
    const inSign = interpretations.planets_in_signs[p.id]
    const inHouse = interpretations.planets_in_houses[p.id]
    const cuspKey = ANGLE_HOUSE_MAP[p.id]
    const cuspInterp = cuspKey ? interpretations.house_cusps_in_signs[cuspKey] : undefined
    return { inSign, inHouse, cuspInterp }
  }

  const hasInterp = (id: string) => {
    const pos = byId.get(id)
    if (!pos || !interpretations) return false
    const { inSign, inHouse, cuspInterp } = getInterps(pos)
    return !!(inSign?.meaning || inHouse?.meaning || cuspInterp?.meaning)
  }

  return (
    <div className="natal-pos">
      <div className="natal-pos__header">
        <span className="natal-pos__title">{t("widget.planetsHouses")}</span>
      </div>
      {GROUPS.map((group) => {
        const rows = group.ids.map((id) => byId.get(id)).filter(Boolean) as NatalPosition[]
        if (!rows.length) return null
        return (
          <Fragment key={group.labelKey}>
            <div className="natal-pos__group">{t(group.labelKey)}</div>
            {rows.map((p) => {
              const clickable = hasInterp(p.id)
              const isOpen = expanded.has(p.id)
              const { inSign, inHouse, cuspInterp } = getInterps(p)
              return (
                <Fragment key={p.id}>
                  {clickable ? (
                  <button
                    type="button"
                    className="natal-pos__row natal-pos__row--clickable"
                    {...tap(() => toggle(p.id))}
                  >
                    <span className="natal-pos__left">
                      <span className="natal-pos__glyph">{OBJECT_GLYPHS[p.id] ?? ""}</span>
                      <span className="natal-pos__name">{t(`planet.${p.id}`)}</span>
                      {p.retrograde ? <span className="natal-pos__retro">Ⓡ</span> : null}
                    </span>
                    <span className="natal-pos__center">
                      <span className="natal-pos__sign-name">{t(`sign.${p.sign}`)}</span>
                      <span className="natal-pos__sign">{SIGN_GLYPHS[p.sign] ?? ""}</span>
                      <span className="natal-pos__house">△{p.house || "—"}</span>
                    </span>
                    <span className="natal-pos__right">
                      <span className="natal-pos__deg">{p.degree}°{String(p.minute).padStart(2, "0")}′</span>
                    </span>
                  </button>
                  ) : (
                  <div className="natal-pos__row">
                    <span className="natal-pos__left">
                      <span className="natal-pos__glyph">{OBJECT_GLYPHS[p.id] ?? ""}</span>
                      <span className="natal-pos__name">{t(`planet.${p.id}`)}</span>
                      {p.retrograde ? <span className="natal-pos__retro">Ⓡ</span> : null}
                    </span>
                    <span className="natal-pos__center">
                      <span className="natal-pos__sign-name">{t(`sign.${p.sign}`)}</span>
                      <span className="natal-pos__sign">{SIGN_GLYPHS[p.sign] ?? ""}</span>
                      <span className="natal-pos__house">△{p.house || "—"}</span>
                    </span>
                    <span className="natal-pos__right">
                      <span className="natal-pos__deg">{p.degree}°{String(p.minute).padStart(2, "0")}′</span>
                    </span>
                  </div>
                  )}
                  {isOpen ? (
                    <div className="natal-interp">
                      {cuspInterp?.meaning ? (
                        <div className="natal-interp__block">
                          <div className="natal-interp__label">{SIGN_GLYPHS[p.sign] ?? ""} {t(`planet.${p.id}`)} {t("interp.inSign")} {t(`sign.${p.sign}`)}</div>
                          <div className="natal-interp__text">{cuspInterp.meaning}</div>
                          {cuspInterp.keywords?.length ? (
                            <div className="natal-interp__keywords">
                              {cuspInterp.keywords.map((kw, i) => (
                                <span key={i} className="natal-interp__tag">{kw}</span>
                              ))}
                            </div>
                          ) : null}
                        </div>
                      ) : null}
                      {inSign?.meaning ? (
                        <div className="natal-interp__block">
                          <div className="natal-interp__label">{SIGN_GLYPHS[p.sign] ?? ""} {t(`planet.${p.id}`)} {t("interp.inSign")} {t(`sign.${p.sign}`)}</div>
                          <div className="natal-interp__text">{inSign.meaning}</div>
                          {inSign.keywords?.length ? (
                            <div className="natal-interp__keywords">
                              {inSign.keywords.map((kw, i) => (
                                <span key={i} className="natal-interp__tag">{kw}</span>
                              ))}
                            </div>
                          ) : null}
                        </div>
                      ) : null}
                      {inHouse?.meaning ? (
                        <div className="natal-interp__block">
                          <div className="natal-interp__label">△{p.house} {t(`planet.${p.id}`)} {t("interp.inHouse")} {p.house}</div>
                          <div className="natal-interp__text">{inHouse.meaning}</div>
                          {inHouse.keywords?.length ? (
                            <div className="natal-interp__keywords">
                              {inHouse.keywords.map((kw, i) => (
                                <span key={i} className="natal-interp__tag">{kw}</span>
                              ))}
                            </div>
                          ) : null}
                        </div>
                      ) : null}
                    </div>
                  ) : null}
                </Fragment>
              )
            })}
          </Fragment>
        )
      })}
    </div>
  )
}

const ASPECT_GLYPHS: Record<string, string> = {
  conjunction: "\u260C",
  opposition: "\u260D",
  trine: "\u25B3",
  square: "\u25A1",
  sextile: "\u26B9",
}

function aspectStrength(orb: number): string {
  if (orb < 1) return "exact"
  if (orb < 3) return "strong"
  if (orb < 5) return "moderate"
  return "wide"
}

const STRENGTH_COLORS: Record<string, string> = {
  exact: "#FF2D55",
  strong: "#FF9500",
  moderate: "#5AC8FA",
  wide: "#8E8E93",
}

const PERSONAL_IDS = new Set(["Sun", "Moon", "Mercury", "Venus", "Mars", "ASC", "MC"])
const OUTER_IDS = new Set(["Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"])

function categorizeNatalAspect(a: NatalAspect): string {
  if (PERSONAL_IDS.has(a.p1)) return "personal"
  if (OUTER_IDS.has(a.p1)) return "outer"
  return "special"
}

const GROUP_LABEL_KEYS: Record<string, string> = {
  personal: "transits.personalPlanets",
  outer: "transits.outerPlanets",
  special: "transits.specialPoints",
}

export function NatalAspectsTable({
  aspects,
  interpretations,
  positions,
}: {
  aspects: NatalAspect[]
  interpretations?: NatalInterpretations | null
  positions?: NatalPosition[]
}) {
  const { t } = useLanguage()
  const tap = useMobileTap()
  const [mostImpact, setMostImpact] = useState(true)
  const filtered = mostImpact
    ? aspects.filter((a) => aspectStrength(a.orb) === "exact" || aspectStrength(a.orb) === "strong")
    : aspects
  const sorted = [...filtered].sort((a, b) => a.orb - b.orb)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

  const aspInterps = interpretations?.aspects ?? []
  const interpMap = new Map(
    aspInterps.map((ai) => [`${ai.p1}_${ai.aspect}_${ai.p2}`, ai]),
  )
  const posMap = new Map((positions ?? []).map((p) => [p.id, p]))

  const toggle = (key: string) => {
    setExpanded((prev) => {
      const next = new Set(prev)
      next.has(key) ? next.delete(key) : next.add(key)
      return next
    })
  }

  const groupOrder = ["personal", "outer", "special"]
  const groups: Record<string, NatalAspect[]> = {}
  for (const a of sorted) {
    const cat = categorizeNatalAspect(a)
    if (!groups[cat]) groups[cat] = []
    groups[cat].push(a)
  }
  const groupedAspects = groupOrder
    .filter((key) => groups[key]?.length)
    .map((key) => ({ key, aspects: groups[key]! }))

  return (
    <div className="natal-asp">
      <div className="natal-asp__header">
        <span className="natal-asp__title">{t("widget.natalAspects")}</span>
        <label className="cw-toggle-wrap">
          <span className="cw-toggle-label">{t("transits.mostImpact")}</span>
          <div
            className={`cw-toggle${mostImpact ? " cw-toggle--on" : ""}`}
            onClick={() => setMostImpact(!mostImpact)}
          >
            <div className="cw-toggle-thumb" />
          </div>
        </label>
      </div>
      {groupedAspects.map((group) => (
        <div key={group.key} className="cw-transit-group">
          <div className="cw-transit-group-label">{t(GROUP_LABEL_KEYS[group.key])}</div>
          <div className="cw-transit-list">
            {group.aspects.map((a, i) => {
              const strength = aspectStrength(a.orb)
              const strengthColor = STRENGTH_COLORS[strength] ?? "#8E8E93"
              const aspKey = `${a.p1}_${a.aspect}_${a.p2}`
              const interp = interpMap.get(aspKey)
              const clickable = !!interp?.meaning
              const isOpen = expanded.has(aspKey)
              return (
                <div
                  key={`${aspKey}-${i}`}
                  className={`cw-transit-item${isOpen ? " cw-transit-item--expanded" : ""}`}
                  style={clickable ? { cursor: "pointer" } : undefined}
                >
                  {clickable ? <button type="button" className="tap-target" {...tap(() => toggle(aspKey))} /> : null}
                  <div className="cw-transit-row">
                    <span className="cw-transit-left">
                      <span className="cw-transit-glyphs">
                        <span className="cw-glyph-transit">{OBJECT_GLYPHS[a.p1] ?? ""}</span>
                        <span className="cw-glyph-aspect">{ASPECT_GLYPHS[a.aspect] ?? ""}</span>
                        <span className="cw-glyph-natal">{OBJECT_GLYPHS[a.p2] ?? ""}</span>
                      </span>
                      <span className="cw-transit-label">
                        {t(`planet.${a.p1}`)} {t(`aspect.${a.aspect}`)} {t(`planet.${a.p2}`)}
                      </span>
                    </span>
                    <span className="cw-transit-right">
                      <span className="cw-transit-orb">{a.orb.toFixed(2)}°</span>
                      <span
                        className="cw-transit-strength"
                        style={{ background: `${strengthColor}18`, color: strengthColor }}
                      >
                        {t(`strength.${strength}`)}
                      </span>
                    </span>
                  </div>

                  {isOpen && interp?.meaning ? (
                    <div className="cw-transit-description">
                      <p className="cw-transit-meaning">{interp.meaning}</p>
                      {interp.keywords?.length ? (
                        <div className="cw-transit-keywords">
                          {interp.keywords.map((kw, ki) => (
                            <span key={ki} className="cw-transit-keyword-tag">{kw}</span>
                          ))}
                        </div>
                      ) : null}
                      {(() => {
                        const p1pos = posMap.get(a.p1)
                        const p2pos = posMap.get(a.p2)
                        if (!p1pos && !p2pos) return null
                        return (
                          <div className="cw-transit-positions">
                            {p1pos ? (
                              <div className="cw-pos-line">
                                <span className="cw-pos-glyph">{OBJECT_GLYPHS[a.p1]}</span>
                                <span className="cw-pos-name">{t(`planet.${a.p1}`)}</span>
                                <span className="cw-pos-deg">{p1pos.degree}°{String(p1pos.minute).padStart(2, "0")}′</span>
                                <span className="cw-pos-sign">{SIGN_GLYPHS[p1pos.sign] ?? ""} {t(`sign.${p1pos.sign}`)}</span>
                                <span className="cw-pos-house">△{p1pos.house}</span>
                                {p1pos.retrograde ? <span className="cw-pos-retro">Ⓡ</span> : null}
                              </div>
                            ) : null}
                            {p2pos ? (
                              <div className="cw-pos-line">
                                <span className="cw-pos-glyph">{OBJECT_GLYPHS[a.p2]}</span>
                                <span className="cw-pos-name">{t(`planet.${a.p2}`)}</span>
                                <span className="cw-pos-deg">{p2pos.degree}°{String(p2pos.minute).padStart(2, "0")}′</span>
                                <span className="cw-pos-sign">{SIGN_GLYPHS[p2pos.sign] ?? ""} {t(`sign.${p2pos.sign}`)}</span>
                                <span className="cw-pos-house">△{p2pos.house}</span>
                                {p2pos.retrograde ? <span className="cw-pos-retro">Ⓡ</span> : null}
                              </div>
                            ) : null}
                          </div>
                        )
                      })()}
                    </div>
                  ) : null}
                </div>
              )
            })}
          </div>
        </div>
      ))}
    </div>
  )
}

function computeAge(birthDate: string): number | null {
  const d = new Date(birthDate)
  if (isNaN(d.getTime())) return null
  const now = new Date()
  let age = now.getFullYear() - d.getFullYear()
  const monthDiff = now.getMonth() - d.getMonth()
  if (monthDiff < 0 || (monthDiff === 0 && now.getDate() < d.getDate())) age--
  return age
}

export function ProfileSummaryCard({ detail }: { detail: ProfileDetailResponse }) {
  const { t } = useLanguage()
  const positions = detail.chart.natal_positions ?? []
  const byId = new Map(positions.map((p) => [p.id, p]))
  const sun = byId.get("Sun")
  const moon = byId.get("Moon")
  const asc = byId.get("ASC")
  const mc = byId.get("MC")
  const mercury = byId.get("Mercury")
  const venus = byId.get("Venus")
  const mars = byId.get("Mars")

  const birthInput = (detail.chart as Record<string, unknown>).birth_input as Record<string, unknown> | undefined
  const birthDate = (birthInput?.birth_date as string) ?? detail.chart.local_birth_datetime?.slice(0, 10) ?? null
  const birthTime = (birthInput?.birth_time as string) ?? null
  const timezone = (birthInput?.timezone as string) ?? null
  const localDt = (birthInput?.local_birth_datetime as string) ?? detail.chart.local_birth_datetime ?? null
  const locationName = (birthInput?.location_name as string) ?? detail.chart.location_name ?? null
  const age = birthDate ? computeAge(birthDate) : null

  const formatDate = (d: string) => {
    const parts = d.split("-")
    if (parts.length === 3) return `${parts[2]}.${parts[1]}.${parts[0]}`
    return d
  }

  const gmtOffset = (() => {
    if (!localDt) return null
    const m = localDt.match(/([+-])(\d{2}):(\d{2})$/)
    if (!m) return null
    const sign = m[1]
    const hours = parseInt(m[2], 10)
    const mins = parseInt(m[3], 10)
    const label = mins > 0 ? `GMT${sign}${hours}:${String(mins).padStart(2, "0")}` : `GMT${sign}${hours}`
    return label.replace("+0", "+").replace("-0", "-").replace("GMT+", "UTC+").replace("GMT-", "UTC-")
  })()

  const signItems: { id: string; pos: NatalPosition | undefined }[] = [
    { id: "Sun", pos: sun },
    { id: "Moon", pos: moon },
    { id: "ASC", pos: asc },
  ]
  const secondaryItems: { id: string; pos: NatalPosition | undefined }[] = [
    { id: "MC", pos: mc },
    { id: "Mercury", pos: mercury },
    { id: "Venus", pos: venus },
    { id: "Mars", pos: mars },
  ]

  return (
    <div className="profile-summary">
      <div className="profile-summary__signs">
        {signItems.map(({ id, pos }) => pos ? (
          <div key={id} className="profile-summary__sign-item">
            <span className="profile-summary__sign-icon">{SIGN_GLYPHS[pos.sign] ?? ""}</span>
            <div>
              <div className="profile-summary__sign-label">{t(`planet.${id}`)}</div>
              <div className="profile-summary__sign-value">{t(`sign.${pos.sign}`)}</div>
            </div>
          </div>
        ) : null)}
      </div>
      <div className="profile-summary__signs profile-summary__signs--secondary">
        {secondaryItems.map(({ id, pos }) => pos ? (
          <div key={id} className="profile-summary__sign-item">
            <span className="profile-summary__sign-icon">{SIGN_GLYPHS[pos.sign] ?? ""}</span>
            <div>
              <div className="profile-summary__sign-label">{t(`planet.${id}`)}</div>
              <div className="profile-summary__sign-value">{t(`sign.${pos.sign}`)}</div>
            </div>
          </div>
        ) : null)}
      </div>
      <div className="profile-summary__meta">
        {age !== null ? (
          <span className="profile-summary__age-badge">{age}</span>
        ) : null}
        <div className="profile-summary__meta-text">
          {locationName ? <span>{locationName}</span> : null}
          <span>
            {birthDate ? formatDate(birthDate) : ""}
            {birthTime ? `, ${birthTime.slice(0, 5)}` : ""}
            {timezone ? ` (${timezone}` : ""}
            {gmtOffset ? `, ${gmtOffset}` : ""}
            {timezone || gmtOffset ? ")" : ""}
          </span>
        </div>
      </div>
    </div>
  )
}

const FEELS_LIKE_COLORS: Record<string, string> = {
  Calm: "#83e0ad",
  "Gentle Tension": "#a8d8a0",
  "Restless Calm": "#c4cc8a",
  Flowing: "#7dd3e8",
  Dynamic: "#f0c74c",
  Pressured: "#f09c4c",
  Supercharged: "#c084fc",
  Intense: "#f06040",
  Explosive: "#ef4444",
}

function tiiArcColor(tii: number): string {
  if (tii < 25) return "#83e0ad"
  if (tii < 50) return "#f0c74c"
  if (tii < 75) return "#f09c4c"
  return "#ef4444"
}

function TiiGauge({ tii }: { tii: number }) {
  const r = 40
  const stroke = 8
  const circumference = Math.PI * r
  const progress = Math.min(tii / 100, 1)
  const dashOffset = circumference * (1 - progress)

  return (
    <svg width="96" height="56" viewBox="0 0 96 56">
      <path
        d={`M ${48 - r} 48 A ${r} ${r} 0 0 1 ${48 + r} 48`}
        fill="none"
        stroke="var(--line)"
        strokeWidth={stroke}
        strokeLinecap="round"
      />
      <path
        d={`M ${48 - r} 48 A ${r} ${r} 0 0 1 ${48 + r} 48`}
        fill="none"
        stroke={tiiArcColor(tii)}
        strokeWidth={stroke}
        strokeLinecap="round"
        strokeDasharray={circumference}
        strokeDashoffset={dashOffset}
      />
      <text x="48" y="44" textAnchor="middle" fill="var(--ink)" fontSize="18" fontWeight="700">
        {Math.round(tii)}
      </text>
    </svg>
  )
}

export function TiiBanner({ transitReport }: { transitReport: TransitReportResponse }) {
  const { t } = useLanguage()
  const tii = transitReport.tii
  const feelsLike = transitReport.feels_like
  const tensionRatio = transitReport.tension_ratio
  const topTransits = transitReport.top_transits ?? []

  if (tii == null) return null

  const feelsColor = feelsLike ? FEELS_LIKE_COLORS[feelsLike] ?? "var(--muted)" : "var(--muted)"

  return (
    <div className="tii-banner">
      <div className="tii-banner__gauge">
        <TiiGauge tii={tii} />
        <div className="tii-banner__label">TII</div>
      </div>
      <div className="tii-banner__info">
        <div className="tii-banner__feels" style={{ color: feelsColor }}>
          {feelsLike ? t(`feels.${feelsLike}`) : "—"}
        </div>
        {tensionRatio != null ? (
          <div className="tii-banner__tension">
            {t("weather.tension")} {Math.round(tensionRatio * 100)}%
          </div>
        ) : null}
        {topTransits.length > 0 ? (
          <div className="tii-banner__top">
            {topTransits.map((tr: TopTransit, i: number) => (
              <span key={i} className="tii-banner__transit">
                {OBJECT_GLYPHS[tr.transit_object] ?? tr.transit_object}{" "}
                {ASPECT_GLYPHS[tr.aspect] ?? tr.aspect}{" "}
                {OBJECT_GLYPHS[tr.natal_object] ?? tr.natal_object}
              </span>
            ))}
          </div>
        ) : null}
      </div>
    </div>
  )
}

export function ProfileDetail({
  activeDetail,
  detailLoading,
  detailError,
  activeProfileId,
  transitReport,
  onEditClick,
}: ProfileDetailProps) {
  const { t } = useLanguage()
  return (
    <>
      {!detailLoading && !detailError && activeDetail ? (
        <div className="profile-summary-row">
          <ProfileSummaryCard detail={activeDetail} />
        </div>
      ) : null}

      {!detailLoading && !detailError && transitReport ? (
        <TiiBanner transitReport={transitReport} />
      ) : null}

      {detailLoading ? (
        <div className="ring-stage loading-state">
          <p>Loading…</p>
        </div>
      ) : null}

      {!detailLoading && detailError ? (
        <div className="ring-stage error-state">
          <strong>Error</strong>
          <span>{detailError}</span>
        </div>
      ) : null}

      {!detailLoading && !detailError && !activeProfileId ? (
        <div className="ring-stage empty-state">
          <strong>{t("widget.selectProfile")}</strong>
          <span>{t("profileList.emptyDesc")}</span>
        </div>
      ) : null}

      {!detailLoading && !detailError && activeDetail?.chart.natal_positions?.length ? (
        <NatalPositionsTable positions={activeDetail.chart.natal_positions} interpretations={activeDetail.chart.natal_interpretations} />
      ) : null}

      {!detailLoading && !detailError && activeDetail?.chart.natal_aspects?.length ? (
        <NatalAspectsTable aspects={activeDetail.chart.natal_aspects} interpretations={activeDetail.chart.natal_interpretations} positions={activeDetail.chart.natal_positions} />
      ) : null}
    </>
  )
}
