import { useState, useEffect, useRef } from "react"
import type { TransitReportResponse, ProfileDetailResponse, ActiveAspect, AspectTiming, TransitPosition, NatalPosition } from "../types"
import type { PlaceCandidate } from "../api"
import { LocationAutocomplete } from "./LocationAutocomplete"
import { zoneColor, FEELS_EMOJI, FEELS_MOOD } from "../tii-zones"
import { useLanguage } from "../contexts/LanguageContext"
import { useMobileTap } from "../lib/useMobileTap"


const STRENGTH_COLORS: Record<string, string> = {
  exact: "#FF2D55",
  strong: "#FF9500",
  moderate: "#5AC8FA",
  wide: "#8E8E93",
}

const PLANET_FACTOR: Record<string, number> = {
  Sun: 1.0, Moon: 0.5, Mercury: 1.0, Venus: 1.0, Mars: 1.0,
  Jupiter: 1.3, Saturn: 1.3, Uranus: 1.5, Neptune: 1.5, Pluto: 1.5,
}

/** 3-stop color scale: blue → yellow → red */
const COLOR_SCALE = [
  { t: 0.0, r: 90, g: 200, b: 250 },    // #5AC8FA
  { t: 0.5, r: 255, g: 214, b: 10 },    // #FFD60A
  { t: 1.0, r: 255, g: 55, b: 95 },     // #FF375F
]

function intensityToColor(intensity: number): string {
  const t = Math.max(0, Math.min(1, intensity))
  for (let i = 0; i < COLOR_SCALE.length - 1; i++) {
    const a = COLOR_SCALE[i], b = COLOR_SCALE[i + 1]
    if (t >= a.t && t <= b.t) {
      const f = (t - a.t) / (b.t - a.t)
      const r = Math.round(a.r + (b.r - a.r) * f)
      const g = Math.round(a.g + (b.g - a.g) * f)
      const bl = Math.round(a.b + (b.b - a.b) * f)
      return `rgb(${r},${g},${bl})`
    }
  }
  return `rgb(${COLOR_SCALE[COLOR_SCALE.length - 1].r},${COLOR_SCALE[COLOR_SCALE.length - 1].g},${COLOR_SCALE[COLOR_SCALE.length - 1].b})`
}

/** Bell curve: peaks at exactPct, falls off smoothly */
function influenceAt(pct: number, exactPct: number): number {
  const dist = (pct - exactPct) / 100
  return Math.exp(-8 * dist * dist)
}

/** Build CSS linear-gradient based on influence curve */
function buildTransitGradient(exactPct: number, planetFactor: number): string {
  const maxI = Math.min(1.0, planetFactor)
  const stops: string[] = []
  for (let p = 0; p <= 100; p += 5) {
    const intensity = influenceAt(p, exactPct) * maxI
    stops.push(`${intensityToColor(intensity)} ${p}%`)
  }
  return `linear-gradient(to right, ${stops.join(", ")})`
}

/** Get peak color for a transit (used for now-dot border and glow) */
function peakColor(planetFactor: number): string {
  return intensityToColor(Math.min(1.0, planetFactor))
}

const OBJECT_GLYPHS: Record<string, string> = {
  Sun: "\u2609", Moon: "\u263D", Mercury: "\u263F", Venus: "\u2640", Mars: "\u2642",
  Jupiter: "\u2643", Saturn: "\u2644", Uranus: "\u2645", Neptune: "\u2646", Pluto: "\u2647",
  Chiron: "\u26B7", Lilith: "\u26B8", Selena: "\u263E",
  "North Node": "\u260A", "South Node": "\u260B", "Part of Fortune": "\u2297", Vertex: "\u22C1",
  ASC: "AC", MC: "MC",
}

const SIGN_GLYPHS: Record<string, string> = {
  Aries: "♈", Taurus: "♉", Gemini: "♊", Cancer: "♋",
  Leo: "♌", Virgo: "♍", Libra: "♎", Scorpio: "♏",
  Sagittarius: "♐", Capricorn: "♑", Aquarius: "♒", Pisces: "♓",
}

const ASPECT_GLYPHS: Record<string, string> = {
  conjunction: "\u260C",
  opposition: "\u260D",
  trine: "\u25B3",
  square: "\u25A1",
  sextile: "\u2731",
}

type Props = {
  transitReport: TransitReportResponse
  activeDetail: ProfileDetailResponse
  loading?: boolean
  onGuideOpen?: () => void
  onTransitSettings?: (date: string, time: string, tz: string, location: string) => void
}

export function DailyWeather({ transitReport, activeDetail, loading, onGuideOpen, onTransitSettings }: Props) {
  const { t } = useLanguage()
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [editDate, setEditDate] = useState("")
  const [editTime, setEditTime] = useState("")
  const [editTz, setEditTz] = useState("")
  const [editLoc, setEditLoc] = useState("")
  const [compact, setCompact] = useState(false)
  const heroRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const el = heroRef.current
    if (!el) return
    const observer = new IntersectionObserver(
      ([entry]) => setCompact(!entry.isIntersecting),
      { threshold: 0, rootMargin: "-48px 0px 0px 0px" }
    )
    observer.observe(el)
    return () => observer.disconnect()
  }, [])

  const tii = transitReport.tii ?? 0
  const feelsLike = transitReport.feels_like ?? "Calm"
  const tensionRatio = transitReport.tension_ratio ?? 0
  const accent = zoneColor(tii)
  const emoji = FEELS_EMOJI[feelsLike] ?? "\u2728"
  const mood = t(`mood.${feelsLike}`)
  const feelsLabel = t(`feels.${feelsLike}`)

  const tz = transitReport.snapshot?.transit_timezone ?? ""
  const tzLabel = (() => {
    if (!tz) return ""
    // Extract city part: "America/Los_Angeles" → "Los Angeles"
    const city = tz.split("/").pop()?.replace(/_/g, " ") ?? tz
    // Get UTC offset like "+03:00" or "-07:00"
    try {
      const offsetStr = new Intl.DateTimeFormat("en", { timeZone: tz, timeZoneName: "shortOffset" })
        .formatToParts(new Date())
        .find((p) => p.type === "timeZoneName")?.value ?? ""
      return `${city} ${offsetStr}`.toUpperCase()
    } catch {
      return city.toUpperCase()
    }
  })()

  function openSettings() {
    const snap = transitReport.snapshot
    try {
      const utcIso = snap?.transit_utc_datetime ?? ""
      const snapTz = snap?.transit_timezone || undefined
      const d = new Date(utcIso.endsWith("Z") ? utcIso : utcIso + "Z")
      const localParts = d.toLocaleString("en-CA", { timeZone: snapTz, year: "numeric", month: "2-digit", day: "2-digit" })
      setEditDate(localParts)
      const timeParts = d.toLocaleString("en-GB", { timeZone: snapTz, hour: "2-digit", minute: "2-digit", hour12: false })
      setEditTime(timeParts.replace(/[^0-9:]/g, ""))
    } catch {
      setEditDate(snap?.transit_date ?? "")
      setEditTime("12:00")
    }
    setEditTz(snap?.transit_timezone ?? Intl.DateTimeFormat().resolvedOptions().timeZone)
    setEditLoc(snap?.transit_location_name ?? "")
    setSettingsOpen(true)
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (editDate && editTime && onTransitSettings) {
      onTransitSettings(editDate, editTime, editTz, editLoc)
    }
    setSettingsOpen(false)
  }

  // Format just the local time for the hero corner
  let heroTimeLabel = ""
  try {
    const snap = transitReport.snapshot
    const utcIso = snap?.transit_utc_datetime ?? ""
    const snapTz = snap?.transit_timezone || undefined
    if (utcIso) {
      const d = new Date(utcIso.endsWith("Z") ? utcIso : utcIso + "Z")
      heroTimeLabel = d.toLocaleString("en-US", {
        timeZone: snapTz,
        weekday: "short",
        month: "short",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit",
        hour12: true,
      })
    }
  } catch { /* ignore */ }

  return (
    <div className="cw">
      {/* Compact fixed header — appears when hero scrolls out */}
      <div className={`cw-compact${compact ? " cw-compact--visible" : ""}`}>
        <span className="cw-compact__name">{activeDetail.profile.profile_name}</span>
        <span className="cw-compact__emoji">{emoji}</span>
        <span className="cw-compact__tii">{Math.round(tii)}&deg;</span>
        <span className="cw-compact__feels" style={{ color: accent }}>{feelsLabel}</span>
        <span className="cw-compact__tension">T {Math.round(tensionRatio * 100)}%</span>
        {heroTimeLabel ? <span className="cw-compact__date" onClick={openSettings}>{heroTimeLabel}</span> : null}
      </div>

      <div className="cw-hero" ref={heroRef}>
        {tzLabel ? <div className="cw-location">{tzLabel}</div> : null}
        <div className="cw-title">{activeDetail.profile.profile_name}</div>

        {heroTimeLabel ? (
          <div className="cw-hero-date" onClick={openSettings}>
            {heroTimeLabel}
            {loading ? <span className="cw-spinner" /> : null}
          </div>
        ) : null}

        <div className="cw-emoji">{emoji}</div>

        <div className="cw-tii">{Math.round(tii)}&deg;</div>
        <div className="cw-tii-label">{t("weather.intensity")}</div>

        <div className="cw-feels" style={{ color: accent }}>{feelsLabel}</div>
        <div className="cw-mood">{mood}</div>

        <div className="cw-tension-bar">
          <div className="cw-tension-bar__track">
            <div
              className="cw-tension-bar__fill"
              style={{ width: `${Math.round(tensionRatio * 100)}%`, background: accent }}
            />
          </div>
          <span className="cw-tension-bar__label">{t("weather.tension")} {Math.round(tensionRatio * 100)}%</span>
        </div>
      </div>

      {settingsOpen ? (
        <div className="settings-overlay" onClick={() => setSettingsOpen(false)}>
          <div className="settings-popup" onClick={(e) => e.stopPropagation()}>
            <div className="settings-popup-head">
              <h3>{t("weather.transitSettings")}</h3>
              <button type="button" className="settings-close" onClick={() => setSettingsOpen(false)}>&times;</button>
            </div>
            <form className="transit-form" onSubmit={handleSubmit}>
              <div className="transit-fields">
                <label className="transit-field">
                  <span className="transit-field-label">{t("weather.date")}</span>
                  <input type="date" value={editDate} onChange={(e) => setEditDate(e.target.value)} required />
                </label>
                <label className="transit-field">
                  <span className="transit-field-label">{t("weather.time")}</span>
                  <input type="time" step="1" value={editTime} onChange={(e) => setEditTime(e.target.value)} required />
                </label>
              </div>
              <div className="transit-field transit-field--full">
                <span className="transit-field-label">{t("weather.location")}</span>
                <LocationAutocomplete
                  value={editLoc}
                  onChange={setEditLoc}
                  onSelect={(place: PlaceCandidate) => {
                    setEditLoc(place.display_name)
                    if (place.timezone) setEditTz(place.timezone)
                  }}
                  placeholder={t("weather.searchCity")}
                />
              </div>
              <label className="transit-field transit-field--full">
                <span className="transit-field-label">{t("weather.timezone")}</span>
                <input type="text" value={editTz} readOnly placeholder={t("weather.autoTimezone")} />
              </label>
              <div className="transit-actions">
                <button type="submit" className="status">{t("weather.generate")}</button>
              </div>
            </form>
          </div>
        </div>
      ) : null}
    </div>
  )
}

function formatTransitDateTime(snapshot: TransitReportResponse["snapshot"]): string {
  if (!snapshot) return ""
  const utcIso = snapshot.transit_utc_datetime ?? ""
  const tz = snapshot.transit_timezone ?? ""
  if (!utcIso) return ""
  try {
    const utcDate = new Date(utcIso.endsWith("Z") ? utcIso : utcIso + "Z")
    const localStr = utcDate.toLocaleString("en-GB", {
      timeZone: tz || undefined,
      day: "numeric",
      month: "short",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    })
    const tzShort = tz.split("/").pop()?.replace(/_/g, " ") ?? tz
    return `${localStr} \u00B7 ${tzShort}`
  } catch {
    const d = snapshot.transit_date ?? ""
    const t = (snapshot.transit_time_ut ?? "").slice(0, 5)
    return `${d}, ${t} UT`
  }
}

/** Format ISO date string to "14 Mar" using translated month */
function shortDate(iso: string | null | undefined, t?: (key: string) => string): string {
  if (!iso) return ""
  try {
    const d = new Date(iso)
    if (isNaN(d.getTime())) return ""
    const month = t ? t(`month.${d.getUTCMonth()}`) : d.toLocaleString("en", { month: "short", timeZone: "UTC" })
    return `${d.getUTCDate()} ${month}`
  } catch {
    return ""
  }
}

/** Progress bar for a single transit aspect with influence gradient */
export function TransitProgressBar({ timing, nowDate, transitObject }: {
  timing: AspectTiming | null
  nowDate: string
  transitObject: string
}) {
  const { t } = useLanguage()
  if (!timing?.start_utc || !timing?.end_utc) return null

  const start = new Date(timing.start_utc).getTime()
  const end = new Date(timing.end_utc).getTime()
  const now = new Date(nowDate + "T12:00:00Z").getTime()
  const total = end - start

  if (total <= 0) return null

  const nowPct = Math.max(0, Math.min(100, ((now - start) / total) * 100))

  // Use peak_utc (closest approach, always exists) for the main notch
  // exact_utc only exists when orb < 0.01° which is too strict
  const peakDate = timing.peak_utc ?? timing.exact_utc
  let peakPct: number | null = null
  if (peakDate) {
    const peak = new Date(peakDate).getTime()
    peakPct = Math.max(0, Math.min(100, ((peak - start) / total) * 100))
  }

  const pFactor = PLANET_FACTOR[transitObject] ?? 1.0
  const gradientPeak = peakPct ?? 50
  const gradient = buildTransitGradient(gradientPeak, pFactor)
  const dotColor = peakColor(pFactor)
  const isOuter = pFactor > 1.0

  const startLabel = shortDate(timing.start_utc, t)
  const peakLabel = shortDate(peakDate, t)
  const endLabel = shortDate(timing.end_utc, t)

  return (
    <div className="transit-bar">
      <div className={`transit-bar__track${isOuter ? " transit-bar__track--outer" : ""}`}
        style={isOuter ? { boxShadow: `0 0 6px ${dotColor}40` } as React.CSSProperties : undefined}
      >
        <div
          className="transit-bar__gradient"
          style={{
            background: gradient,
            width: `${nowPct}%`,
            backgroundSize: nowPct > 0 ? `${100 / nowPct * 100}% 100%` : undefined,
          }}
        />
        {/* Render notches: exact_passes if multiple, otherwise peak notch */}
        {timing.exact_passes && timing.exact_passes.length > 1 ? (
          timing.exact_passes.map((pass, i) => {
            const passTime = new Date(pass.utc).getTime()
            const passPct = Math.max(0, Math.min(100, ((passTime - start) / total) * 100))
            const tier = i % 2 === 0 ? "" : " transit-bar__exact--alt"
            return (
              <div key={i} className={`transit-bar__exact${tier}`} style={{ left: `${passPct}%` }} />
            )
          })
        ) : peakPct !== null ? (
          <div className="transit-bar__exact" style={{ left: `${peakPct}%` }} />
        ) : null}
        <div
          className="transit-bar__now"
          style={{ left: `${nowPct}%`, borderColor: dotColor }}
        />
      </div>
      <div className="transit-bar__labels">
        <span>{startLabel}</span>
        {timing.exact_passes && timing.exact_passes.length > 1 ? (
          timing.exact_passes.map((pass, i) => {
            const passTime = new Date(pass.utc).getTime()
            const passPct = Math.max(0, Math.min(100, ((passTime - start) / total) * 100))
            const tier = i % 2 === 0 ? "" : " transit-bar__exact-label--alt"
            return (
              <span key={i} className={`transit-bar__exact-label${tier}`} style={{ left: `${passPct}%` }}>
                {shortDate(pass.utc, t)}
              </span>
            )
          })
        ) : peakPct !== null && peakLabel ? (
          <span className="transit-bar__exact-label" style={{ left: `${peakPct}%` }}>{peakLabel}</span>
        ) : null}
        <span>{endLabel}</span>
      </div>
    </div>
  )
}

const OUTER_PLANETS = new Set(["Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"])

const PLANET_EMOJI: Record<string, string> = {
  Jupiter: "🌊", Saturn: "🏗", Uranus: "⚡", Neptune: "🌊", Pluto: "🌀",
}

const PLANET_BAR_COLOR: Record<string, string> = {
  Pluto: "#FF2D55",
  Neptune: "#5AC8FA",
  Uranus: "#FFB800",
  Saturn: "#30D158",
  Jupiter: "#5E5CE6",
}

function formatMonthRange(startUtc: string | null, endUtc: string | null, t?: (key: string) => string): string {
  if (!startUtc || !endUtc) return ""
  const s = new Date(startUtc)
  const e = new Date(endUtc)
  if (isNaN(s.getTime()) || isNaN(e.getTime())) return ""
  const sMonth = t ? t(`month.${s.getMonth()}`) : ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][s.getMonth()]
  const eMonth = t ? t(`month.${e.getMonth()}`) : ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][e.getMonth()]
  const sYear = s.getFullYear()
  const eYear = e.getFullYear()
  if (sYear === eYear) return `${sMonth} — ${eMonth} ${eYear}`
  return `${sMonth} ${sYear} — ${eMonth} ${eYear}`
}

/** Simple single-color progress bar for Cosmic Climate cards — no dates */
function ClimateProgressBar({ timing, nowDate, transitObject }: {
  timing: AspectTiming | null
  nowDate: string
  transitObject: string
}) {
  if (!timing?.start_utc || !timing?.end_utc) return null
  const start = new Date(timing.start_utc).getTime()
  const end = new Date(timing.end_utc).getTime()
  const now = new Date(nowDate + "T12:00:00Z").getTime()
  const total = end - start
  if (total <= 0) return null
  const pct = Math.max(0, Math.min(100, ((now - start) / total) * 100))
  const color = PLANET_BAR_COLOR[transitObject] ?? "#5AC8FA"

  return (
    <div className="cc-bar">
      <div className="cc-bar__track">
        <div className="cc-bar__fill" style={{ width: `${pct}%`, background: color }} />
      </div>
    </div>
  )
}

export function CosmicClimateWidget({ transitReport }: {
  transitReport: TransitReportResponse
}) {
  const { t } = useLanguage()
  const climateAspects = transitReport.cosmic_climate ?? []
  const nowDate = transitReport.snapshot?.transit_date ?? ""

  if (!climateAspects.length) return null

  return (
    <div className="cc-widget">
      <div className="cc-title">{t("climate.title")}</div>
      {climateAspects.map((a, i) => {
        const tGlyph = OBJECT_GLYPHS[a.transit_object] ?? a.transit_object
        const nGlyph = OBJECT_GLYPHS[a.natal_object] ?? a.natal_object
        const aGlyph = ASPECT_GLYPHS[a.aspect] ?? a.aspect
        const emoji = PLANET_EMOJI[a.transit_object] ?? "✨"
        const dateRange = formatMonthRange(a.timing?.start_utc ?? null, a.timing?.end_utc ?? null, t)

        return (
          <div key={`${a.transit_object}-${a.natal_object}-${i}`} className="cc-card">
            <div className="cc-card-header">
              <div className="cc-card-left">
                <span className="cc-card-emoji">{emoji}</span>
                <span className="cc-card-name">
                  {t(`planet.${a.transit_object}`)} {aGlyph} {t(`planet.${a.natal_object}`)}
                </span>
              </div>
              {dateRange ? <span className="cc-card-date">{dateRange}</span> : null}
            </div>
            {a.meaning ? <p className="cc-card-desc">{a.meaning}</p> : null}
            {a.insight ? <p className="cc-card-insight">{a.insight}</p> : null}
            <ClimateProgressBar timing={a.timing} nowDate={nowDate} transitObject={a.transit_object} />
          </div>
        )
      })}
    </div>
  )
}

const PERSONAL_IDS = new Set(["Sun", "Moon", "Mercury", "Venus", "Mars"])
const OUTER_IDS = new Set(["Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"])

function categorizeWidgetAspect(a: ActiveAspect): string {
  if (PERSONAL_IDS.has(a.transit_object)) return "personal"
  if (OUTER_IDS.has(a.transit_object)) return "outer"
  return "special"
}

const GROUP_LABEL_KEYS: Record<string, string> = {
  personal: "transits.personalPlanets",
  outer: "transits.outerPlanets",
  special: "transits.specialPoints",
}

export function ActiveTransitsWidget({ transitReport }: {
  transitReport: TransitReportResponse
}) {
  const { t } = useLanguage()
  const tap = useMobileTap()
  const allAspects = transitReport.active_aspects ?? []
  const [expandedCards, setExpandedCards] = useState<Set<number>>(new Set())
  const [mostImpact, setMostImpact] = useState(true)
  if (!allAspects.length) return null

  const aspects = mostImpact
    ? allAspects.filter((a) => a.strength === "exact" || a.strength === "strong")
    : allAspects

  const dateLabel = formatTransitDateTime(transitReport.snapshot)
  const nowDate = transitReport.snapshot?.transit_date ?? ""

  // Build position lookup maps
  const transitMap: Record<string, TransitPosition> = {}
  for (const tp of transitReport.transit_positions ?? []) transitMap[tp.id] = tp
  const natalMap: Record<string, NatalPosition> = {}
  for (const np of transitReport.natal_positions ?? []) natalMap[np.id] = np
  for (const ap of transitReport.angle_positions ?? [])
    natalMap[ap.id] = { ...ap, house: 0, retrograde: null, speed: null } as NatalPosition

  // Group aspects
  const groupOrder = ["personal", "outer", "special"]
  const groups: Record<string, ActiveAspect[]> = {}
  for (const a of aspects) {
    const cat = categorizeWidgetAspect(a)
    if (!groups[cat]) groups[cat] = []
    groups[cat].push(a)
  }
  const groupedAspects = groupOrder
    .filter((key) => groups[key]?.length)
    .map((key) => ({ key, aspects: groups[key] }))

  const toggleCardIdx = (idx: number) => {
    setExpandedCards((prev) => {
      const next = new Set(prev)
      if (next.has(idx)) next.delete(idx)
      else next.add(idx)
      return next
    })
  }
  const toggleCard = (e: React.MouseEvent, idx: number) => {
    e.stopPropagation()
    toggleCardIdx(idx)
  }

  // Global index for expand tracking across groups
  let globalIdx = 0

  return (
    <div className="cw-transits">
      <div className="cw-transits-header">
        <span className="cw-transits-title">{t("transits.title")}</span>
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
          <div className="cw-transit-group-label">{t(GROUP_LABEL_KEYS[group.key]).toUpperCase()}</div>
          <div className="cw-transit-list">
            {group.aspects.map((a) => {
              const idx = globalIdx++
              const strengthColor = STRENGTH_COLORS[a.strength] ?? "#8E8E93"
              const isExpanded = expandedCards.has(idx)
              const tp = transitMap[a.transit_object]
              const np = natalMap[a.natal_object]
              return (
                <div
                  key={`${a.transit_object}-${a.natal_object}-${idx}`}
                  className={`cw-transit-item${isExpanded ? " cw-transit-item--expanded" : ""}`}
                  style={{ cursor: "pointer" }}
                >
                  <button type="button" className="tap-target" {...tap(() => toggleCardIdx(idx))} />
                  <div className="cw-transit-row">
                    <span className="cw-transit-left">
                      <span className="cw-transit-glyphs">
                        <span className="cw-glyph-transit">{OBJECT_GLYPHS[a.transit_object] ?? a.transit_object}</span>
                        <span className="cw-glyph-aspect">{ASPECT_GLYPHS[a.aspect] ?? a.aspect}</span>
                        <span className="cw-glyph-natal">{OBJECT_GLYPHS[a.natal_object] ?? a.natal_object}</span>
                      </span>
                      <span className="cw-transit-label">
                        {t(`planet.${a.transit_object}`)} {t(`aspect.${a.aspect}`)} {t(`planet.${a.natal_object}`)}
                        {tp?.retrograde ? <span className="cw-retro-badge">Ⓡ</span> : null}
                      </span>
                    </span>
                    <span className="cw-transit-right">
                      <span className="cw-transit-orb">{a.orb.toFixed(2)}&deg;</span>
                      <span
                        className="cw-transit-strength"
                        style={{ background: `${strengthColor}18`, color: strengthColor }}
                      >
                        {t(`strength.${a.strength}`)}
                      </span>
                    </span>
                  </div>
                  {isExpanded ? (
                    <div className="cw-transit-description">
                      {a.meaning ? <p className="cw-transit-meaning">{a.meaning}</p> : null}
                      {a.action ? (
                        <p className="cw-transit-action">→ {a.action}</p>
                      ) : null}
                      {a.keywords?.length ? (
                        <div className="cw-transit-keywords">
                          {a.keywords.map((kw) => (
                            <span key={kw} className="cw-transit-keyword-tag">{kw}</span>
                          ))}
                        </div>
                      ) : null}
                      <TransitProgressBar timing={a.timing} nowDate={nowDate} transitObject={a.transit_object} />
                      <div className="cw-transit-positions">
                        {tp ? (
                          <div className="cw-pos-line">
                            <span className="cw-pos-glyph">{OBJECT_GLYPHS[a.transit_object]}</span>
                            <span className="cw-pos-name">{t(`planet.${a.transit_object}`)}</span>
                            <span className="cw-pos-deg">{tp.degree}°{String(tp.minute).padStart(2, "0")}′</span>
                            <span className="cw-pos-sign">{SIGN_GLYPHS[tp.sign]} {t(`sign.${tp.sign}`)}</span>
                            {tp.natal_house ? <span className="cw-pos-house">△{tp.natal_house}</span> : null}
                            {tp.retrograde ? <span className="cw-pos-retro">Ⓡ</span> : null}
                          </div>
                        ) : null}
                        {np ? (
                          <div className="cw-pos-line">
                            <span className="cw-pos-glyph">{OBJECT_GLYPHS[a.natal_object]}</span>
                            <span className="cw-pos-name">{t(`planet.${a.natal_object}`)}</span>
                            <span className="cw-pos-deg">{np.degree}°{String(np.minute).padStart(2, "0")}′</span>
                            <span className="cw-pos-sign">{SIGN_GLYPHS[np.sign]} {t(`sign.${np.sign}`)}</span>
                            {np.house ? <span className="cw-pos-house">△{np.house}</span> : null}
                            {np.retrograde ? <span className="cw-pos-retro">Ⓡ</span> : null}
                          </div>
                        ) : null}
                      </div>
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
