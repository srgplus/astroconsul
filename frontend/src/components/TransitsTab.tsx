import { useEffect, useRef, useState } from "react"
import { fetchTransitReport, fetchTransitTimeline, resolveLocation } from "../api"
import type {
  ActiveAspect,
  ProfileDetailResponse,
  TimelineItem,
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

const STRENGTH_ORDER = ["exact", "strong", "moderate", "wide"]

function todayDate(): string {
  const d = new Date()
  return d.toISOString().slice(0, 10)
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
  const d = new Date(base)
  d.setDate(d.getDate() + days)
  return d.toISOString().slice(0, 10)
}

function formatUtc(iso: string | null): string {
  if (!iso) return "—"
  try {
    const d = new Date(iso)
    return d.toLocaleDateString(undefined, {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    })
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
  const [resolving, setResolving] = useState(false)
  const [resolvedLabel, setResolvedLabel] = useState<string | null>(null)

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

    // Use the already-fetched report from App.tsx if available
    setReport(initialReport ?? null)
    setTimeline([])
    setError(null)
    setResolvedLabel(null)
  }, [activeDetail?.profile.profile_id])

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
        <div className="eyebrow">Transits</div>
        <h2>Transit report{activeDetail ? ` — ${activeDetail.profile.profile_name}` : ""}</h2>
        <p>Compute active transits for a given moment.</p>
      </div>

      <form className="transit-form" onSubmit={handleSubmit}>
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
                  {new Date(report.snapshot.transit_utc_datetime).toLocaleString()} UTC
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
            <table className="aspect-table">
              <thead>
                <tr>
                  <th>Transit</th>
                  <th>Aspect</th>
                  <th>Natal</th>
                  <th>Orb</th>
                  <th>Strength</th>
                  <th>Start</th>
                  <th>Exact</th>
                  <th>End</th>
                </tr>
              </thead>
              <tbody>
                {sortedAspects.map((a, i) => (
                  <tr key={`${a.transit_object}-${a.aspect}-${a.natal_object}-${i}`}>
                    <td>{a.transit_object}</td>
                    <td className="aspect-glyph">
                      {ASPECT_GLYPHS[a.aspect] ?? a.aspect}
                    </td>
                    <td>{a.natal_object}</td>
                    <td>{a.orb.toFixed(2)}°</td>
                    <td>
                      <span className={`strength-badge strength-${a.strength}`}>
                        {a.strength}
                      </span>
                      {a.timing?.status ? (
                        <span className={`timing-status timing-status--${a.timing.status}`}>
                          {" "}{a.timing.status}
                        </span>
                      ) : null}
                      {a.timing?.duration_hours ? (
                        <span className="timing-duration">
                          {" · "}{formatDuration(a.timing.duration_hours)}
                        </span>
                      ) : null}
                    </td>
                    <td className="timing-cell">{formatUtc(a.timing?.start_utc ?? null)}</td>
                    <td className="timing-cell">{formatUtc(a.timing?.exact_utc ?? null)}</td>
                    <td className="timing-cell">{formatUtc(a.timing?.end_utc ?? null)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <div className="transit-empty">
              <span>No active aspects found for this moment.</span>
            </div>
          )}

          {timeline.length ? (
            <div className="timeline-section">
              <h3>Upcoming transits (±7 days)</h3>
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
            </div>
          ) : null}
        </div>
      ) : null}
    </section>
  )
}
