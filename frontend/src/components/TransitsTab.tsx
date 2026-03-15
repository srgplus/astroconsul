import { useEffect, useRef, useState } from "react"
import { fetchTransitReport, fetchTransitTimeline, resolveLocation } from "../api"
import type {
  ActiveAspect,
  NatalPosition,
  ProfileDetailResponse,
  TimelineItem,
  TransitPosition,
  TransitReportResponse,
} from "../types"

type TransitsTabProps = {
  activeProfileId: string | null
  activeDetail: ProfileDetailResponse | null
  onTransitReport?: (report: TransitReportResponse) => void
  initialReport?: TransitReportResponse | null
}

const ASPECT_GLYPHS: Record<string, string> = {
  conjunction: "\u260C",
  sextile: "\u26B9",
  square: "\u25A1",
  trine: "\u25B3",
  opposition: "\u260D",
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

/** Display names that differ from backend IDs */
const DISPLAY_NAMES: Record<string, string> = {
  Selena: "Selena",
}

function displayName(id: string): string {
  return DISPLAY_NAMES[id] ?? id
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

/** Groups for categorizing aspects */
const PERSONAL_IDS = new Set(["Sun", "Moon", "Mercury", "Venus", "Mars"])
const OUTER_IDS = new Set(["Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"])

function categorizeAspect(a: ActiveAspect): string {
  if (PERSONAL_IDS.has(a.transit_object)) return "Personal Planets"
  if (OUTER_IDS.has(a.transit_object)) return "Outer Planets"
  return "Special Points"
}

const STRENGTH_ORDER = ["exact", "strong", "moderate", "wide"]

function todayDate(): string {
  const d = new Date()
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, "0")
  const day = String(d.getDate()).padStart(2, "0")
  return `${y}-${m}-${day}`
}

function nowTime(): string {
  const d = new Date()
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}:00`
}

function browserTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone
  } catch {
    return "UTC"
  }
}

function offsetDate(base: string, days: number): string {
  const d = new Date(base + "T12:00:00")
  d.setDate(d.getDate() + days)
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, "0")
  const day = String(d.getDate()).padStart(2, "0")
  return `${y}-${m}-${day}`
}

function formatUtc(iso: string | null): string {
  if (!iso) return "—"
  try {
    const d = new Date(iso)
    const day = d.getDate()
    const mon = d.toLocaleString("en", { month: "short" })
    const hh = String(d.getHours()).padStart(2, "0")
    const mm = String(d.getMinutes()).padStart(2, "0")
    return `${day} ${mon}, ${hh}:${mm}`
  } catch {
    return iso
  }
}

function formatDuration(hours: number | null | undefined): string {
  if (hours == null) return ""
  if (hours < 1) return `${Math.round(hours * 60)} min`
  if (hours < 48) return `${Math.round(hours)} h`
  return `${Math.round(hours / 24)} d`
}

export function TransitsTab({ activeProfileId, activeDetail, onTransitReport, initialReport }: TransitsTabProps) {
  const [transitDate, setTransitDate] = useState(todayDate)
  const [transitTime, setTransitTime] = useState(nowTime)
  const [timezone, setTimezone] = useState(browserTimezone)
  const [locationName, setLocationName] = useState("")

  const [report, setReport] = useState<TransitReportResponse | null>(null)
  const [timeline, setTimeline] = useState<TimelineItem[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [filter, setFilter] = useState<"all" | "strong">("all")
  const [timelineOpen, setTimelineOpen] = useState(false)
  const [resolving, setResolving] = useState(false)
  const [resolvedLabel, setResolvedLabel] = useState<string | null>(null)
  const [settingsOpen, setSettingsOpen] = useState(false)

  const controllerRef = useRef<AbortController | null>(null)

  // Pre-fill form from localStorage saved params, then profile's latest_transit, then defaults
  useEffect(() => {
    let filled = false
    if (activeProfileId) {
      try {
        const saved = JSON.parse(localStorage.getItem("transitParams") || "{}")
        const p = saved[activeProfileId]
        if (p?.transitDate && p?.transitTime) {
          setTransitDate(p.transitDate)
          setTransitTime(p.transitTime)
          if (p.timezone) setTimezone(p.timezone)
          if (p.locationName) setLocationName(p.locationName)
          filled = true
        }
      } catch { /* ignore */ }
    }

    if (!filled) {
      const lt = activeDetail?.profile.latest_transit
      if (lt) {
        setTransitDate(lt.transit_date)
        setTransitTime(lt.transit_time)
        if (lt.timezone) setTimezone(lt.timezone)
        if (lt.location_name) setLocationName(lt.location_name)
      } else {
        setTransitDate(todayDate())
        setTransitTime(nowTime())
        setTimezone(browserTimezone())
        setLocationName("")
      }
    }

    setReport(null)
    setTimeline([])
    setError(null)
    setResolvedLabel(null)
  }, [activeDetail?.profile.profile_id])

  // Sync initialReport from App.tsx (arrives asynchronously after auto-fetch)
  useEffect(() => {
    if (initialReport) setReport(initialReport)
  }, [initialReport])

  async function handleResolveLocation() {
    if (!locationName.trim()) return
    setResolving(true)
    setResolvedLabel(null)
    try {
      const result = await resolveLocation(locationName.trim())
      setTimezone(result.timezone)
      setLocationName(result.resolved_name)
      setResolvedLabel(`${result.resolved_name} → ${result.timezone}`)
    } catch {
      setResolvedLabel("Could not resolve location")
    } finally {
      setResolving(false)
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!activeProfileId) return

    controllerRef.current?.abort()
    const controller = new AbortController()
    controllerRef.current = controller

    setLoading(true)
    setError(null)

    try {
      const reportResult = await fetchTransitReport(
        activeProfileId,
        {
          transit_date: transitDate,
          transit_time: transitTime,
          timezone: timezone || null,
          location_name: locationName || null,
          include_timing: true,
        },
        controller.signal,
      )

      if (controller.signal.aborted) return
      setReport(reportResult)
      onTransitReport?.(reportResult)

      // Persist last transit params per profile
      try {
        const saved = JSON.parse(localStorage.getItem("transitParams") || "{}")
        saved[activeProfileId] = { transitDate, transitTime, timezone, locationName }
        localStorage.setItem("transitParams", JSON.stringify(saved))
      } catch { /* ignore */ }

      // Fire timeline request in parallel
      const timelineResult = await fetchTransitTimeline(
        activeProfileId,
        {
          start_date: offsetDate(transitDate, -7),
          end_date: offsetDate(transitDate, 7),
          timezone: timezone || browserTimezone(),
        },
        controller.signal,
      )

      if (controller.signal.aborted) return
      setTimeline(timelineResult.timeline)
    } catch (err) {
      if (controller.signal.aborted) return
      setError(err instanceof Error ? err.message : "Unknown error")
      setReport(null)
      setTimeline([])
    } finally {
      if (!controller.signal.aborted) setLoading(false)
    }
  }

  const filteredAspects: ActiveAspect[] = (report?.active_aspects ?? []).filter((a) => {
    if (filter === "strong") return a.strength === "exact" || a.strength === "strong"
    return true
  })

  const sortedAspects = [...filteredAspects].sort((a, b) => {
    const ai = STRENGTH_ORDER.indexOf(a.strength)
    const bi = STRENGTH_ORDER.indexOf(b.strength)
    if (ai !== bi) return ai - bi
    return a.orb - b.orb
  })

  // Build lookup maps for transit & natal positions
  const transitMap: Record<string, TransitPosition> = {}
  for (const tp of report?.transit_positions ?? []) {
    transitMap[tp.id] = tp
  }
  const natalMap: Record<string, NatalPosition> = {}
  for (const np of report?.natal_positions ?? []) {
    natalMap[np.id] = np
  }
  // Also map angle positions as natal
  for (const ap of report?.angle_positions ?? []) {
    natalMap[ap.id] = { ...ap, house: 0, retrograde: null, speed: null } as NatalPosition
  }

  // Group sorted aspects by category
  const groupedAspects: { label: string; aspects: ActiveAspect[] }[] = []
  const groupOrder = ["Personal Planets", "Outer Planets", "Special Points"]
  const groups: Record<string, ActiveAspect[]> = {}
  for (const a of sortedAspects) {
    const cat = categorizeAspect(a)
    if (!groups[cat]) groups[cat] = []
    groups[cat].push(a)
  }
  for (const label of groupOrder) {
    if (groups[label]?.length) groupedAspects.push({ label, aspects: groups[label] })
  }

  if (!activeProfileId) {
    return (
      <section className="card">
        <div className="card-head">
          <div className="eyebrow">Transits</div>
          <h2>Select a profile first</h2>
          <p>Choose a natal profile on the Profile tab to generate transit reports.</p>
        </div>
      </section>
    )
  }

  return (
    <section className="card">
      <div className="card-head">
        <div className="transit-head-row">
          <div>
            <div className="eyebrow">Transits</div>
            <h2>Transit report{activeDetail ? ` — ${activeDetail.profile.profile_name}` : ""}</h2>
          </div>
        </div>
      </div>

      {settingsOpen ? (
        <div className="settings-overlay" onClick={() => setSettingsOpen(false)}>
          <div className="settings-popup" onClick={(e) => e.stopPropagation()}>
            <div className="settings-popup-head">
              <h3>Transit Settings</h3>
              <button type="button" className="settings-close" onClick={() => setSettingsOpen(false)}>×</button>
            </div>
            <form className="transit-form" onSubmit={(e) => { handleSubmit(e); setSettingsOpen(false) }}>
              <div className="transit-fields">
                <label className="transit-field">
                  <span className="transit-field-label">Date</span>
                  <input
                    type="date"
                    value={transitDate}
                    onChange={(e) => setTransitDate(e.target.value)}
                    required
                  />
                </label>
                <label className="transit-field">
                  <span className="transit-field-label">Time</span>
                  <input
                    type="time"
                    step="1"
                    value={transitTime}
                    onChange={(e) => setTransitTime(e.target.value)}
                    required
                  />
                </label>
                <label className="transit-field">
                  <span className="transit-field-label">Timezone</span>
                  <input
                    type="text"
                    value={timezone}
                    onChange={(e) => setTimezone(e.target.value)}
                    placeholder="America/New_York"
                  />
                </label>
                <label className="transit-field">
                  <span className="transit-field-label">Location (optional)</span>
                  <input
                    type="text"
                    value={locationName}
                    onChange={(e) => { setLocationName(e.target.value); setResolvedLabel(null) }}
                    onBlur={() => { if (locationName.trim()) handleResolveLocation() }}
                    placeholder="e.g. Moscow"
                  />
                </label>
              </div>
              {resolvedLabel ? (
                <div className="edit-resolve-hint" style={{ marginTop: 8 }}>{resolvedLabel}</div>
              ) : null}
              <div className="transit-actions">
                <button type="submit" className="status" disabled={loading}>
                  {loading ? "Computing…" : "Generate Transit Report"}
                </button>
              </div>
            </form>
          </div>
        </div>
      ) : null}

      {error ? (
        <div className="transit-result error-state">
          <strong>Error</strong>
          <span>{error}</span>
        </div>
      ) : null}

      {report && !error ? (
        <div className="transit-result">
          <div className="transit-result-head">
            <div className="transit-snapshot">
              {report.snapshot?.transit_utc_datetime ? (
                <span>
                  {(() => {
                    try {
                      const utcIso = report.snapshot!.transit_utc_datetime
                      const tz = report.snapshot!.transit_timezone || undefined
                      const d = new Date(utcIso.endsWith("Z") ? utcIso : utcIso + "Z")
                      return d.toLocaleString("en-US", { timeZone: tz, dateStyle: "short", timeStyle: "long" })
                    } catch {
                      return new Date(report.snapshot!.transit_utc_datetime).toLocaleString() + " UTC"
                    }
                  })()}
                </span>
              ) : null}
              {report.snapshot?.transit_location_name ? (
                <span> · {report.snapshot.transit_location_name}</span>
              ) : null}
            </div>
            <div className="filter-chips">
              <button
                type="button"
                className={`filter-chip ${filter === "all" ? "active" : ""}`}
                onClick={() => setFilter("all")}
              >
                All (&lt; 2°)
              </button>
              <button
                type="button"
                className={`filter-chip ${filter === "strong" ? "active" : ""}`}
                onClick={() => setFilter("strong")}
              >
                Exact + Strong (&lt; 1°)
              </button>
            </div>
          </div>

          {sortedAspects.length ? (
            <div className="aspect-cards-wrapper">
              <div className="aspect-cards-header">
                <span>Transit</span>
                <span className="aspect-cards-header-center">Aspect</span>
                <span className="aspect-cards-header-right">Natal</span>
              </div>
              {groupedAspects.map((group) => (
                <div key={group.label} className="aspect-group">
                  <div className="aspect-group-label">{group.label.toUpperCase()}</div>
                  {group.aspects.map((a, i) => {
                    const tp = transitMap[a.transit_object]
                    const np = natalMap[a.natal_object]
                    return (
                      <div
                        key={`${a.transit_object}-${a.aspect}-${a.natal_object}-${i}`}
                        className="aspect-card"
                      >
                        {/* Row 1: transit — aspect+orb — natal */}
                        <div className="aspect-card-row1">
                          <div className="aspect-card-planet transit-side">
                            <span className="planet-glyph">{OBJECT_GLYPHS[a.transit_object] ?? ""}</span>
                            <span className="planet-name">
                              {displayName(a.transit_object)}
                              {tp?.retrograde ? <span className="retro-badge">Ⓡ</span> : null}
                            </span>
                            <span className="planet-meta">
                              {tp ? `${SIGN_GLYPHS[tp.sign] ?? ""} ${tp.sign} · △${tp.natal_house}` : ""}
                            </span>
                          </div>
                          <div className="aspect-card-center">
                            <div className="aspect-card-center-row">
                              <span className="aspect-glyph-symbol">{ASPECT_GLYPHS[a.aspect] ?? ""}</span>
                              <span className="aspect-name">{a.aspect}</span>
                            </div>
                            <span className="aspect-orb">{a.orb.toFixed(2)}°</span>
                          </div>
                          <div className="aspect-card-planet natal-side">
                            <span className="planet-glyph">{OBJECT_GLYPHS[a.natal_object] ?? ""}</span>
                            <span className="planet-name">
                              {displayName(a.natal_object)}
                              {np?.retrograde ? <span className="retro-badge">Ⓡ</span> : null}
                            </span>
                            <span className="planet-meta">
                              {np ? `${SIGN_GLYPHS[np.sign] ?? ""} ${np.sign}${np.house ? ` · △${np.house}` : ""}` : ""}
                            </span>
                          </div>
                        </div>

                        {/* Row 3: strength, status, duration + timeline on same line */}
                        <div className="aspect-card-row3">
                          <span className={`strength-badge strength-${a.strength}`}>
                            {a.strength}
                          </span>
                          {a.timing?.status ? (
                            <span className={`timing-status timing-status--${a.timing.status}`}>
                              <span className="timing-dot">●</span> {a.timing.status}
                            </span>
                          ) : null}
                          {a.timing?.duration_hours ? (
                            <span className="timing-duration">
                              {formatDuration(a.timing.duration_hours)}
                            </span>
                          ) : null}
                          {a.timing ? (
                            <>
                              <span className="timing-sep">|</span>
                              <span className="timeline-marker timeline-start">▶ {formatUtc(a.timing.start_utc)}</span>
                              <span className="timeline-marker timeline-exact">◎ {formatUtc(a.timing.exact_utc)}</span>
                              <span className="timeline-marker timeline-end">✓ {formatUtc(a.timing.end_utc)}</span>
                            </>
                          ) : null}
                        </div>
                      </div>
                    )
                  })}
                </div>
              ))}
            </div>
          ) : (
            <div className="transit-empty">
              <span>No active aspects found for this moment.</span>
            </div>
          )}

          {timeline.length ? (
            <div className="timeline-section">
              <button
                type="button"
                className="timeline-toggle"
                onClick={() => setTimelineOpen((v) => !v)}
              >
                <span className="timeline-toggle-arrow">{timelineOpen ? "▾" : "▸"}</span>
                Upcoming transits (±7 days)
              </button>
              {timelineOpen ? (
              <table className="aspect-table timeline-table">
                <thead>
                  <tr>
                    <th>Transit</th>
                    <th>Aspect</th>
                    <th>Natal</th>
                    <th>When</th>
                    <th>Strength</th>
                  </tr>
                </thead>
                <tbody>
                  {timeline.slice(0, 20).map((t, i) => (
                    <tr key={`tl-${t.transit}-${t.aspect}-${t.natal}-${i}`}>
                      <td>{t.transit}</td>
                      <td className="aspect-glyph">
                        {ASPECT_GLYPHS[t.aspect] ?? t.aspect}
                      </td>
                      <td>{t.natal}</td>
                      <td>{formatUtc(t.display_utc)}</td>
                      <td>
                        <span className={`strength-badge strength-${t.strength}`}>
                          {t.strength}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              ) : null}
            </div>
          ) : null}
        </div>
      ) : null}
    </section>
  )
}
