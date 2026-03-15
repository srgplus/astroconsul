import { useState, useEffect, useRef } from "react"
import type { TransitReportResponse, ProfileDetailResponse, ActiveAspect, AspectTiming } from "../types"
import type { PlaceCandidate } from "../api"
import { LocationAutocomplete } from "./LocationAutocomplete"
import { zoneColor, FEELS_EMOJI, FEELS_MOOD } from "../tii-zones"

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
  onGuideOpen?: () => void
  onTransitSettings?: (date: string, time: string, tz: string, location: string) => void
}

export function DailyWeather({ transitReport, activeDetail, onGuideOpen, onTransitSettings }: Props) {
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
  const mood = FEELS_MOOD[feelsLike] ?? ""

  const tz = transitReport.snapshot?.transit_timezone ?? ""
  const tzLabel = tz ? tz.replace(/\//g, " / ").replace(/_/g, " ").toUpperCase() : ""

  function openSettings() {
    const snap = transitReport.snapshot
    try {
      const utcIso = snap?.transit_utc_datetime ?? ""
      const snapTz = snap?.transit_timezone || undefined
      const d = new Date(utcIso.endsWith("Z") ? utcIso : utcIso + "Z")
      // Compute local date (YYYY-MM-DD) from UTC datetime + timezone
      const localParts = d.toLocaleString("en-CA", { timeZone: snapTz, year: "numeric", month: "2-digit", day: "2-digit" })
      setEditDate(localParts) // en-CA gives YYYY-MM-DD format
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
        <span className="cw-compact__feels" style={{ color: accent }}>{feelsLike}</span>
        <span className="cw-compact__tension">T {Math.round(tensionRatio * 100)}%</span>
        {heroTimeLabel ? <span className="cw-compact__date" onClick={openSettings}>{heroTimeLabel}</span> : null}
      </div>

      <div className="cw-hero" ref={heroRef}>
        {tzLabel ? <div className="cw-location">{tzLabel}</div> : null}
        <div className="cw-title">{activeDetail.profile.profile_name}</div>

        {heroTimeLabel ? (
          <div className="cw-hero-date" onClick={openSettings}>
            {heroTimeLabel}
          </div>
        ) : null}

        <div className="cw-emoji">{emoji}</div>

        <div className="cw-tii">{Math.round(tii)}&deg;</div>
        <div className="cw-tii-label">INTENSITY</div>

        <div className="cw-feels" style={{ color: accent }}>{feelsLike}</div>
        <div className="cw-mood">{mood}</div>

        <div className="cw-tension-bar">
          <div className="cw-tension-bar__track">
            <div
              className="cw-tension-bar__fill"
              style={{ width: `${Math.round(tensionRatio * 100)}%`, background: accent }}
            />
          </div>
          <span className="cw-tension-bar__label">Tension {Math.round(tensionRatio * 100)}%</span>
        </div>
      </div>

      {settingsOpen ? (
        <div className="settings-overlay" onClick={() => setSettingsOpen(false)}>
          <div className="settings-popup" onClick={(e) => e.stopPropagation()}>
            <div className="settings-popup-head">
              <h3>Transit Settings</h3>
              <button type="button" className="settings-close" onClick={() => setSettingsOpen(false)}>&times;</button>
            </div>
            <form className="transit-form" onSubmit={handleSubmit}>
              <div className="transit-fields">
                <label className="transit-field">
                  <span className="transit-field-label">Date</span>
                  <input type="date" value={editDate} onChange={(e) => setEditDate(e.target.value)} required />
                </label>
                <label className="transit-field">
                  <span className="transit-field-label">Time</span>
                  <input type="time" step="1" value={editTime} onChange={(e) => setEditTime(e.target.value)} required />
                </label>
              </div>
              <div className="transit-field transit-field--full">
                <span className="transit-field-label">Location</span>
                <LocationAutocomplete
                  value={editLoc}
                  onChange={setEditLoc}
                  onSelect={(place: PlaceCandidate) => {
                    setEditLoc(place.display_name)
                    if (place.timezone) setEditTz(place.timezone)
                  }}
                  placeholder="Search city..."
                />
              </div>
              <label className="transit-field transit-field--full">
                <span className="transit-field-label">Timezone</span>
                <input type="text" value={editTz} readOnly placeholder="Auto-filled from location" />
              </label>
              <div className="transit-actions">
                <button type="submit" className="status">Generate Transit Report</button>
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
    // Fallback: show UT time
    const d = snapshot.transit_date ?? ""
    const t = (snapshot.transit_time_ut ?? "").slice(0, 5)
    return `${d}, ${t} UT`
  }
}

/** Format ISO date string to "14 Mar" */
function shortDate(iso: string | null | undefined): string {
  if (!iso) return ""
  try {
    const d = new Date(iso)
    if (isNaN(d.getTime())) return ""
    return `${d.getUTCDate()} ${d.toLocaleString("en", { month: "short", timeZone: "UTC" })}`
  } catch {
    return ""
  }
}

/** Progress bar for a single transit aspect with influence gradient */
function TransitProgressBar({ timing, nowDate, transitObject }: {
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

  const nowPct = Math.max(0, Math.min(100, ((now - start) / total) * 100))

  let exactPct: number | null = null
  if (timing.exact_utc) {
    const exact = new Date(timing.exact_utc).getTime()
    exactPct = Math.max(0, Math.min(100, ((exact - start) / total) * 100))
  }

  const pFactor = PLANET_FACTOR[transitObject] ?? 1.0
  const peakPct = exactPct ?? 50
  const gradient = buildTransitGradient(peakPct, pFactor)
  const dotColor = peakColor(pFactor)
  const isOuter = pFactor > 1.0

  const startLabel = shortDate(timing.start_utc)
  const exactLabel = shortDate(timing.exact_utc)
  const endLabel = shortDate(timing.end_utc)

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
        {exactPct !== null ? (
          <div
            className="transit-bar__exact"
            style={{ left: `${exactPct}%` }}
          />
        ) : null}
        <div
          className="transit-bar__now"
          style={{ left: `${nowPct}%`, borderColor: dotColor }}
        />
      </div>
      <div className="transit-bar__labels">
        <span>{startLabel}</span>
        {exactPct !== null && exactLabel ? (
          <span className="transit-bar__exact-label" style={{ left: `${exactPct}%` }}>{exactLabel}</span>
        ) : null}
        <span>{endLabel}</span>
      </div>
    </div>
  )
}

export function ActiveTransitsWidget({ transitReport }: {
  transitReport: TransitReportResponse
}) {
  const aspects = transitReport.active_aspects ?? []
  if (!aspects.length) return null

  const dateLabel = formatTransitDateTime(transitReport.snapshot)
  const nowDate = transitReport.snapshot?.transit_date ?? ""

  return (
    <div className="cw-transits">
      <div className="cw-transits-header">
        <span className="cw-transits-title">Transits</span>
        {dateLabel ? <span className="cw-transits-date">{dateLabel}</span> : null}
      </div>
      <div className="cw-transit-list">
        {aspects.slice(0, 8).map((a: ActiveAspect, i: number) => {
          const strengthColor = STRENGTH_COLORS[a.strength] ?? "#8E8E93"
          return (
            <div key={`${a.transit_object}-${a.natal_object}-${i}`} className="cw-transit-item">
              <div className="cw-transit-row">
                <span className="cw-transit-glyphs">
                  <span className="cw-glyph-transit">{OBJECT_GLYPHS[a.transit_object] ?? a.transit_object}</span>
                  <span className="cw-glyph-aspect">{ASPECT_GLYPHS[a.aspect] ?? a.aspect}</span>
                  <span className="cw-glyph-natal">{OBJECT_GLYPHS[a.natal_object] ?? a.natal_object}</span>
                </span>
                <span className="cw-transit-orb">{a.orb.toFixed(2)}&deg;</span>
                <span
                  className="cw-transit-strength"
                  style={{ background: `${strengthColor}18`, color: strengthColor }}
                >
                  {a.strength.toUpperCase()}
                </span>
              </div>
              <TransitProgressBar timing={a.timing} nowDate={nowDate} transitObject={a.transit_object} />
            </div>
          )
        })}
      </div>
    </div>
  )
}
