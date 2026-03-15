import { useEffect, useState, useCallback, useRef, Fragment } from "react"
import { useAuth } from "./contexts/AuthContext"
import AuthScreen from "./components/AuthScreen"
import { fetchHealth, fetchProfiles, fetchProfileDetail, fetchTransitReport } from "./api"
import { ProfileList, type ProfileTiiData } from "./components/ProfileList"
import { ProfileSummaryCard, NatalPositionsTable, NatalAspectsTable } from "./components/ProfileDetail"
import { DailyWeather, ActiveTransitsWidget } from "./components/DailyWeather"
import { TiiGuide } from "./components/TiiGuide"
import { ProfileEditForm } from "./components/ProfileEditForm"
import { TransitsTab } from "./components/TransitsTab"
import { NatalZodiacRing } from "./components/NatalZodiacRing"
import type { HealthResponse, ProfileSummary, ProfileDetailResponse, TransitReportResponse, NatalPosition } from "./types"

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

function coerceNumber(value: number | string | null | undefined): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value === "string") { const n = Number(value); return Number.isFinite(n) ? n : null }
  return null
}

type Theme = "system" | "light" | "dark"
type ExpandedWidget = null | "summary" | "planets" | "aspects" | "transits"

function useTheme() {
  const [theme, setTheme] = useState<Theme>(() => (localStorage.getItem("theme") as Theme) || "system")

  useEffect(() => {
    const root = document.documentElement
    if (theme === "system") {
      root.removeAttribute("data-theme")
      localStorage.removeItem("theme")
    } else {
      root.setAttribute("data-theme", theme)
      localStorage.setItem("theme", theme)
    }
  }, [theme])

  return [theme, setTheme] as const
}

/** Compact preview of natal planet positions for a widget card */
function PlanetsPreview({ positions }: { positions: NatalPosition[] }) {
  const preview = positions.filter((p) =>
    ["Sun", "Moon", "Mercury", "Venus", "Mars", "ASC", "MC"].includes(p.id)
  ).slice(0, 5)

  return (
    <div className="widget-planets-preview">
      {preview.map((p) => (
        <div key={p.id} className="widget-planet-row">
          <span className="widget-planet-glyph">{OBJECT_GLYPHS[p.id] ?? ""}</span>
          <span className="widget-planet-name">{p.id}</span>
          <span className="widget-planet-sign">{SIGN_GLYPHS[p.sign] ?? ""} {p.sign}</span>
          <span className="widget-planet-deg">{p.degree}°{String(p.minute).padStart(2, "0")}′</span>
        </div>
      ))}
    </div>
  )
}

/** Compact preview of top natal aspects for a widget card */
function AspectsPreview({ aspects }: { aspects: { p1: string; p2: string; aspect: string; orb: number }[] }) {
  const sorted = [...aspects].sort((a, b) => a.orb - b.orb).slice(0, 4)

  return (
    <div className="widget-aspects-preview">
      {sorted.map((a, i) => (
        <div key={`${a.p1}-${a.p2}-${i}`} className="widget-aspect-row">
          <span className="widget-planet-glyph">{OBJECT_GLYPHS[a.p1] ?? ""}</span>
          <span className="widget-aspect-glyph">{ASPECT_GLYPHS[a.aspect] ?? ""}</span>
          <span className="widget-planet-glyph">{OBJECT_GLYPHS[a.p2] ?? ""}</span>
          <span className="widget-aspect-name">{a.aspect}</span>
          <span className="widget-aspect-orb">{a.orb.toFixed(1)}°</span>
        </div>
      ))}
    </div>
  )
}

/** Compact preview of transit aspects for widget card */
function TransitAspectsPreview({ report }: { report: TransitReportResponse | null }) {
  const aspects = (report?.active_aspects ?? [])
    .filter((a) => a.strength === "exact" || a.strength === "strong")
    .slice(0, 4)

  if (!aspects.length) return <div className="widget-empty-hint">No strong aspects</div>

  return (
    <div className="widget-aspects-preview">
      {aspects.map((a, i) => (
        <div key={`${a.transit_object}-${a.natal_object}-${i}`} className="widget-aspect-row">
          <span className="widget-planet-glyph">{OBJECT_GLYPHS[a.transit_object] ?? ""}</span>
          <span className="widget-aspect-glyph">{ASPECT_GLYPHS[a.aspect] ?? ""}</span>
          <span className="widget-planet-glyph">{OBJECT_GLYPHS[a.natal_object] ?? ""}</span>
          <span className="widget-aspect-name">{a.aspect}</span>
          <span className="widget-aspect-orb">{a.orb.toFixed(2)}°</span>
        </div>
      ))}
    </div>
  )
}

export function App() {
  const { user, loading: authLoading, signOut } = useAuth()
  const [theme, setTheme] = useTheme()
  const [health, setHealth] = useState<HealthResponse | null>(null)
  const [profiles, setProfiles] = useState<ProfileSummary[]>([])
  const [activeProfileId, setActiveProfileId] = useState<string | null>(null)
  const [activeDetail, setActiveDetail] = useState<ProfileDetailResponse | null>(null)
  const [bootError, setBootError] = useState<string | null>(null)
  const [detailError, setDetailError] = useState<string | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [isEditing, setIsEditing] = useState(false)
  const [transitReport, setTransitReport] = useState<TransitReportResponse | null>(null)
  const [wheelExpanded, setWheelExpanded] = useState(false)
  const [searchQuery, setSearchQuery] = useState("")
  const [expandedWidget, setExpandedWidget] = useState<ExpandedWidget>(null)
  const [wheelMode, setWheelMode] = useState<"natal" | "transit">("transit")
  const [tiiMap, setTiiMap] = useState<Record<string, ProfileTiiData>>({})
  const [guideOpen, setGuideOpen] = useState(false)
  const autoFetchRef = useRef<AbortController | null>(null)
  const [fetchTrigger, setFetchTrigger] = useState(0)
  const [transitLoading, setTransitLoading] = useState(false)
  // Content is ready when both detail and transit are loaded (no flicker)
  const contentLoading = detailLoading || transitLoading

  useEffect(() => {
    let cancelled = false

    async function bootstrap() {
      try {
        const [healthPayload, profilesPayload] = await Promise.all([
          fetchHealth(),
          fetchProfiles(),
        ])

        if (cancelled) return

        setHealth(healthPayload)
        setProfiles(profilesPayload.profiles)
        setActiveProfileId((current) => current || profilesPayload.profiles[0]?.profile_id || null)
      } catch (err) {
        if (!cancelled) {
          setBootError(err instanceof Error ? err.message : "Unknown error")
        }
      }
    }

    bootstrap()
    return () => { cancelled = true }
  }, [])

  useEffect(() => {
    if (!activeProfileId) {
      setActiveDetail(null)
      setDetailError(null)
      setDetailLoading(false)
      return
    }

    const controller = new AbortController()
    setDetailLoading(true)
    setDetailError(null)

    fetchProfileDetail(activeProfileId, controller.signal)
      .then((payload) => {
        setActiveDetail(payload)
      })
      .catch((err) => {
        if (controller.signal.aborted) return
        setActiveDetail(null)
        setDetailError(err instanceof Error ? err.message : "Unknown error")
      })
      .finally(() => {
        if (!controller.signal.aborted) setDetailLoading(false)
      })

    return () => controller.abort()
  }, [activeProfileId])

  // Fetch TII for all profiles (lightweight — no timing)
  // Uses saved per-profile params from localStorage so sidebar matches hero values
  useEffect(() => {
    if (!profiles.length) return
    const controller = new AbortController()
    const now = new Date()
    const browserTz = Intl.DateTimeFormat().resolvedOptions().timeZone
    const defaultDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`
    const defaultTime = `${String(now.getHours()).padStart(2, "0")}:00`

    Promise.all(
      profiles.map((p) => {
        return fetchTransitReport(p.profile_id, {
          transit_date: defaultDate,
          transit_time: defaultTime,
          timezone: browserTz,
          include_timing: false,
        }, controller.signal)
          .then((r) => ({ id: p.profile_id, r }))
          .catch(() => null)
      })
    ).then((results) => {
      if (controller.signal.aborted) return
      const map: Record<string, ProfileTiiData> = {}
      for (const item of results) {
        if (!item || item.r.tii == null) continue
        map[item.id] = {
          tii: item.r.tii,
          tension_ratio: item.r.tension_ratio ?? 0,
          feels_like: item.r.feels_like ?? "Calm",
          location: item.r.snapshot?.transit_timezone ?? browserTz,
        }
      }
      setTiiMap(map)
    })

    return () => controller.abort()
  }, [profiles])



  // Fetch transit report for active profile — use saved params if available, else current time
  useEffect(() => {
    if (!activeProfileId) {
      setTransitReport(null)
      return
    }

    autoFetchRef.current?.abort()
    const controller = new AbortController()
    autoFetchRef.current = controller
    setTransitLoading(true)
    const browserTz = Intl.DateTimeFormat().resolvedOptions().timeZone

    // Preserve profile's saved timezone & location, only update date/time to "now"
    let savedTz = browserTz
    let savedLoc: string | null = null
    try {
      const saved = JSON.parse(localStorage.getItem("transitParams") || "{}")
      const p = saved[activeProfileId]
      if (p?.timezone) savedTz = p.timezone
      if (p?.locationName) savedLoc = p.locationName
    } catch { /* ignore */ }

    const now = new Date()
    const year = now.getFullYear()
    const month = String(now.getMonth() + 1).padStart(2, "0")
    const day = String(now.getDate()).padStart(2, "0")
    const params = {
      transit_date: `${year}-${month}-${day}`,
      transit_time: `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`,
      timezone: savedTz,
      location_name: savedLoc,
      include_timing: true,
    }

    function applyReport(report: TransitReportResponse) {
      if (controller.signal.aborted) return
      setTransitReport(report)
      setTransitLoading(false)
      if (report.tii != null) {
        setTiiMap((prev) => ({
          ...prev,
          [activeProfileId]: {
            tii: report.tii!,
            tension_ratio: report.tension_ratio ?? 0,
            feels_like: report.feels_like ?? "Calm",
            location: report.snapshot?.transit_timezone ?? savedTz,
          },
        }))
      }
    }

    fetchTransitReport(activeProfileId, params, controller.signal)
      .then(applyReport)
      .catch(() => {
        if (controller.signal.aborted) return
        // Retry with plain browser timezone (saved params may be stale/invalid)
        const fallback = {
          transit_date: params.transit_date,
          transit_time: params.transit_time,
          timezone: browserTz,
          include_timing: true,
        }
        fetchTransitReport(activeProfileId, fallback, controller.signal)
          .then(applyReport)
          .catch(() => {
            if (!controller.signal.aborted) {
              setTransitReport(null)
              setTransitLoading(false)
            }
          })
      })

    return () => controller.abort()
  }, [activeProfileId, fetchTrigger])

  const refreshProfile = useCallback(async () => {
    setIsEditing(false)
    if (activeProfileId) {
      try {
        const [detail, profilesPayload] = await Promise.all([
          fetchProfileDetail(activeProfileId),
          fetchProfiles(),
        ])
        setActiveDetail(detail)
        setProfiles(profilesPayload.profiles)
      } catch {
        // silent — detail will remain stale
      }
    }
  }, [activeProfileId])

  const natalPositions = activeDetail?.chart.natal_positions ?? []
  const natalAspects = activeDetail?.chart.natal_aspects ?? []
  const totalTransitAspects = transitReport?.active_aspects?.length ?? 0
  const strongTransitAspects = (transitReport?.active_aspects ?? []).filter(
    (a) => a.strength === "exact" || a.strength === "strong"
  ).length

  // Auth gate: show login screen if not authenticated
  if (authLoading) {
    return (
      <main className="app-shell">
        <div className="content-loader" style={{ position: "fixed", inset: 0 }}>
          <div className="content-loader__spinner" />
        </div>
      </main>
    )
  }

  if (!user) {
    return <AuthScreen />
  }

  return (
    <main className="app-shell">
      <div className="main-layout">
        <aside className="sidebar">
          <div className="sidebar-search">
            <input
              type="text"
              placeholder="Search"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>
          <div className="sidebar-scroll">
            <ProfileList
              profiles={searchQuery.trim()
                ? profiles.filter((p) => {
                    const q = searchQuery.toLowerCase()
                    return p.profile_name.toLowerCase().includes(q)
                      || p.username.toLowerCase().includes(q)
                      || (p.location_name ?? "").toLowerCase().includes(q)
                  })
                : profiles}
              activeProfileId={activeProfileId}
              onSelect={(id) => {
                if (id === activeProfileId) {
                  setFetchTrigger((n) => n + 1)
                } else {
                  setActiveProfileId(id)
                }
              }}
              tiiMap={tiiMap}
            />
          </div>
          <div className="sidebar-footer">
            <span className="sidebar-user-email" title={user.email ?? ""}>
              {user.email ?? ""}
            </span>
            <button
              type="button"
              className="sidebar-icon-btn"
              onClick={() => {
                signOut()
                setProfiles([])
                setActiveProfileId(null)
                setActiveDetail(null)
                setTransitReport(null)
              }}
              title="Sign out"
            >
              {"\u23FB"}
            </button>
            <button
              type="button"
              className="sidebar-icon-btn"
              onClick={() => setGuideOpen(true)}
              title="How It Works"
            >
              {"\u2139"}
            </button>
            <button
              type="button"
              className="sidebar-icon-btn"
              onClick={() => setTheme(theme === "dark" ? "light" : theme === "light" ? "system" : "dark")}
              title={`Theme: ${theme}`}
            >
              {theme === "dark" ? "\u263D" : theme === "light" ? "\u2600" : "\u25D0"}
            </button>
          </div>
        </aside>

        <div className="content-pane">
          {contentLoading && activeProfileId ? (
            <div className="content-loader">
              <div className="content-loader__spinner" />
            </div>
          ) : null}
          <div style={{ opacity: contentLoading ? 0 : 1, transition: "opacity 0.2s ease" }}>
          {transitReport && activeDetail ? (
            <DailyWeather
              transitReport={transitReport}
              activeDetail={activeDetail}
              onGuideOpen={() => setGuideOpen(true)}
              onTransitSettings={(date, time, tz, loc) => {
                if (!activeProfileId) return
                autoFetchRef.current?.abort()
                fetchTransitReport(activeProfileId, {
                  transit_date: date,
                  transit_time: time,
                  timezone: tz || undefined,
                  location_name: loc || null,
                  include_timing: true,
                }).then((report) => {
                  setTransitReport(report)
                  try {
                    const saved = JSON.parse(localStorage.getItem("transitParams") || "{}")
                    saved[activeProfileId] = { transitDate: date, transitTime: time, timezone: tz, locationName: loc }
                    localStorage.setItem("transitParams", JSON.stringify(saved))
                  } catch { /* ignore */ }
                  if (report.tii != null) {
                    setTiiMap((prev) => ({
                      ...prev,
                      [activeProfileId!]: {
                        tii: report.tii!,
                        tension_ratio: report.tension_ratio ?? 0,
                        feels_like: report.feels_like ?? "Calm",
                        location: report.snapshot?.transit_timezone ?? "",
                      },
                    }))
                  }
                }).catch(() => {})
              }}
            />
          ) : (
            <header className="sticky-header">
              <h1 className="content-profile-name">{activeDetail?.profile.profile_name || "Select a profile"}</h1>
              {activeDetail ? <span className="content-profile-username">@{activeDetail.profile.username}</span> : null}
            </header>
          )}

          <div className="widget-grid">
            {/* Left column: Natal + Transits */}
            <div className="widget-col-left">
              {/* Natal widget */}
              {activeDetail ? (
                <div className="widget widget--summary" onClick={() => setExpandedWidget("summary")}>
                  <div className="widget-title">Natal</div>
                  <ProfileSummaryCard detail={activeDetail} />
                </div>
              ) : null}

              {/* Active Transits widget */}
              {transitReport ? (
                <div className="widget widget--summary" onClick={() => setExpandedWidget("transits")}>
                  <ActiveTransitsWidget transitReport={transitReport} />
                  <div className="widget-hint">Details</div>
                </div>
              ) : null}
            </div>

            {/* Right column: Wheel (full height) */}
            <div className="widget widget--chart widget--wheel-right" onClick={() => activeDetail && setWheelExpanded(true)}>
              <div className="wheel-mode-toggle" onClick={(e) => e.stopPropagation()}>
                <button type="button" className={wheelMode === "natal" ? "active" : ""} onClick={() => setWheelMode("natal")}>Natal</button>
                <button type="button" className={wheelMode === "transit" ? "active" : ""} onClick={() => setWheelMode("transit")}>Transit</button>
              </div>
              {activeDetail ? (
                <NatalZodiacRing
                  asc={coerceNumber(activeDetail.chart.asc)}
                  mc={coerceNumber(activeDetail.chart.mc)}
                  houses={activeDetail.chart.houses ?? null}
                  planets={(natalPositions)
                    .filter((p) => Number.isFinite(p.longitude))
                    .map((p) => ({
                      id: p.id,
                      longitude: p.longitude,
                      glyph: OBJECT_GLYPHS[p.id] ?? p.id.slice(0, 2),
                    }))}
                  transitPlanets={wheelMode === "transit" ? (transitReport?.transit_positions ?? [])
                    .filter((p) => Number.isFinite(p.longitude))
                    .map((p) => ({
                      id: p.id,
                      longitude: p.longitude,
                      glyph: OBJECT_GLYPHS[p.id] ?? p.id.slice(0, 2),
                    })) : []}
                  transitAspects={wheelMode === "transit" ? (transitReport?.active_aspects ?? [])
                    .filter((a) => a.is_within_orb)
                    .map((a) => ({
                      transit_object: a.transit_object,
                      natal_object: a.natal_object,
                      aspect: a.aspect,
                      orb: a.orb,
                      strength: a.strength,
                    })) : []}
                  natalAspects={wheelMode === "natal" ? natalAspects.map((a) => ({
                    p1: a.p1,
                    p2: a.p2,
                    aspect: a.aspect,
                    orb: a.orb,
                  })) : []}
                  size={700}
                  theme="light"
                />
              ) : null}
            </div>
          </div>
          </div>{/* end opacity wrapper */}
        </div>
      </div>

      {isEditing && activeProfileId && activeDetail ? (
        <ProfileEditForm
          profileId={activeProfileId}
          activeDetail={activeDetail}
          onClose={() => setIsEditing(false)}
          onSaved={refreshProfile}
        />
      ) : null}

      {bootError ? (
        <section className="card error-card">
          <h2>Bootstrap Error</h2>
          <p>{bootError}</p>
        </section>
      ) : null}

      {/* ===== Expanded widget popup ===== */}
      {expandedWidget ? (
        <div className="widget-popup-overlay" onClick={() => setExpandedWidget(null)}>
          <div className="widget-popup" onClick={(e) => e.stopPropagation()}>
            <div className="widget-popup-head">
              <h3>
                {expandedWidget === "summary" ? "Natal Profile" : null}
                {expandedWidget === "planets" ? "Planet Positions" : null}
                {expandedWidget === "aspects" ? "Natal Aspects" : null}
                {expandedWidget === "transits" ? `Transits${activeDetail ? ` — ${activeDetail.profile.profile_name}` : ""}` : null}
              </h3>
              <button type="button" className="settings-close" onClick={() => setExpandedWidget(null)}>&times;</button>
            </div>
            <div className="widget-popup-body">
              {expandedWidget === "summary" && activeDetail ? (
                <div>
                  <ProfileSummaryCard detail={activeDetail} />
                  <button type="button" className="edit-btn" style={{ marginTop: 16 }} onClick={() => { setExpandedWidget(null); setIsEditing(true) }}>Edit Profile</button>
                  {natalPositions.length ? <NatalPositionsTable positions={natalPositions} /> : null}
                  {natalAspects.length ? <NatalAspectsTable aspects={natalAspects} /> : null}
                </div>
              ) : null}
              {expandedWidget === "planets" && natalPositions.length ? (
                <NatalPositionsTable positions={natalPositions} />
              ) : null}
              {expandedWidget === "aspects" && natalAspects.length ? (
                <NatalAspectsTable aspects={natalAspects} />
              ) : null}
              {expandedWidget === "transits" ? (
                <TransitsTab
                  activeProfileId={activeProfileId}
                  activeDetail={activeDetail}
                  onTransitReport={(report) => {
                    // Cancel any in-flight auto-fetch so it doesn't overwrite this report
                    autoFetchRef.current?.abort()
                    setTransitReport(report)
                    if (activeProfileId && report.tii != null) {
                      setTiiMap((prev) => ({
                        ...prev,
                        [activeProfileId]: {
                          tii: report.tii!,
                          tension_ratio: report.tension_ratio ?? 0,
                          feels_like: report.feels_like ?? "Calm",
                          location: report.snapshot?.transit_timezone ?? "",
                        },
                      }))
                    }
                  }}
                  initialReport={transitReport}
                />
              ) : null}
            </div>
          </div>
        </div>
      ) : null}

      {/* ===== Fullscreen wheel overlay ===== */}
      {wheelExpanded && activeDetail ? (
        <div className="wheel-fullscreen" onClick={() => setWheelExpanded(false)}>
          <button type="button" className="wheel-fullscreen__close" onClick={() => setWheelExpanded(false)}>&times;</button>
          <div className="wheel-fullscreen__toggle" onClick={(e) => e.stopPropagation()}>
            <button type="button" className={wheelMode === "natal" ? "active" : ""} onClick={() => setWheelMode("natal")}>Natal</button>
            <button type="button" className={wheelMode === "transit" ? "active" : ""} onClick={() => setWheelMode("transit")}>Transit</button>
          </div>
          <div className="wheel-fullscreen__ring" onClick={(e) => e.stopPropagation()}>
            <NatalZodiacRing
              asc={coerceNumber(activeDetail.chart.asc)}
              mc={coerceNumber(activeDetail.chart.mc)}
              houses={activeDetail.chart.houses ?? null}
              planets={(natalPositions)
                .filter((p) => Number.isFinite(p.longitude))
                .map((p) => ({
                  id: p.id,
                  longitude: p.longitude,
                  glyph: OBJECT_GLYPHS[p.id] ?? p.id.slice(0, 2),
                }))}
              transitPlanets={wheelMode === "transit" ? (transitReport?.transit_positions ?? [])
                .filter((p) => Number.isFinite(p.longitude))
                .map((p) => ({
                  id: p.id,
                  longitude: p.longitude,
                  glyph: OBJECT_GLYPHS[p.id] ?? p.id.slice(0, 2),
                })) : []}
              transitAspects={wheelMode === "transit" ? (transitReport?.active_aspects ?? [])
                .filter((a) => a.is_within_orb)
                .map((a) => ({
                  transit_object: a.transit_object,
                  natal_object: a.natal_object,
                  aspect: a.aspect,
                  orb: a.orb,
                  strength: a.strength,
                })) : []}
              natalAspects={wheelMode === "natal" ? natalAspects.map((a) => ({
                p1: a.p1,
                p2: a.p2,
                aspect: a.aspect,
                orb: a.orb,
              })) : []}
              size={700}
              theme="light"
            />
          </div>
        </div>
      ) : null}

      {guideOpen ? <TiiGuide onClose={() => setGuideOpen(false)} /> : null}
    </main>
  )
}
