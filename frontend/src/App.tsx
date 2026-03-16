import { useEffect, useState, useCallback, useRef } from "react"
import { useAuth } from "./contexts/AuthContext"
import { useLanguage } from "./contexts/LanguageContext"
import AuthScreen from "./components/AuthScreen"
import { fetchHealth, fetchProfiles, fetchProfileDetail, fetchTransitReport, searchPublicProfiles, followProfile, unfollowProfile } from "./api"
import { ProfileList, type ProfileTiiData } from "./components/ProfileList"
import { ProfileSummaryCard, NatalPositionsTable, NatalAspectsTable } from "./components/ProfileDetail"
import { DailyWeather, ActiveTransitsWidget, CosmicClimateWidget } from "./components/DailyWeather"
import { TiiGuide } from "./components/TiiGuide"
import { ProfileEditForm } from "./components/ProfileEditForm"
import { ProfileCreateForm } from "./components/ProfileCreateForm"
import { TransitsTab } from "./components/TransitsTab"
import { NatalZodiacRing } from "./components/NatalZodiacRing"
import { SettingsModal } from "./components/SettingsModal"
import type { HealthResponse, ProfileSummary, ProfileDetailResponse, TransitReportResponse, NatalPosition, PublicSearchResult } from "./types"

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

/* ===== Skeleton components ===== */

function SkeletonSidebarItems({ count = 5 }: { count?: number }) {
  return (
    <>
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="skeleton-sidebar-item">
          <div className="skeleton skeleton-sidebar-item__avatar" />
          <div className="skeleton-sidebar-item__lines">
            <div className="skeleton skeleton-sidebar-item__line1" />
            <div className="skeleton skeleton-sidebar-item__line2" />
          </div>
          <div className="skeleton skeleton-sidebar-item__tii" />
        </div>
      ))}
    </>
  )
}

function SkeletonHero() {
  return (
    <div className="skeleton-hero">
      <div className="skeleton skeleton-hero__location" />
      <div className="skeleton skeleton-hero__name" />
      <div className="skeleton skeleton-hero__tii" />
      <div className="skeleton skeleton-hero__mood" />
      <div className="skeleton skeleton-hero__date" />
    </div>
  )
}

function SkeletonWidget({ rows = 4 }: { rows?: number }) {
  return (
    <div className="skeleton-widget">
      <div className="skeleton skeleton-widget__title" />
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="skeleton-widget__row">
          <div className="skeleton skeleton-widget__icon" />
          <div className="skeleton skeleton-widget__bar" style={{ flex: i % 2 === 0 ? 1 : 0.6 }} />
        </div>
      ))}
    </div>
  )
}

function SkeletonWheel() {
  return (
    <div className="skeleton-wheel">
      <div className="skeleton skeleton-wheel__circle" />
    </div>
  )
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
  const { t, lang } = useLanguage()
  const [theme, setTheme] = useTheme()
  const [health, setHealth] = useState<HealthResponse | null>(null)
  const [profiles, setProfiles] = useState<ProfileSummary[]>(() => {
    try { return JSON.parse(localStorage.getItem("cachedProfiles") || "[]") } catch { return [] }
  })
  const [activeProfileId, setActiveProfileId] = useState<string | null>(() => {
    const primary = localStorage.getItem("primaryProfileId")
    try {
      const cached: ProfileSummary[] = JSON.parse(localStorage.getItem("cachedProfiles") || "[]")
      if (cached.length) return primary || cached[0]?.profile_id || null
    } catch {}
    return null
  })
  const [activeDetail, setActiveDetail] = useState<ProfileDetailResponse | null>(() => {
    try {
      const pid = localStorage.getItem("primaryProfileId")
      if (!pid) {
        const cached: ProfileSummary[] = JSON.parse(localStorage.getItem("cachedProfiles") || "[]")
        if (cached.length) {
          const detail = localStorage.getItem("cachedDetail_" + cached[0]?.profile_id)
          if (detail) return JSON.parse(detail)
        }
        return null
      }
      const detail = localStorage.getItem("cachedDetail_" + pid)
      if (detail) return JSON.parse(detail)
    } catch {}
    return null
  })
  const [bootError, setBootError] = useState<string | null>(null)
  const [detailError, setDetailError] = useState<string | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [isEditing, setIsEditing] = useState(false)
  const [transitReport, setTransitReport] = useState<TransitReportResponse | null>(null)
  const [wheelExpanded, setWheelExpanded] = useState(false)
  const [searchQuery, setSearchQuery] = useState("")
  const [expandedWidget, setExpandedWidget] = useState<ExpandedWidget>(null)
  const [mobileView, setMobileView] = useState<"list" | "detail">(() => {
    // On mobile, auto-open detail if we have cached profiles (skip list screen)
    try {
      const cached = JSON.parse(localStorage.getItem("cachedProfiles") || "[]")
      if (cached.length > 0) return "detail"
    } catch {}
    return "list"
  })
  const [wheelMode, setWheelMode] = useState<"natal" | "transit">("transit")
  const [tiiMap, setTiiMap] = useState<Record<string, ProfileTiiData>>(() => {
    try {
      // Try dedicated TII cache first (survives even when server has no latest_transit)
      const tiiCache = localStorage.getItem("cachedTiiMap")
      if (tiiCache) return JSON.parse(tiiCache)
      // Fallback: extract from cached profiles
      const cached: ProfileSummary[] = JSON.parse(localStorage.getItem("cachedProfiles") || "[]")
      const browserTz = Intl.DateTimeFormat().resolvedOptions().timeZone
      const map: Record<string, ProfileTiiData> = {}
      for (const p of cached) {
        const lt = p.latest_transit
        if (lt?.tii != null) {
          map[p.profile_id] = {
            tii: lt.tii,
            tension_ratio: lt.tension_ratio ?? 0,
            feels_like: lt.feels_like ?? "Calm",
            location: lt.location_name || lt.timezone || browserTz,
          }
        }
      }
      return map
    } catch { return {} }
  })
  // Persist tiiMap to localStorage so sidebar TII survives page reload
  useEffect(() => {
    if (Object.keys(tiiMap).length > 0) {
      try { localStorage.setItem("cachedTiiMap", JSON.stringify(tiiMap)) } catch {}
    }
  }, [tiiMap])
  const [guideOpen, setGuideOpen] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [primaryProfileId, setPrimaryProfileId] = useState<string | null>(() => localStorage.getItem("primaryProfileId"))
  const [profileOrder, setProfileOrder] = useState<string[]>(() => {
    try { return JSON.parse(localStorage.getItem("profileOrder") ?? "[]") } catch { return [] }
  })
  const [isCreating, setIsCreating] = useState(false)
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [publicResults, setPublicResults] = useState<PublicSearchResult[]>([])
  const [publicSearching, setPublicSearching] = useState(false)
  const [publicAddingId, setPublicAddingId] = useState<string | null>(null)
  const publicSearchRef = useRef<AbortController | null>(null)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const autoFetchRef = useRef<AbortController | null>(null)
  const [fetchTrigger, setFetchTrigger] = useState(0)
  const [transitLoading, setTransitLoading] = useState(false)
  useEffect(() => {
    if (!user) return
    let cancelled = false

    async function bootstrap(attempt = 0) {
      setBootError(null)
      try {
        const [healthPayload, profilesPayload] = await Promise.all([
          fetchHealth(),
          fetchProfiles(),
        ])

        if (cancelled) return

        setHealth(healthPayload)
        setProfiles(profilesPayload.profiles)
        try { localStorage.setItem("cachedProfiles", JSON.stringify(profilesPayload.profiles)) } catch {}

        // Clear stale primaryProfileId if it points to a deleted profile
        const validIds = new Set(profilesPayload.profiles.map((p: ProfileSummary) => p.profile_id))
        let effectivePrimary = primaryProfileId
        if (effectivePrimary && !validIds.has(effectivePrimary)) {
          localStorage.removeItem("primaryProfileId")
          setPrimaryProfileId(null)
          effectivePrimary = null
        }

        setActiveProfileId((current) => current || effectivePrimary || profilesPayload.profiles[0]?.profile_id || null)

        // Merge server-side TII into existing tiiMap (preserve client-cached values)
        const browserTz = Intl.DateTimeFormat().resolvedOptions().timeZone
        setTiiMap((prev) => {
          const merged = { ...prev }
          for (const p of profilesPayload.profiles) {
            const lt = p.latest_transit
            if (lt?.tii != null) {
              merged[p.profile_id] = {
                tii: lt.tii,
                tension_ratio: lt.tension_ratio ?? 0,
                feels_like: lt.feels_like ?? "Calm",
                location: lt.location_name || lt.timezone || browserTz,
              }
            }
          }
          return merged
        })
      } catch (err) {
        if (cancelled) return
        const msg = err instanceof Error ? err.message : "Unknown error"
        // Retry up to 2 times on server errors (500/502/503)
        if (attempt < 2 && /^5\d\d\s/.test(msg)) {
          await new Promise((r) => setTimeout(r, 1000 * (attempt + 1)))
          if (!cancelled) return bootstrap(attempt + 1)
        }
        setBootError(msg)
      }
    }

    bootstrap()
    return () => { cancelled = true }
  }, [user])

  // Background TII: compute transit for profiles missing TII so sidebar populates automatically
  useEffect(() => {
    if (profiles.length === 0) return
    const browserTz = Intl.DateTimeFormat().resolvedOptions().timeZone
    const now = new Date()
    const date = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`
    const time = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`

    const missing = profiles.filter((p) => {
      const lt = p.latest_transit
      return lt?.tii == null
    })
    if (missing.length === 0) return

    let cancelled = false
    // Stagger requests to avoid hammering the server
    missing.forEach((p, i) => {
      setTimeout(() => {
        if (cancelled) return
        fetchTransitReport(p.profile_id, {
          transit_date: date,
          transit_time: time,
          timezone: p.latest_transit?.timezone ?? browserTz,
          include_timing: false,
        }).then((report) => {
          if (cancelled || report.tii == null) return
          setTiiMap((prev) => ({
            ...prev,
            [p.profile_id]: {
              tii: report.tii!,
              tension_ratio: report.tension_ratio ?? 0,
              feels_like: report.feels_like ?? "Calm",
              location: report.snapshot?.transit_location_name || report.snapshot?.transit_timezone || browserTz,
            },
          }))
        }).catch(() => { /* silent — TII will populate when user clicks profile */ })
      }, i * 500)
    })

    return () => { cancelled = true }
  }, [profiles])

  useEffect(() => {
    if (!activeProfileId) {
      setActiveDetail(null)
      setDetailError(null)
      setDetailLoading(false)
      return
    }

    const controller = new AbortController()
    setDetailError(null)

    // Load cached detail instantly, then refresh from API
    const cachedKey = "cachedDetail_" + activeProfileId
    try {
      const cached = localStorage.getItem(cachedKey)
      if (cached) {
        setActiveDetail(JSON.parse(cached))
        setDetailLoading(false)
      } else {
        setActiveDetail(null)
        setDetailLoading(true)
      }
    } catch {
      setActiveDetail(null)
      setDetailLoading(true)
    }

    fetchProfileDetail(activeProfileId, controller.signal)
      .then((payload) => {
        setActiveDetail(payload)
        try { localStorage.setItem(cachedKey, JSON.stringify(payload)) } catch {}
      })
      .catch((err) => {
        if (controller.signal.aborted) return
        // Only clear detail if we don't have cached data
        if (!localStorage.getItem(cachedKey)) setActiveDetail(null)
        setDetailError(err instanceof Error ? err.message : "Unknown error")
      })
      .finally(() => {
        if (!controller.signal.aborted) setDetailLoading(false)
      })

    return () => controller.abort()
  }, [activeProfileId])


  // Fetch transit report for active profile — use saved params if available, else current time
  useEffect(() => {
    if (!activeProfileId) {
      setTransitReport(null)
      return
    }

    autoFetchRef.current?.abort()
    const controller = new AbortController()
    autoFetchRef.current = controller
    const browserTz = Intl.DateTimeFormat().resolvedOptions().timeZone

    // Clear previous profile's transit data, then check cache
    setTransitReport(null)

    const transitCacheKey = "cachedTransit_" + activeProfileId
    try {
      const cached = localStorage.getItem(transitCacheKey)
      if (cached) {
        setTransitReport(JSON.parse(cached))
        setTransitLoading(false)
      } else {
        setTransitLoading(true)
      }
    } catch {
      setTransitLoading(true)
    }

    // Preserve profile's saved timezone & location, only update date/time to "now"
    // Priority: localStorage > latest_transit from profile > browser timezone
    const activeProfile = profiles.find((p) => p.profile_id === activeProfileId)
    const lt = activeProfile?.latest_transit
    let savedTz = lt?.timezone ?? browserTz
    let savedLoc: string | null = lt?.location_name ?? null
    let savedLat: number | null = lt?.latitude ?? null
    let savedLon: number | null = lt?.longitude ?? null
    try {
      const saved = JSON.parse(localStorage.getItem("transitParams") || "{}")
      const p = saved[activeProfileId]
      if (p?.timezone) savedTz = p.timezone
      if (p?.locationName) savedLoc = p.locationName
      if (p?.latitude != null) savedLat = p.latitude
      if (p?.longitude != null) savedLon = p.longitude
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
      latitude: savedLat,
      longitude: savedLon,
      include_timing: true,
    }

    function applyReport(report: TransitReportResponse) {
      if (controller.signal.aborted) return
      setTransitReport(report)
      setTransitLoading(false)
      try { localStorage.setItem(transitCacheKey, JSON.stringify(report)) } catch {}
      if (report.tii != null) {
        setTiiMap((prev) => ({
          ...prev,
          [activeProfileId]: {
            tii: report.tii!,
            tension_ratio: report.tension_ratio ?? 0,
            feels_like: report.feels_like ?? "Calm",
            location: report.snapshot?.transit_location_name || report.snapshot?.transit_timezone || savedTz,
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
  // eslint-disable-next-line react-hooks/exhaustive-deps -- profiles read for location only, no re-fetch needed
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

  // Public profile search: triggered when searchQuery starts with "@"
  const isPublicSearch = searchQuery.startsWith("@")
  const publicQuery = searchQuery.slice(1).trim()

  useEffect(() => {
    if (!isPublicSearch || publicQuery.length < 2) {
      setPublicResults([])
      setPublicSearching(false)
      publicSearchRef.current?.abort()
      return
    }

    if (debounceRef.current) clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(() => {
      publicSearchRef.current?.abort()
      const controller = new AbortController()
      publicSearchRef.current = controller
      setPublicSearching(true)
      searchPublicProfiles(publicQuery, controller.signal)
        .then((results) => {
          if (!controller.signal.aborted) {
            setPublicResults(results)
            setPublicSearching(false)
          }
        })
        .catch(() => {
          if (!controller.signal.aborted) {
            setPublicResults([])
            setPublicSearching(false)
          }
        })
    }, 300)

    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current)
      publicSearchRef.current?.abort()
    }
  }, [isPublicSearch, publicQuery])

  const handleFollowProfile = useCallback(async (result: PublicSearchResult) => {
    setPublicAddingId(result.profile_id)
    try {
      await followProfile(result.profile_id)
      const profilesPayload = await fetchProfiles()
      setProfiles(profilesPayload.profiles)
      setActiveProfileId(result.profile_id)
      setSearchQuery("")
      setPublicResults([])
      setMobileView("detail")
    } catch {
      // silent
    } finally {
      setPublicAddingId(null)
    }
  }, [])

  const handleUnfollowProfile = useCallback(async (profileId: string) => {
    try {
      await unfollowProfile(profileId)
      const profilesPayload = await fetchProfiles()
      setProfiles(profilesPayload.profiles)
      if (activeProfileId === profileId) {
        setActiveProfileId(profilesPayload.profiles[0]?.profile_id || null)
      }
    } catch {
      // silent
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
    <main className={`app-shell${sidebarCollapsed ? " app-shell--sidebar-collapsed" : ""} mobile-view--${mobileView}`}>
      <div className="main-layout">
        <aside className={`sidebar${sidebarCollapsed ? " sidebar--collapsed" : ""}`}>
          {/* Desktop toolbar (burger + add) */}
          <div className="sidebar-toolbar sidebar-toolbar--desktop">
            <button
              type="button"
              className="sidebar-toolbar-btn"
              onClick={() => setSidebarCollapsed(!sidebarCollapsed)}
              title={sidebarCollapsed ? t("sidebar.showSidebar") : t("sidebar.hideSidebar")}
            >
              {sidebarCollapsed ? "\u25C1" : "\u2630"}
            </button>
            {!sidebarCollapsed && (
              <button
                type="button"
                className="sidebar-toolbar-btn sidebar-toolbar-btn--add"
                onClick={() => setIsCreating(true)}
                title={t("sidebar.newProfile")}
              >
                +
              </button>
            )}
          </div>

          {/* Mobile header: "Astromi" title + settings/info */}
          <div className="mobile-list-header">
            <h1 className="mobile-list-title">Astromi</h1>
            <div className="mobile-list-header-actions">
              <button type="button" className="sidebar-icon-btn" onClick={() => setSettingsOpen(true)} title={t("sidebar.settings")}>{"\u2699"}</button>
              <button type="button" className="sidebar-icon-btn" onClick={() => setGuideOpen(true)} title={t("sidebar.howItWorks")}>{"\u2139"}</button>
            </div>
          </div>

          {!sidebarCollapsed && (
            <>
              {/* Desktop search (top) */}
              <div className="sidebar-search sidebar-search--desktop">
                <input
                  type="text"
                  placeholder={t("sidebar.search")}
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                />
              </div>
              <div className="sidebar-scroll">
                {isPublicSearch ? (
                  <div className="public-search-results">
                    {publicSearching ? (
                      <div className="public-search-status">
                        <div className="content-loader__spinner" />
                        <span>{t("sidebar.publicSearching")}</span>
                      </div>
                    ) : publicQuery.length < 2 ? (
                      <div className="public-search-status">
                        <span className="public-search-hint">{t("sidebar.searchPublic")}</span>
                      </div>
                    ) : publicResults.length === 0 ? (
                      <div className="public-search-status">
                        <span>{t("sidebar.publicNoResults")}</span>
                      </div>
                    ) : (
                      publicResults.map((r) => (
                        <div key={r.profile_id} className="public-search-card">
                          <div className="public-search-card__info">
                            <div className="public-search-card__name">{r.profile_name}</div>
                            <div className="public-search-card__username">@{r.username}</div>
                            <div className="public-search-card__meta">
                              {r.location_name && <span className="public-search-card__location">{r.location_name}</span>}
                              {r.natal_summary && (
                                <span className="public-search-card__summary">
                                  {typeof r.natal_summary === "string"
                                    ? r.natal_summary
                                    : `☉ ${r.natal_summary.sun} · ☽ ${r.natal_summary.moon} · AC ${r.natal_summary.asc}`}
                                </span>
                              )}
                            </div>
                          </div>
                          <button
                            type="button"
                            className="public-search-card__add"
                            onClick={() => handleFollowProfile(r)}
                            disabled={publicAddingId === r.profile_id}
                            title={t("sidebar.follow")}
                          >
                            {publicAddingId === r.profile_id ? "..." : "+"}
                          </button>
                        </div>
                      ))
                    )}
                  </div>
                ) : profiles.length === 0 && !bootError ? (
                  <SkeletonSidebarItems count={6} />
                ) : (
                  <ProfileList
                    profiles={(() => {
                      // Sort: primary first, then by saved manual order, then rest
                      const order = profileOrder
                      const sorted = [...profiles].sort((a, b) => {
                        if (a.profile_id === primaryProfileId) return -1
                        if (b.profile_id === primaryProfileId) return 1
                        const ai = order.indexOf(a.profile_id)
                        const bi = order.indexOf(b.profile_id)
                        if (ai !== -1 && bi !== -1) return ai - bi
                        if (ai !== -1) return -1
                        if (bi !== -1) return 1
                        return 0
                      })
                      if (!searchQuery.trim()) return sorted
                      const q = searchQuery.toLowerCase()
                      return sorted.filter((p) =>
                        p.profile_name.toLowerCase().includes(q)
                        || p.username.toLowerCase().includes(q)
                        || (p.location_name ?? "").toLowerCase().includes(q)
                      )
                    })()}
                    activeProfileId={activeProfileId}
                    onSelect={(id) => {
                      if (id === activeProfileId) {
                        setFetchTrigger((n) => n + 1)
                      } else {
                        setActiveProfileId(id)
                      }
                      setMobileView("detail")
                    }}
                    tiiMap={tiiMap}
                    primaryProfileId={primaryProfileId}
                    onReorder={(ids) => {
                      setProfileOrder(ids)
                      localStorage.setItem("profileOrder", JSON.stringify(ids))
                    }}
                  />
                )}
              </div>
              {/* Desktop footer */}
              <div className="sidebar-footer sidebar-footer--desktop">
                <button
                  type="button"
                  className="sidebar-icon-btn"
                  onClick={() => setSettingsOpen(true)}
                  title={t("sidebar.settings")}
                >
                  {"\u2699"}
                </button>
                <button
                  type="button"
                  className="sidebar-icon-btn"
                  onClick={() => setGuideOpen(true)}
                  title={t("sidebar.howItWorks")}
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
              {/* Mobile footer: search + add button */}
              <div className="mobile-list-footer">
                <div className="mobile-search-bar">
                  <span className="mobile-search-icon">{"\uD83D\uDD0D"}</span>
                  <input
                    type="text"
                    placeholder={t("sidebar.search")}
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                  />
                </div>
                <button
                  type="button"
                  className="mobile-add-btn"
                  onClick={() => setIsCreating(true)}
                  title={t("sidebar.newProfile")}
                >
                  +
                </button>
              </div>
            </>
          )}
        </aside>

        <div className="content-pane">
          {/* Mobile bottom bar: list button (like Apple Weather) */}
          <div className="mobile-detail-bottombar">
            <button
              type="button"
              className="mobile-list-btn"
              onClick={() => setMobileView("list")}
              title={t("sidebar.back")}
            >
              {"\u2630"}
            </button>
          </div>
          {/* Hero section: DailyWeather or skeleton */}
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
                    saved[activeProfileId] = { timezone: tz, locationName: loc }
                    localStorage.setItem("transitParams", JSON.stringify(saved))
                  } catch { /* ignore */ }
                  if (report.tii != null) {
                    setTiiMap((prev) => ({
                      ...prev,
                      [activeProfileId!]: {
                        tii: report.tii!,
                        tension_ratio: report.tension_ratio ?? 0,
                        feels_like: report.feels_like ?? "Calm",
                        location: report.snapshot?.transit_location_name || report.snapshot?.transit_timezone || "",
                      },
                    }))
                  }
                }).catch(() => {})
              }}
            />
          ) : activeDetail ? (
            <header className="sticky-header">
              <h1 className="content-profile-name">{activeDetail.profile.profile_name}</h1>
              <span className="content-profile-username">@{activeDetail.profile.username}</span>
            </header>
          ) : activeProfileId ? (
            <SkeletonHero />
          ) : (
            <header className="sticky-header">
              <h1 className="content-profile-name">{t("widget.selectProfile")}</h1>
            </header>
          )}

          <div className="widget-grid">
            {/* Left column: Transits + Climate */}
            <div className="widget-col-left">
              {/* Active Transits widget */}
              {transitReport ? (
                <div className="widget widget--summary">
                  <ActiveTransitsWidget transitReport={transitReport} />
                </div>
              ) : (transitLoading || activeProfileId) && !transitReport ? (
                <SkeletonWidget rows={4} />
              ) : null}

              {/* Cosmic Climate widget */}
              {transitReport ? (
                <div className="widget widget--summary">
                  <CosmicClimateWidget transitReport={transitReport} />
                </div>
              ) : (transitLoading || activeProfileId) && !transitReport ? (
                <SkeletonWidget rows={3} />
              ) : null}
            </div>

            {/* Right column: Natal + Wheel */}
            <div className="widget-col-right">
              {/* Natal widget */}
              {activeDetail ? (
                <div className="widget widget--summary" onClick={() => setExpandedWidget("summary")}>
                  <div className="widget-title">{t("widget.natal")}</div>
                  <ProfileSummaryCard detail={activeDetail} />
                </div>
              ) : activeProfileId ? (
                <SkeletonWidget rows={5} />
              ) : null}
              {activeDetail ? (
                <div className="widget widget--chart widget--wheel-right" onClick={() => setWheelExpanded(true)}>
                  <div className="wheel-mode-toggle" onClick={(e) => e.stopPropagation()}>
                    <button type="button" className={wheelMode === "natal" ? "active" : ""} onClick={() => setWheelMode("natal")}>{t("widget.natal")}</button>
                    <button type="button" className={wheelMode === "transit" ? "active" : ""} onClick={() => setWheelMode("transit")}>{t("widget.transit")}</button>
                  </div>
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
              ) : activeProfileId ? (
                <SkeletonWheel />
              ) : null}
            </div>{/* end widget-col-right */}
          </div>{/* end widget-grid */}
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

      {isCreating ? (
        <ProfileCreateForm
          onClose={() => setIsCreating(false)}
          onCreated={async (profileId) => {
            setIsCreating(false)
            const profilesPayload = await fetchProfiles()
            setProfiles(profilesPayload.profiles)
            setActiveProfileId(profileId)
          }}
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
                {expandedWidget === "summary" ? t("widget.natalProfile") : null}
                {expandedWidget === "planets" ? t("widget.planetPositions") : null}
                {expandedWidget === "aspects" ? t("widget.natalAspects") : null}
                {expandedWidget === "transits" ? `${t("transits.title")}${activeDetail ? ` — ${activeDetail.profile.profile_name}` : ""}` : null}
              </h3>
              <button type="button" className="settings-close" onClick={() => setExpandedWidget(null)}>&times;</button>
            </div>
            <div className="widget-popup-body">
              {expandedWidget === "summary" && activeDetail ? (
                <div>
                  <ProfileSummaryCard detail={activeDetail} />
                  {(() => {
                    const activeP = profiles.find((p) => p.profile_id === activeProfileId)
                    const isOwn = activeP?.is_own !== false
                    const isFollowing = activeP?.is_following === true
                    return (
                      <>
                        {isOwn ? (
                          <button type="button" className="edit-btn" style={{ marginTop: 16 }} onClick={() => { setExpandedWidget(null); setIsEditing(true) }}>{t("widget.editProfile")}</button>
                        ) : null}
                        {isFollowing ? (
                          <button type="button" className="edit-btn edit-btn--unfollow" style={{ marginTop: 16 }} onClick={() => { setExpandedWidget(null); if (activeProfileId) handleUnfollowProfile(activeProfileId) }}>{t("sidebar.unfollow")}</button>
                        ) : null}
                      </>
                    )
                  })()}
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
                          location: report.snapshot?.transit_location_name || report.snapshot?.transit_timezone || "",
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
            <button type="button" className={wheelMode === "natal" ? "active" : ""} onClick={() => setWheelMode("natal")}>{t("wheel.natal")}</button>
            <button type="button" className={wheelMode === "transit" ? "active" : ""} onClick={() => setWheelMode("transit")}>{t("wheel.transit")}</button>
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

      <SettingsModal
        open={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        email={user.email ?? null}
        theme={theme}
        onThemeChange={setTheme}
        onSignOut={() => {
          setSettingsOpen(false)
          signOut()
          setProfiles([])
          setActiveProfileId(null)
          setActiveDetail(null)
          setTransitReport(null)
        }}
        onResetCache={() => {
          // Clear all cached data from localStorage
          const keysToRemove = Object.keys(localStorage).filter((k) =>
            k.startsWith("cachedProfiles") || k.startsWith("cachedDetail_") || k.startsWith("cachedTransit_") || k === "cachedTiiMap" || k === "transitParams"
          )
          keysToRemove.forEach((k) => localStorage.removeItem(k))
          setSettingsOpen(false)
          // Force full reload from server
          window.location.reload()
        }}
        transitReport={transitReport}
        profiles={profiles}
        primaryProfileId={primaryProfileId}
        onPrimaryChange={(id) => {
          setPrimaryProfileId(id)
          localStorage.setItem("primaryProfileId", id)
        }}
      />
    </main>
  )
}
