import { useEffect, useState, useCallback, Fragment } from "react"
import { fetchHealth, fetchProfiles, fetchProfileDetail, fetchTransitReport } from "./api"
import { ProfileList } from "./components/ProfileList"
import { ProfileSummaryCard, NatalPositionsTable, NatalAspectsTable } from "./components/ProfileDetail"
import { ProfileEditForm } from "./components/ProfileEditForm"
import { TransitsTab } from "./components/TransitsTab"
import { NatalZodiacRing } from "./components/NatalZodiacRing"
import type { HealthResponse, ProfileSummary, ProfileDetailResponse, TransitReportResponse, NatalPosition } from "./types"

const OBJECT_GLYPHS: Record<string, string> = {
  Sun: "\u2609", Moon: "\u263D", Mercury: "\u263F", Venus: "\u2640", Mars: "\u2642",
  Jupiter: "\u2643", Saturn: "\u2644", Uranus: "\u2645", Neptune: "\u2646", Pluto: "\u2BD3",
  Chiron: "\u26B7", Lilith: "\u26B8", Selena: "\u2BCC",
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
  const [theme, setTheme] = useTheme()
  const [health, setHealth] = useState<HealthResponse | null>(null)
  const [profiles, setProfiles] = useState<ProfileSummary[]>([])
  const [activeProfileId, setActiveProfileId] = useState<string | null>(null)
  const [activeDetail, setActiveDetail] = useState<ProfileDetailResponse | null>(null)
  const [bootError, setBootError] = useState<string | null>(null)
  const [detailError, setDetailError] = useState<string | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [isEditing, setIsEditing] = useState(false)
  const [infoOpen, setInfoOpen] = useState(false)
  const [transitReport, setTransitReport] = useState<TransitReportResponse | null>(null)
  const [wheelExpanded, setWheelExpanded] = useState(false)
  const [searchQuery, setSearchQuery] = useState("")
  const [expandedWidget, setExpandedWidget] = useState<ExpandedWidget>(null)
  const [wheelMode, setWheelMode] = useState<"natal" | "transit">("natal")

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

  // Fetch transit positions using saved params (or now as fallback)
  useEffect(() => {
    if (!activeProfileId) {
      setTransitReport(null)
      return
    }

    const controller = new AbortController()

    function nowParams() {
      const now = new Date()
      return {
        transit_date: now.toISOString().slice(0, 10),
        transit_time: `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`,
        include_timing: true,
      }
    }

    let params: { transit_date: string; transit_time: string; timezone?: string | null; location_name?: string | null }
    let usedSaved = false

    try {
      const saved = JSON.parse(localStorage.getItem("transitParams") || "{}")
      const p = saved[activeProfileId]
      if (p?.transitDate && p?.transitTime) {
        params = {
          transit_date: p.transitDate,
          transit_time: p.transitTime,
          timezone: p.timezone || null,
          location_name: p.locationName || null,
          include_timing: true,
        }
        usedSaved = true
      } else {
        params = nowParams()
      }
    } catch {
      params = nowParams()
    }

    fetchTransitReport(activeProfileId, params, controller.signal)
      .then(setTransitReport)
      .catch(() => {
        if (controller.signal.aborted) return
        if (usedSaved) {
          fetchTransitReport(activeProfileId, nowParams(), controller.signal)
            .then(setTransitReport)
            .catch(() => setTransitReport(null))
        } else {
          setTransitReport(null)
        }
      })

    return () => controller.abort()
  }, [activeProfileId])

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
              onSelect={setActiveProfileId}
            />
          </div>
          <div className="sidebar-footer">
            <button
              type="button"
              className="sidebar-icon-btn"
              onClick={() => setInfoOpen(true)}
              title="Reference Guide"
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
          <header className="sticky-header">
            <h1 className="content-profile-name">{activeDetail?.profile.profile_name || "Select a profile"}</h1>
            {activeDetail ? <span className="content-profile-username">@{activeDetail.profile.username}</span> : null}
          </header>

          <div className="widget-grid">
            {/* Left column: Natal + Transits */}
            <div className="widget-col-left">
              {/* Natal widget */}
              {activeDetail ? (
                <div className="widget widget--summary" onClick={() => setExpandedWidget("summary")}>
                  <div className="widget-title">Natal</div>
                  <ProfileSummaryCard detail={activeDetail} />
                  <PlanetsPreview positions={natalPositions} />
                  <div className="widget-hint">Details</div>
                </div>
              ) : null}

              {/* Transits widget */}
              {activeDetail ? (
                <div className="widget widget--summary" onClick={() => setExpandedWidget("transits")}>
                  <div className="widget-title">Transits</div>
                  {transitReport ? (
                    <>
                      <div className="widget-transit-info">
                        {transitReport.snapshot?.transit_utc_datetime ? (
                          <div className="widget-transit-date">
                            {new Date(transitReport.snapshot.transit_utc_datetime).toLocaleDateString("en", {
                              day: "numeric", month: "short", year: "numeric",
                            })}
                          </div>
                        ) : null}
                        <div className="widget-transit-stats">
                          <span>{totalTransitAspects} aspects</span>
                          <span className="widget-transit-strong">{strongTransitAspects} strong</span>
                        </div>
                      </div>
                      <TransitAspectsPreview report={transitReport} />
                    </>
                  ) : (
                    <div className="widget-empty-hint">Loading transits...</div>
                  )}
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
                  onTransitReport={setTransitReport}
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

      {infoOpen ? (
        <div className="settings-overlay" onClick={() => setInfoOpen(false)}>
          <div className="info-popup" onClick={(e) => e.stopPropagation()}>
            <div className="settings-popup-head">
              <h3>Reference Guide</h3>
              <button type="button" className="settings-close" onClick={() => setInfoOpen(false)}>&times;</button>
            </div>
            <div className="info-popup-body">

              <div className="info-section">
                <h4>Planet Glyphs</h4>
                <div className="info-grid">
                  {[
                    ["Sun", "\u2609"], ["Moon", "\u263D"], ["Mercury", "\u263F"], ["Venus", "\u2640"], ["Mars", "\u2642"],
                    ["Jupiter", "\u2643"], ["Saturn", "\u2644"], ["Uranus", "\u2645"], ["Neptune", "\u2646"], ["Pluto", "\u2BD3"],
                    ["Chiron", "\u26B7"], ["Lilith", "\u26B8"], ["Selene", "\u2BCC"],
                    ["North Node", "\u260A"], ["South Node", "\u260B"], ["Part of Fortune", "\u2297"], ["Vertex", "\u22C1"],
                  ].map(([name, glyph]) => (
                    <div key={name} className="info-item">
                      <span className="info-glyph">{glyph}</span>
                      <span>{name}</span>
                    </div>
                  ))}
                </div>
              </div>

              <div className="info-section">
                <h4>Zodiac Signs</h4>
                <div className="info-grid">
                  {[
                    ["Aries", "\u2648", "Fire"], ["Taurus", "\u2649", "Earth"], ["Gemini", "\u264A", "Air"], ["Cancer", "\u264B", "Water"],
                    ["Leo", "\u264C", "Fire"], ["Virgo", "\u264D", "Earth"], ["Libra", "\u264E", "Air"], ["Scorpio", "\u264F", "Water"],
                    ["Sagittarius", "\u2650", "Fire"], ["Capricorn", "\u2651", "Earth"], ["Aquarius", "\u2652", "Air"], ["Pisces", "\u2653", "Water"],
                  ].map(([name, glyph, element]) => (
                    <div key={name} className="info-item">
                      <span className="info-glyph">{glyph}</span>
                      <span>{name}</span>
                      <span className="info-muted">{element}</span>
                    </div>
                  ))}
                </div>
              </div>

              <div className="info-section">
                <h4>Aspects</h4>
                <div className="info-grid">
                  {[
                    ["Conjunction", "\u260C", "0\u00B0", "Fusion of energies"],
                    ["Sextile", "\u26B9", "60\u00B0", "Harmonious opportunity"],
                    ["Square", "\u25A1", "90\u00B0", "Tension and challenge"],
                    ["Trine", "\u25B3", "120\u00B0", "Effortless harmony"],
                    ["Opposition", "\u260D", "180\u00B0", "Polarity and balance"],
                  ].map(([name, glyph, angle, desc]) => (
                    <div key={name} className="info-item info-item--wide">
                      <span className="info-glyph">{glyph}</span>
                      <span><strong>{name}</strong> ({angle})</span>
                      <span className="info-muted">{desc}</span>
                    </div>
                  ))}
                </div>
              </div>

              <div className="info-section">
                <h4>Houses</h4>
                <div className="info-grid info-grid--houses">
                  {[
                    ["1", "Self, appearance, identity"],
                    ["2", "Finances, values, possessions"],
                    ["3", "Communication, siblings, short trips"],
                    ["4", "Home, family, roots"],
                    ["5", "Creativity, romance, children"],
                    ["6", "Health, daily routine, service"],
                    ["7", "Partnerships, marriage, contracts"],
                    ["8", "Transformation, shared resources"],
                    ["9", "Philosophy, travel, higher education"],
                    ["10", "Career, public image, ambition"],
                    ["11", "Friends, groups, aspirations"],
                    ["12", "Subconscious, solitude, karma"],
                  ].map(([num, desc]) => (
                    <div key={num} className="info-item info-item--wide">
                      <span className="info-glyph info-house-num">{num}</span>
                      <span>{desc}</span>
                    </div>
                  ))}
                </div>
              </div>

              <div className="info-section">
                <h4>Strength Levels</h4>
                <div className="info-grid">
                  {[
                    ["EXACT", "< 1\u00B0", "exact"],
                    ["STRONG", "1\u00B0\u20133\u00B0", "strong"],
                    ["MODERATE", "3\u00B0\u20135\u00B0", "moderate"],
                    ["WIDE", "> 5\u00B0", "wide"],
                  ].map(([label, range, cls]) => (
                    <div key={label} className="info-item">
                      <span className={`natal-asp__str natal-asp__str--${cls}`}>{label}</span>
                      <span className="info-muted">{range}</span>
                    </div>
                  ))}
                </div>
              </div>

              <div className="info-section">
                <h4>Symbols</h4>
                <div className="info-grid">
                  <div className="info-item"><span className="info-glyph">{"\u24C7"}</span><span>Retrograde</span></div>
                  <div className="info-item"><span className="info-glyph">{"\u25B3"}</span><span>House number (e.g. {"\u25B3"}4)</span></div>
                  <div className="info-item"><strong>AC</strong><span>Ascendant</span></div>
                  <div className="info-item"><strong>DC</strong><span>Descendant</span></div>
                  <div className="info-item"><strong>MC</strong><span>Midheaven</span></div>
                  <div className="info-item"><strong>IC</strong><span>Imum Coeli</span></div>
                </div>
              </div>

            </div>
          </div>
        </div>
      ) : null}
    </main>
  )
}
