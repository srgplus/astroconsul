import { useEffect, useState, useCallback, useRef } from "react"
import { useAuth } from "./contexts/AuthContext"
import { useLanguage } from "./contexts/LanguageContext"
import AuthScreen from "./components/AuthScreen"
import B3Logo from "./components/B3Logo"
import { LandingPage } from "./components/LandingPage"
import { fetchHealth, fetchProfiles, fetchProfileDetail, fetchTransitReport, fetchSynastryReport, searchPublicProfiles, followProfile, unfollowProfile, setPrimaryProfile } from "./api"
import { ProfileList, type ProfileTiiData } from "./components/ProfileList"
import { ProfileSummaryCard, NatalPositionsTable, NatalAspectsTable } from "./components/ProfileDetail"
import { DailyWeather, ActiveTransitsWidget, CosmicClimateWidget, MoonPhaseWidget } from "./components/DailyWeather"
import { zoneColor, FEELS_EMOJI } from "./tii-zones"
import { TiiGuide } from "./components/TiiGuide"
import { ProfileEditForm } from "./components/ProfileEditForm"
import { ProfileCreateForm } from "./components/ProfileCreateForm"
import { TransitsTab } from "./components/TransitsTab"
import { NatalZodiacRing } from "./components/NatalZodiacRing"
import { SettingsModal } from "./components/SettingsModal"
import { InviteAcceptPage } from "./components/InviteAcceptPage"
import { InviteModal } from "./components/InviteModal"
import SynastryWidget from "./components/SynastryWidget"
import ProfilePickerModal from "./components/ProfilePickerModal"
import SynastryReport from "./components/SynastryReport"
import ChartSidebar from "./components/ChartSidebar"
import type { HealthResponse, ProfileSummary, ProfileDetailResponse, TransitReportResponse, SynastryReportResponse, NatalPosition, PublicSearchResult } from "./types"

const OBJECT_GLYPHS: Record<string, string> = {
  Sun: "\u2609", Moon: "\u263D", Mercury: "\u263F", Venus: "\u2640", Mars: "\u2642",
  Jupiter: "\u2643", Saturn: "\u2644", Uranus: "\u2645", Neptune: "\u2646", Pluto: "\u2647",
  Chiron: "\u26B7", Lilith: "\u26B8", Selena: "\u263E",
  "North Node": "\u260A", "South Node": "\u260B", "Part of Fortune": "\u2297", Vertex: "\u22C1",
  ASC: "AC", MC: "MC",
}

const SPECIAL_POINT_IDS = new Set(["Chiron", "Lilith", "Selena", "North Node", "South Node", "Part of Fortune", "Vertex"])

const SIGN_OFFSETS: Record<string, number> = {
  Aries: 0, Taurus: 30, Gemini: 60, Cancer: 90,
  Leo: 120, Virgo: 150, Libra: 180, Scorpio: 210,
  Sagittarius: 240, Capricorn: 270, Aquarius: 300, Pisces: 330,
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
type ExpandedWidget = null | "summary" | "planets" | "aspects" | "transits" | "synastry"

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
  const [showAuth, setShowAuth] = useState(false)
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
  const [bootDone, setBootDone] = useState(false)
  const [bootError, setBootError] = useState<string | null>(null)
  const [detailError, setDetailError] = useState<string | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [isEditing, setIsEditing] = useState(false)
  const [showInviteModal, setShowInviteModal] = useState(false)
  const [transitReport, setTransitReport] = useState<TransitReportResponse | null>(null)
  const [wheelExpanded, setWheelExpanded] = useState(false)

  // Allow pinch-to-zoom only when wheel is fullscreen
  useEffect(() => {
    const tag = document.querySelector('meta[name="viewport"]')
    if (!tag) return
    if (wheelExpanded) {
      tag.setAttribute("content", "width=device-width, initial-scale=1.0, viewport-fit=cover")
    } else {
      tag.setAttribute("content", "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover")
    }
  }, [wheelExpanded])
  const [searchQuery, setSearchQuery] = useState("")
  const [expandedWidget, setExpandedWidget] = useState<ExpandedWidget>(null)
  const [showSpecialPoints, setShowSpecialPoints] = useState(() => localStorage.getItem("showSpecialPoints") !== "false")
  const toggleSpecialPoints = () => {
    setShowSpecialPoints((prev) => {
      const next = !prev
      localStorage.setItem("showSpecialPoints", String(next))
      return next
    })
  }
  // Synastry state — per-profile (keyed by activeProfileId)
  const [synastryPartnerId, setSynastryPartnerId] = useState<string | null>(null)
  const [synastryPartnerName, setSynastryPartnerName] = useState<string | null>(null)
  const [synastryPartnerHandle, setSynastryPartnerHandle] = useState<string | null>(null)
  const [synastryPartnerNatalSummary, setSynastryPartnerNatalSummary] = useState<Record<string, string> | null>(null)
  const [synastryReport, setSynastryReport] = useState<SynastryReportResponse | null>(null)
  const [synastryLoading, setSynastryLoading] = useState(false)
  const synastryPrefetchRef = useRef<AbortController | null>(null)
  const [showProfilePicker, setShowProfilePicker] = useState(false)
  const [mobileView, setMobileView] = useState<"list" | "detail">(() => {
    // On mobile, auto-open detail if we have cached profiles (skip list screen)
    try {
      const cached = JSON.parse(localStorage.getItem("cachedProfiles") || "[]")
      if (cached.length > 0) return "detail"
    } catch {}
    return "list"
  })
  const [wheelMode, setWheelMode] = useState<"natal" | "transit" | "synastry">("transit")
  const [unfollowPopup, setUnfollowPopup] = useState<{ id: string; name: string; username: string } | null>(null)
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
  // Lock body scroll when widget popup overlay is open
  useEffect(() => {
    if (expandedWidget) {
      document.body.style.overflow = "hidden"
      return () => { document.body.style.overflow = "" }
    }
  }, [expandedWidget])
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
  const [transitRefreshing, setTransitRefreshing] = useState(false)
  // Use user.id as dependency (not user object) to avoid re-running bootstrap on token refresh
  const userId = user?.id

  // Clear stale caches when a different user logs in
  useEffect(() => {
    if (!userId) return
    const prevUserId = localStorage.getItem("lastUserId")
    if (prevUserId && prevUserId !== userId) {
      // Different user — wipe cached data from previous account
      const keysToRemove = Object.keys(localStorage).filter((k) =>
        k.startsWith("cachedProfiles") || k.startsWith("cachedDetail_") || k.startsWith("cachedTransit_") || k === "cachedTiiMap" || k === "transitParams" || k === "primaryProfileId" || k === "profileOrder"
      )
      keysToRemove.forEach((k) => localStorage.removeItem(k))
      setProfiles([])
      setActiveProfileId(null)
      setActiveDetail(null)
      setTransitReport(null)
      setTiiMap({})
      setPrimaryProfileId(null)
      setProfileOrder([])
    }
    localStorage.setItem("lastUserId", userId)
  }, [userId])

  useEffect(() => {
    if (!userId) return
    let cancelled = false

    async function bootstrap(attempt = 0) {
      setBootError(null)
      setBootDone(false)
      try {
        const [healthPayload, profilesPayload] = await Promise.all([
          fetchHealth(),
          fetchProfiles(),
        ])

        if (cancelled) return

        setHealth(healthPayload)
        setProfiles(profilesPayload.profiles)
        try { localStorage.setItem("cachedProfiles", JSON.stringify(profilesPayload.profiles)) } catch {}

        // Primary profile: prefer server-side value, fall back to localStorage
        const validIds = new Set(profilesPayload.profiles.map((p: ProfileSummary) => p.profile_id))
        const serverPrimary = profilesPayload.primary_profile_id ?? null
        const localPrimary = localStorage.getItem("primaryProfileId")
        let effectivePrimary = serverPrimary && validIds.has(serverPrimary) ? serverPrimary : localPrimary
        if (effectivePrimary && !validIds.has(effectivePrimary)) {
          if (profilesPayload.profiles.length > 0) {
            localStorage.removeItem("primaryProfileId")
            setPrimaryProfileId(null)
            effectivePrimary = null
          }
        } else if (effectivePrimary) {
          localStorage.setItem("primaryProfileId", effectivePrimary)
          setPrimaryProfileId(effectivePrimary)
          // Sync localStorage → server if server doesn't have it yet
          if (!serverPrimary && localPrimary && validIds.has(localPrimary)) {
            setPrimaryProfile(localPrimary).catch(() => {})
          }
        }

        const defaultId = profilesPayload.profiles[0]?.profile_id || null
        setActiveProfileId((current) => {
          // If primary is set, always prefer it (even over current)
          if (effectivePrimary) return effectivePrimary
          return current || defaultId
        })

        // New user with no profiles — ensure mobile shows list (with create prompt)
        if (profilesPayload.profiles.length === 0) {
          setMobileView("list")
        }

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
        setBootDone(true)
      } catch (err) {
        if (cancelled) return
        const msg = err instanceof Error ? err.message : "Unknown error"
        // Retry up to 2 times on server errors (500/502/503)
        if (attempt < 2 && /^5\d\d\s/.test(msg)) {
          await new Promise((r) => setTimeout(r, 1000 * (attempt + 1)))
          if (!cancelled) return bootstrap(attempt + 1)
        }
        setBootError(msg)
        setBootDone(true)
      }
    }

    bootstrap()
    return () => { cancelled = true }
  // eslint-disable-next-line react-hooks/exhaustive-deps -- userId is stable, avoids re-bootstrap on token refresh
  }, [userId])

  // Background TII: compute transit for profiles missing TII so sidebar populates automatically
  // Wait until active profile's data is loaded first to avoid blocking the server queue
  useEffect(() => {
    if (profiles.length === 0) return
    // Don't start background TII until the active profile has loaded its transit data
    // This prevents background requests from blocking the critical path on single-worker servers
    if (transitLoading) return

    const browserTz = Intl.DateTimeFormat().resolvedOptions().timeZone
    const now = new Date()
    const date = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`
    const time = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`

    const missing = profiles.filter((p) => {
      // Skip active profile (already loading/loaded) and profiles with TII data
      if (p.profile_id === activeProfileId) return false
      const existing = tiiMap[p.profile_id]
      if (existing) return false
      const lt = p.latest_transit
      return lt?.tii == null
    })
    if (missing.length === 0) return

    let cancelled = false
    // Stagger requests — one at a time, sequential to avoid overloading single-worker server
    let chain = Promise.resolve()
    missing.forEach((p) => {
      chain = chain.then(() => {
        if (cancelled) return
        return fetchTransitReport(p.profile_id, {
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
        }).catch(() => { /* silent */ })
      })
    })

    return () => { cancelled = true }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [profiles, transitLoading])

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

    fetchProfileDetail(activeProfileId, controller.signal, lang)
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
  }, [activeProfileId, lang])


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

    // Show cached transit instantly — don't clear previous data until we know there's nothing cached
    const transitCacheKey = "cachedTransit_" + activeProfileId
    let hasCached = false
    setTransitRefreshing(true)
    try {
      const cached = localStorage.getItem(transitCacheKey)
      if (cached) {
        setTransitReport(JSON.parse(cached))
        setTransitLoading(false)
        hasCached = true
      } else {
        setTransitReport(null)
        setTransitLoading(true)
      }
    } catch {
      setTransitReport(null)
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
    // Get current date/time in the profile's saved timezone (not local browser time)
    const tzDateParts = new Intl.DateTimeFormat("en-CA", { timeZone: savedTz, year: "numeric", month: "2-digit", day: "2-digit" }).format(now)
    const tzTimeParts = new Intl.DateTimeFormat("en-GB", { timeZone: savedTz, hour: "2-digit", minute: "2-digit", hour12: false }).format(now).replace(/[^0-9:]/g, "")
    const params = {
      transit_date: tzDateParts,
      transit_time: tzTimeParts,
      timezone: savedTz,
      location_name: savedLoc,
      latitude: savedLat,
      longitude: savedLon,
      include_timing: true,
      lang,
    }

    function applyReport(report: TransitReportResponse, preserveClimate = false) {
      if (controller.signal.aborted) return
      if (preserveClimate) {
        // Fast phase has no timing → no cosmic_climate. Preserve from current state.
        setTransitReport((prev) => {
          const merged = { ...report }
          if ((!merged.cosmic_climate || merged.cosmic_climate.length === 0) && prev?.cosmic_climate?.length) {
            merged.cosmic_climate = prev.cosmic_climate
          }
          // Also preserve timing data from cache if fast phase lacks it
          if (prev?.active_aspects?.some((a: any) => a.timing) && !report.active_aspects?.some((a: any) => a.timing)) {
            merged.active_aspects = prev.active_aspects
          }
          try { localStorage.setItem(transitCacheKey, JSON.stringify(merged)) } catch {}
          return merged
        })
      } else {
        setTransitReport(report)
        try { localStorage.setItem(transitCacheKey, JSON.stringify(report)) } catch {}
        if (!controller.signal.aborted) setTransitRefreshing(false)
      }
      setTransitLoading(false)
      if (report.tii != null && activeProfileId) {
        const pid = activeProfileId
        setTiiMap((prev) => ({
          ...prev,
          [pid]: {
            tii: report.tii!,
            tension_ratio: report.tension_ratio ?? 0,
            feels_like: report.feels_like ?? "Calm",
            location: report.snapshot?.transit_location_name || report.snapshot?.transit_timezone || savedTz,
          },
        }))
      }
    }

    // Two-phase loading: fast fetch WITHOUT timing first, then upgrade WITH timing in background
    const fastParams = { ...params, include_timing: false }

    fetchTransitReport(activeProfileId, fastParams, controller.signal)
      .then((fastReport) => {
        applyReport(fastReport, true)  // preserve cached climate data
        // Now upgrade with timing data in background
        if (!controller.signal.aborted) {
          fetchTransitReport(activeProfileId, params, controller.signal)
            .then(applyReport)
            .catch(() => { if (!controller.signal.aborted) setTransitRefreshing(false) })
        }
      })
      .catch(() => {
        if (controller.signal.aborted) return
        // Retry with plain browser timezone (saved params may be stale/invalid)
        const fallback = {
          transit_date: params.transit_date,
          transit_time: params.transit_time,
          timezone: browserTz,
          include_timing: false,
          lang,
        }
        fetchTransitReport(activeProfileId, fallback, controller.signal)
          .then((fastReport) => {
            applyReport(fastReport, true)
            // Upgrade with timing
            if (!controller.signal.aborted) {
              fetchTransitReport(activeProfileId, { ...fallback, include_timing: true }, controller.signal)
                .then(applyReport)
                .catch(() => { if (!controller.signal.aborted) setTransitRefreshing(false) })
            }
          })
          .catch(() => {
            if (!controller.signal.aborted) {
              setTransitReport(null)
              setTransitLoading(false)
              setTransitRefreshing(false)
            }
          })
      })

    return () => { controller.abort(); setTransitRefreshing(false) }
  // eslint-disable-next-line react-hooks/exhaustive-deps -- profiles read for location only, no re-fetch needed
  }, [activeProfileId, fetchTrigger, lang])

  const refreshProfile = useCallback(async () => {
    setIsEditing(false)
    if (activeProfileId) {
      try {
        const [detail, profilesPayload] = await Promise.all([
          fetchProfileDetail(activeProfileId, undefined, lang),
          fetchProfiles(),
        ])
        setActiveDetail(detail)
        setProfiles(profilesPayload.profiles)
      } catch {
        // silent — detail will remain stale
      }
    }
  }, [activeProfileId])

  // Public profile search: triggered when searchQuery has 2+ chars
  const trimmedSearch = searchQuery.trim()
  const isPublicSearch = trimmedSearch.length >= 2
  const publicQuery = trimmedSearch.startsWith("@") ? trimmedSearch.slice(1) : trimmedSearch

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
      try { localStorage.setItem("cachedProfiles", JSON.stringify(profilesPayload.profiles)) } catch {}
      setSearchQuery("")
      setPublicResults([])
      setMobileView("detail")

      // Always set the active profile and force re-fetch detail + transits
      // (if already viewing this profile, the ID won't change so we must manually trigger)
      const pid = result.profile_id
      if (pid === activeProfileId) {
        // Same profile — force re-fetch by fetching directly
        try {
          const detail = await fetchProfileDetail(pid, undefined, lang)
          setActiveDetail(detail)
          try { localStorage.setItem("cachedDetail_" + pid, JSON.stringify(detail)) } catch {}
        } catch { /* silent */ }
        setFetchTrigger((n) => n + 1) // re-trigger transit fetch
      } else {
        setActiveProfileId(pid) // different profile — useEffect handles it
      }
    } catch (err) {
      console.error("Follow failed:", err)
    } finally {
      setPublicAddingId(null)
    }
  }, [activeProfileId, lang])

  const handleUnfollowProfile = useCallback(async (profileId: string) => {
    try {
      await unfollowProfile(profileId)
      const profilesPayload = await fetchProfiles()
      setProfiles(profilesPayload.profiles)
      try { localStorage.setItem("cachedProfiles", JSON.stringify(profilesPayload.profiles)) } catch {}
      if (activeProfileId === profileId) {
        // Switch to first remaining profile (the unfollowed one is removed from list)
        const nextId = profilesPayload.profiles[0]?.profile_id || null
        setActiveProfileId(nextId)
      }
    } catch {
      // silent
    }
  }, [activeProfileId])

  // --- Synastry: load partner from per-profile localStorage on profile switch ---
  useEffect(() => {
    if (!activeProfileId) { setSynastryPartnerId(null); setSynastryPartnerName(null); setSynastryPartnerHandle(null); setSynastryPartnerNatalSummary(null); setSynastryReport(null); return }
    const pid = localStorage.getItem(`syn_pid_${activeProfileId}`)
    const pname = localStorage.getItem(`syn_name_${activeProfileId}`)
    const phandle = localStorage.getItem(`syn_handle_${activeProfileId}`)
    let pns: Record<string, string> | null = null
    try { pns = JSON.parse(localStorage.getItem(`syn_ns_${activeProfileId}`) || "null") } catch {}
    setSynastryPartnerId(pid)
    setSynastryPartnerName(pname)
    setSynastryPartnerHandle(phandle)
    setSynastryPartnerNatalSummary(pns)
    setSynastryReport(null)
  }, [activeProfileId])

  // --- Synastry handlers ---
  const handleClearSynastryPartner = useCallback(() => {
    setSynastryPartnerId(null)
    setSynastryPartnerName(null)
    setSynastryPartnerHandle(null)
    setSynastryPartnerNatalSummary(null)
    setSynastryReport(null)
    if (activeProfileId) {
      localStorage.removeItem(`syn_pid_${activeProfileId}`)
      localStorage.removeItem(`syn_name_${activeProfileId}`)
      localStorage.removeItem(`syn_handle_${activeProfileId}`)
      localStorage.removeItem(`syn_ns_${activeProfileId}`)
    }
  }, [activeProfileId])

  const handleSelectSynastryPartner = useCallback((profileId: string, name: string, handle: string, natalSummary: Record<string, string> | string | null) => {
    setSynastryPartnerId(profileId)
    setSynastryPartnerName(name)
    setSynastryPartnerHandle(handle)
    const ns = (natalSummary && typeof natalSummary === "object") ? natalSummary as Record<string, string> : null
    setSynastryPartnerNatalSummary(ns)
    setSynastryReport(null)
    setShowProfilePicker(false)
    if (activeProfileId) {
      localStorage.setItem(`syn_pid_${activeProfileId}`, profileId)
      localStorage.setItem(`syn_name_${activeProfileId}`, name)
      localStorage.setItem(`syn_handle_${activeProfileId}`, handle)
      try { localStorage.setItem(`syn_ns_${activeProfileId}`, JSON.stringify(ns)) } catch {}
    }
    // Prefetch synastry report in the background
    if (synastryPrefetchRef.current) synastryPrefetchRef.current.abort()
    if (activeProfileId) {
      const controller = new AbortController()
      synastryPrefetchRef.current = controller
      fetchSynastryReport(activeProfileId, profileId)
        .then(report => {
          if (!controller.signal.aborted) setSynastryReport(report)
        })
        .catch(err => {
          if (!controller.signal.aborted) console.error("Synastry prefetch failed:", err)
        })
    }
  }, [activeProfileId])

  const handleOpenSynastryReport = useCallback(async () => {
    if (!activeProfileId || !synastryPartnerId) return
    if (synastryReport) {
      setExpandedWidget("synastry")
      return
    }
    setSynastryLoading(true)
    try {
      const report = await fetchSynastryReport(activeProfileId, synastryPartnerId)
      setSynastryReport(report)
      setExpandedWidget("synastry")
    } catch (err: unknown) {
      console.error("Synastry report failed:", err)
      const msg = err instanceof Error ? err.message : String(err)
      alert(`Synastry report error: ${msg}`)
    } finally {
      setSynastryLoading(false)
    }
  }, [activeProfileId, synastryPartnerId, synastryReport])

  const natalPositions = activeDetail?.chart.natal_positions ?? []
  const natalAspects = activeDetail?.chart.natal_aspects ?? []
  const totalTransitAspects = transitReport?.active_aspects?.length ?? 0
  const strongTransitAspects = (transitReport?.active_aspects ?? []).filter(
    (a) => a.strength === "exact" || a.strength === "strong"
  ).length

  // Keep mobile footer above iOS virtual keyboard via VisualViewport API
  const mobileFooterRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const vv = window.visualViewport
    if (!vv) return
    const onResize = () => {
      const el = mobileFooterRef.current
      if (!el) return
      const offsetFromBottom = window.innerHeight - vv.height - vv.offsetTop
      if (offsetFromBottom > 50) {
        // Keyboard is open
        el.style.bottom = `${offsetFromBottom}px`
      } else {
        el.style.bottom = ""
      }
    }
    vv.addEventListener("resize", onResize)
    vv.addEventListener("scroll", onResize)
    return () => {
      vv.removeEventListener("resize", onResize)
      vv.removeEventListener("scroll", onResize)
    }
  }, [])

  // Auth gate: show login screen if not authenticated
  // Invite page: /invite/{token}
  const inviteMatch = window.location.pathname.match(/^\/invite\/([a-f0-9]+)$/)
  if (inviteMatch) {
    return <InviteAcceptPage token={inviteMatch[1]} />
  }

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
    if (showAuth) {
      return <AuthScreen onBack={() => setShowAuth(false)} />
    }
    return <LandingPage onSignIn={() => setShowAuth(true)} onSignUp={() => setShowAuth(true)} />
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
              {"\u2630"}
            </button>
            <B3Logo size="sm" className="sidebar-toolbar__logo" />
            <button
              type="button"
              className="sidebar-toolbar-btn sidebar-toolbar-btn--add"
              onClick={() => setIsCreating(true)}
              title={t("sidebar.newProfile")}
            >
              +
            </button>
          </div>

          {/* Mobile header: "big3.me" title + settings/info */}
          <div className="mobile-list-header">
            <h1 className="mobile-list-title"><span className="brand-big">big</span><span className="brand-3">3</span><span className="brand-me">.me</span></h1>
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
                {profiles.length === 0 && !bootDone && !bootError && !isPublicSearch ? (
                  <SkeletonSidebarItems count={6} />
                ) : (
                  <>
                  {/* Show create-profile prompt when no profiles after boot */}
                  {profiles.length === 0 && !isPublicSearch && bootDone && (
                    <div className="empty-card empty-card--onboard">
                      <strong>{t("profileList.empty")}</strong>
                      <span>{t("profileList.emptyDesc")}</span>
                      <button
                        type="button"
                        className="empty-card__create-btn"
                        onClick={() => setIsCreating(true)}
                      >
                        + {t("sidebar.newProfile")}
                      </button>
                    </div>
                  )}
                  {/* Local profiles — filtered by search, hidden when empty */}
                  {(() => {
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
                    const q = searchQuery.trim().toLowerCase()
                    const filtered = q
                      ? sorted.filter((p) =>
                          p.profile_name.toLowerCase().includes(q)
                          || p.username.toLowerCase().includes(q)
                          || (p.location_name ?? "").toLowerCase().includes(q)
                        )
                      : sorted
                    if (filtered.length === 0) return null
                    return (
                    <ProfileList
                      profiles={filtered}
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
                      onUnfollow={handleUnfollowProfile}
                    />
                    )
                  })()}

                  {/* Public search results */}
                  {isPublicSearch && (
                    <div className="public-search-results">
                      <div className="public-search-divider">{t("sidebar.globalResults")}</div>
                      {publicSearching ? (
                        <div className="public-search-status">
                          <div className="content-loader__spinner" />
                        </div>
                      ) : publicResults.length === 0 ? (
                        <div className="public-search-status">
                          <span>{t("sidebar.publicNoResults")}</span>
                        </div>
                      ) : (
                        publicResults
                          .filter((r) => !profiles.some((p) => p.profile_id === r.profile_id))
                          .map((r) => (
                            <button
                              key={r.profile_id}
                              type="button"
                              className={`profile-list-item public-search-item ${r.profile_id === activeProfileId ? "active" : ""}`}
                              onClick={() => {
                                setActiveProfileId(r.profile_id)
                                setWheelMode("natal")
                                setMobileView("detail")
                              }}
                            >
                              <div className="pli-top">
                                <div className="pli-left">
                                  <div className="pli-name">{r.profile_name}</div>
                                  <div className="pli-location">@{r.username}</div>
                                </div>
                                <button
                                  type="button"
                                  className="pli-follow-btn"
                                  onClick={(e) => { e.stopPropagation(); handleFollowProfile(r) }}
                                  disabled={publicAddingId === r.profile_id}
                                >
                                  {publicAddingId === r.profile_id ? "..." : `+ ${t("sidebar.follow")}`}
                                </button>
                              </div>
                            </button>
                          ))
                      )}
                    </div>
                  )}
                  </>
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
              {/* Mobile footer moved outside sidebar — see below */}
            </>
          )}
        </aside>

        {/* Mobile sticky logo — outside content-pane so visible on list & detail */}
        <div className="b3-logo-mobile-sticky">
          <B3Logo size="sm" />
        </div>

        <div className="content-pane">
          {/* Hero section: DailyWeather, locked preview, or skeleton */}
          {transitReport && activeDetail ? (
            <DailyWeather
              transitReport={transitReport}
              activeDetail={activeDetail}
              loading={transitRefreshing}
              onGuideOpen={() => setGuideOpen(true)}
              onTransitSettings={(date, time, tz, loc) => {
                if (!activeProfileId) return
                autoFetchRef.current?.abort()
                const pid = activeProfileId
                const settingsParams = {
                  transit_date: date,
                  transit_time: time,
                  timezone: tz || undefined,
                  location_name: loc || null,
                  lang,
                }
                function applySettingsReport(report: TransitReportResponse) {
                  setTransitReport(report)
                  try {
                    const saved = JSON.parse(localStorage.getItem("transitParams") || "{}")
                    saved[pid] = {
                      timezone: tz,
                      locationName: loc,
                      latitude: report.snapshot?.transit_latitude ?? null,
                      longitude: report.snapshot?.transit_longitude ?? null,
                    }
                    localStorage.setItem("transitParams", JSON.stringify(saved))
                  } catch { /* ignore */ }
                  if (report.tii != null) {
                    setTiiMap((prev) => ({
                      ...prev,
                      [pid]: {
                        tii: report.tii!,
                        tension_ratio: report.tension_ratio ?? 0,
                        feels_like: report.feels_like ?? "Calm",
                        location: report.snapshot?.transit_location_name || report.snapshot?.transit_timezone || "",
                      },
                    }))
                  }
                }
                // Fast fetch without timing, then upgrade
                setTransitRefreshing(true)
                fetchTransitReport(pid, { ...settingsParams, include_timing: false })
                  .then((fast) => {
                    applySettingsReport(fast)
                    fetchTransitReport(pid, { ...settingsParams, include_timing: true })
                      .then((full) => { applySettingsReport(full); setTransitRefreshing(false) })
                      .catch(() => { setTransitRefreshing(false) })
                  })
                  .catch(() => { setTransitRefreshing(false) })
              }}
            />
          ) : activeDetail && activeProfileId && tiiMap[activeProfileId] ? (
            /* Show partial hero with TII from sidebar data while transit report loads */
            (() => {
              const tiiData = tiiMap[activeProfileId]
              const accent = zoneColor(tiiData.tii)
              const feelsLabel = t(`feels.${tiiData.feels_like}`)
              const emoji = FEELS_EMOJI[tiiData.feels_like] ?? "\u2728"
              const mood = t(`mood.${tiiData.feels_like}`)
              const tzRaw = tiiData.location || ""
              const tzLabel = (() => {
                if (!tzRaw) return ""
                const city = tzRaw.split("/").pop()?.replace(/_/g, " ") ?? tzRaw
                try {
                  const offsetStr = new Intl.DateTimeFormat("en", { timeZone: tzRaw, timeZoneName: "shortOffset" })
                    .formatToParts(new Date())
                    .find((p) => p.type === "timeZoneName")?.value ?? ""
                  return `${city} ${offsetStr}`.toUpperCase()
                } catch { return city.toUpperCase() }
              })()
              return (
                <div className="cw">
                  <div className="cw-hero" style={{ textAlign: "center", padding: "2rem 0" }}>
                    <div className="cw-hero__tz">{tzLabel}</div>
                    <h1 className="cw-hero__name">{activeDetail.profile.profile_name}</h1>
                    <div className="cw-hero__emoji">{emoji}</div>
                    <div className="cw-hero__tii" style={{ color: accent }}>{Math.round(tiiData.tii)}°</div>
                    <div className="cw-hero__sublabel">INTENSITY</div>
                    <div className="cw-hero__feels" style={{ color: accent }}>{feelsLabel}</div>
                    <div className="cw-hero__mood">{mood}</div>
                    <div className="cw-hero__bar-row">
                      <div className="cw-hero__bar">
                        <div className="cw-hero__bar-fill" style={{ width: `${Math.round(tiiData.tension_ratio * 100)}%`, background: accent }} />
                      </div>
                      <span className="cw-hero__bar-label">Tension {Math.round(tiiData.tension_ratio * 100)}%</span>
                    </div>
                  </div>
                </div>
              )
            })()
          ) : activeDetail ? (
            <header className="sticky-header">
              <h1 className="content-profile-name">{activeDetail.profile.profile_name}</h1>
            </header>
          ) : activeProfileId ? (
            <SkeletonHero />
          ) : (
            <header className="sticky-header">
              <h1 className="content-profile-name">{t("widget.selectProfile")}</h1>
            </header>
          )}

          <div className="widget-grid">
            {/* Left column: Followers + Natal + Wheel (was right) */}
            {(() => {
              const isOwnProfile = profiles.some((p) => p.profile_id === activeProfileId)
              return (
            <div className="widget-col-right">
              {/* Moon Phase widget */}
              {transitReport?.moon_phase ? (
                <div className="widget widget--summary">
                  <MoonPhaseWidget transitReport={transitReport} />
                </div>
              ) : null}

              {/* Active Transits widget */}
              {transitReport ? (
                <div className="widget widget--summary">
                  <ActiveTransitsWidget transitReport={transitReport} />
                </div>
              ) : isOwnProfile && (transitLoading || activeProfileId) && !transitReport ? (
                <SkeletonWidget rows={4} />
              ) : !isOwnProfile && activeDetail ? (
                <div className="widget widget--summary locked-preview locked-preview--widget">
                  <div className="locked-preview__title">{t("transits.title")}</div>
                  <div className="locked-preview__content">
                    <div className="locked-preview__content-blur">
                      <div className="locked-preview__group-label">PERSONAL PLANETS</div>
                      <div className="locked-preview__transit-row">
                        <span className="locked-preview__transit-left">
                          <span className="locked-preview__transit-glyphs">♂ △ ♆</span>
                          <span>Mars trine Neptune</span>
                        </span>
                        <span className="locked-preview__transit-right">
                          <span className="locked-preview__transit-orb">0.16°</span>
                          <span className="locked-preview__transit-strength" style={{ background: "rgba(255,152,0,0.15)", color: "#ff9800" }}>EXACT</span>
                        </span>
                      </div>
                      <div className="locked-preview__transit-row">
                        <span className="locked-preview__transit-left">
                          <span className="locked-preview__transit-glyphs">☉ △ ☉</span>
                          <span>Sun trine Sun</span>
                        </span>
                        <span className="locked-preview__transit-right">
                          <span className="locked-preview__transit-orb">0.55°</span>
                          <span className="locked-preview__transit-strength" style={{ background: "rgba(255,152,0,0.15)", color: "#ff9800" }}>STRONG</span>
                        </span>
                      </div>
                      <div className="locked-preview__transit-row">
                        <span className="locked-preview__transit-left">
                          <span className="locked-preview__transit-glyphs">☿ ☍ ♇</span>
                          <span>Mercury opp Pluto</span>
                        </span>
                        <span className="locked-preview__transit-right">
                          <span className="locked-preview__transit-orb">0.83°</span>
                          <span className="locked-preview__transit-strength" style={{ background: "rgba(255,152,0,0.15)", color: "#ff9800" }}>STRONG</span>
                        </span>
                      </div>
                      <div className="locked-preview__transit-row">
                        <span className="locked-preview__transit-left">
                          <span className="locked-preview__transit-glyphs">♂ △ ♀</span>
                          <span>Mars trine Venus</span>
                        </span>
                        <span className="locked-preview__transit-right">
                          <span className="locked-preview__transit-orb">0.87°</span>
                          <span className="locked-preview__transit-strength" style={{ background: "rgba(255,152,0,0.15)", color: "#ff9800" }}>STRONG</span>
                        </span>
                      </div>
                      <div className="locked-preview__group-label">OUTER PLANETS</div>
                      <div className="locked-preview__transit-row">
                        <span className="locked-preview__transit-left">
                          <span className="locked-preview__transit-glyphs">♄ △ ♂</span>
                          <span>Saturn trine Mars</span>
                        </span>
                        <span className="locked-preview__transit-right">
                          <span className="locked-preview__transit-orb">0.47°</span>
                          <span className="locked-preview__transit-strength" style={{ background: "rgba(255,152,0,0.15)", color: "#ff9800" }}>STRONG</span>
                        </span>
                      </div>
                      <div className="locked-preview__transit-row">
                        <span className="locked-preview__transit-left">
                          <span className="locked-preview__transit-glyphs">♆ ✱ ♃</span>
                          <span>Neptune sextile Jupiter</span>
                        </span>
                        <span className="locked-preview__transit-right">
                          <span className="locked-preview__transit-orb">0.58°</span>
                          <span className="locked-preview__transit-strength" style={{ background: "rgba(255,152,0,0.15)", color: "#ff9800" }}>STRONG</span>
                        </span>
                      </div>
                    </div>
                    <div className="locked-preview__glass" data-tooltip={t("widget.followForTransit")}>
                      <span className="locked-preview__lock">🔒</span>
                    </div>
                  </div>
                </div>
              ) : null}

              {/* Cosmic Climate widget */}
              {transitReport ? (
                <div className="widget widget--summary">
                  <CosmicClimateWidget transitReport={transitReport} />
                </div>
              ) : isOwnProfile && (transitLoading || activeProfileId) && !transitReport ? (
                <SkeletonWidget rows={3} />
              ) : !isOwnProfile && activeDetail ? (
                <div className="widget widget--summary locked-preview locked-preview--widget">
                  <div className="locked-preview__title">{t("climate.title")}</div>
                  <div className="locked-preview__content">
                    <div className="locked-preview__content-blur">
                      <div className="locked-preview__climate-card">
                        <div className="locked-preview__climate-header">
                          <span className="locked-preview__climate-left">
                            <span>🔴</span>
                            <span>Pluto ✳ Mars</span>
                          </span>
                          <span className="locked-preview__climate-date">Dec 2025 – Feb 2027</span>
                        </div>
                        <p className="locked-preview__climate-desc">Deep transformation of motivation and willpower. Actions become more purposeful.</p>
                      </div>
                      <div className="locked-preview__climate-card">
                        <div className="locked-preview__climate-header">
                          <span className="locked-preview__climate-left">
                            <span>🪐</span>
                            <span>Saturn △ Venus</span>
                          </span>
                          <span className="locked-preview__climate-date">Jan 2026 – Mar 2026</span>
                        </div>
                        <p className="locked-preview__climate-desc">Stabilizing relationships and values. Commitment deepens naturally.</p>
                      </div>
                    </div>
                    <div className="locked-preview__glass" data-tooltip={t("widget.followForTransit")}>
                      <span className="locked-preview__lock">🔒</span>
                    </div>
                  </div>
                </div>
              ) : null}
            </div>
              )
            })()}

            {/* Right column: Natal + Wheel */}
            <div className="widget-col-left">
              {/* Followers widget */}
              {activeDetail ? (() => {
                const isOwn = activeDetail.profile.is_own === true
                const isFollowed = profiles.some((p) => p.profile_id === activeProfileId && p.is_following === true)
                return (
                <div className="widget widget--followers">
                  <div className="followers-stats">
                    <span className="followers-stat">
                      <strong>{activeDetail.profile.followers_count ?? 0}</strong> {t("profile.followers")}
                    </span>
                  </div>
                  {isOwn ? (
                    <span className="followers-owner">{t("profile.owner")}</span>
                  ) : isFollowed ? (
                    <button
                      type="button"
                      className="followers-btn followers-btn--following"
                      onClick={() => setUnfollowPopup({
                        id: activeDetail.profile.profile_id,
                        name: activeDetail.profile.profile_name,
                        username: activeDetail.profile.username,
                      })}
                    >
                      {t("sidebar.following")}
                    </button>
                  ) : (
                    <button
                      type="button"
                      className="followers-btn followers-btn--follow"
                      onClick={() => {
                        const pub = publicResults.find((r) => r.profile_id === activeProfileId)
                        if (pub) handleFollowProfile(pub)
                      }}
                    >
                      + {t("sidebar.follow")}
                    </button>
                  )}
                </div>
                )
              })() : null}

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
                  <button type="button" className="cw-toggle-wrap wheel-sp-toggle" onClick={(e) => { e.stopPropagation(); toggleSpecialPoints() }}>
                    <span className="cw-toggle-label">{t("wheel.specialPoints")}</span>
                    <div className={`cw-toggle${showSpecialPoints ? " cw-toggle--on" : ""}`}>
                      <div className="cw-toggle-thumb" />
                    </div>
                  </button>
                  {(() => {
                    const canTransit = profiles.some((p) => p.profile_id === activeProfileId)
                    return (
                  <div className="wheel-mode-toggle" onClick={(e) => e.stopPropagation()}>
                    <button type="button" className={wheelMode === "natal" ? "active" : ""} onClick={() => setWheelMode("natal")}>{t("widget.natal")}</button>
                    <span className={!canTransit ? "transit-locked-wrap" : ""} data-tooltip={!canTransit ? t("widget.followForTransit") : undefined}>
                      <button type="button" className={`${wheelMode === "transit" ? "active" : ""} ${!canTransit ? "disabled" : ""}`} disabled={!canTransit} onClick={() => setWheelMode("transit")}>{t("widget.transit")}</button>
                    </span>
                    <span className={!synastryReport ? "transit-locked-wrap" : ""} data-tooltip={!synastryReport ? t("widget.addSynastryFirst") : undefined}>
                      <button type="button" className={`${wheelMode === "synastry" ? "active" : ""} ${!synastryReport ? "disabled" : ""}`} disabled={!synastryReport} onClick={() => setWheelMode("synastry")}>{t("widget.synastry")}</button>
                    </span>
                  </div>
                    )
                  })()}
                  <NatalZodiacRing
                    asc={coerceNumber(activeDetail.chart.asc)}
                    mc={coerceNumber(activeDetail.chart.mc)}
                    houses={activeDetail.chart.houses ?? null}
                    planets={(natalPositions)
                      .filter((p) => Number.isFinite(p.longitude) && (showSpecialPoints || !SPECIAL_POINT_IDS.has(p.id)))
                      .map((p) => ({
                        id: p.id,
                        longitude: p.longitude,
                        glyph: OBJECT_GLYPHS[p.id] ?? p.id.slice(0, 2),
                      }))}
                    transitPlanets={wheelMode === "transit" ? (transitReport?.transit_positions ?? [])
                      .filter((p) => Number.isFinite(p.longitude) && (showSpecialPoints || !SPECIAL_POINT_IDS.has(p.id)))
                      .map((p) => ({
                        id: p.id,
                        longitude: p.longitude,
                        glyph: OBJECT_GLYPHS[p.id] ?? p.id.slice(0, 2),
                      })) : wheelMode === "synastry" ? (synastryReport?.positions_b ?? [])
                      .filter((p) => showSpecialPoints || !SPECIAL_POINT_IDS.has(p.id))
                      .map((p) => ({
                        id: p.id,
                        longitude: (SIGN_OFFSETS[p.sign] ?? 0) + p.degree + p.minute / 60,
                        glyph: OBJECT_GLYPHS[p.id] ?? p.id.slice(0, 2),
                      })) : []}
                    transitAspects={wheelMode === "transit" ? (transitReport?.active_aspects ?? [])
                      .filter((a) => a.is_within_orb && (showSpecialPoints || (!SPECIAL_POINT_IDS.has(a.transit_object) && !SPECIAL_POINT_IDS.has(a.natal_object))))
                      .map((a) => ({
                        transit_object: a.transit_object,
                        natal_object: a.natal_object,
                        aspect: a.aspect,
                        orb: a.orb,
                        strength: a.strength,
                      })) : wheelMode === "synastry" ? (synastryReport?.aspects ?? [])
                      .filter((a) => showSpecialPoints || (!SPECIAL_POINT_IDS.has(a.person_b_object) && !SPECIAL_POINT_IDS.has(a.person_a_object)))
                      .map((a) => ({
                        transit_object: a.person_b_object,
                        natal_object: a.person_a_object,
                        aspect: a.aspect,
                        orb: a.orb,
                        strength: a.strength,
                      })) : []}
                    natalAspects={wheelMode === "natal" ? natalAspects
                      .filter((a) => showSpecialPoints || (!SPECIAL_POINT_IDS.has(a.p1) && !SPECIAL_POINT_IDS.has(a.p2)))
                      .map((a) => ({
                      p1: a.p1,
                      p2: a.p2,
                      aspect: a.aspect,
                      orb: a.orb,
                    })) : []}
                    hideSpecialPoints={!showSpecialPoints}
                    size={700}
                    theme="light"
                  />
                </div>
              ) : activeProfileId ? (
                <SkeletonWheel />
              ) : null}
              {/* Synastry widget */}
              {activeDetail && profiles.some((p) => p.profile_id === activeProfileId) ? (
                <SynastryWidget
                  activeDetail={activeDetail}
                  partnerName={synastryPartnerName}
                  partnerHandle={synastryPartnerHandle}
                  partnerNatalSummary={synastryPartnerNatalSummary}
                  onPickPartner={() => setShowProfilePicker(true)}
                  onClearPartner={handleClearSynastryPartner}
                  onOpenReport={handleOpenSynastryReport}
                  loading={synastryLoading}
                />
              ) : null}
            </div>{/* end widget-col-left */}
          </div>{/* end widget-grid */}
        </div>
      </div>

      {/* Mobile footer: always visible, same position in list & detail */}
      <div className="mobile-footer" ref={mobileFooterRef}>
        <button
          type="button"
          className="mobile-footer-btn mobile-footer-btn--add"
          onClick={() => {
            setMobileView("list")
            setIsCreating(true)
          }}
          title={t("sidebar.newProfile")}
        >
          +
        </button>
        <div className="mobile-search-bar" onClick={() => setMobileView("list")}>
          <span className="mobile-search-icon">{"\uD83D\uDD0D"}</span>
          <input
            type="text"
            enterKeyHint="search"
            placeholder={t("sidebar.search")}
            value={searchQuery}
            onChange={(e) => {
              setSearchQuery(e.target.value)
              setMobileView("list")
            }}
            onFocus={() => {
              setMobileView("list")
              // Prevent iOS from scrolling page up when keyboard opens
              setTimeout(() => window.scrollTo(0, 0), 100)
              setTimeout(() => window.scrollTo(0, 0), 300)
            }}
          />
        </div>
        <button
          type="button"
          className="mobile-footer-btn mobile-footer-btn--menu"
          onClick={() => setMobileView(mobileView === "list" ? "detail" : "list")}
        >
          {"\u2630"}
        </button>
      </div>

      {isEditing && activeProfileId && activeDetail ? (
        <ProfileEditForm
          profileId={activeProfileId}
          activeDetail={activeDetail}
          onClose={() => setIsEditing(false)}
          onSaved={refreshProfile}
        />
      ) : null}

      {showInviteModal && activeProfileId && activeDetail ? (
        <InviteModal
          profileId={activeProfileId}
          profileName={activeDetail.profile.profile_name}
          onClose={() => setShowInviteModal(false)}
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
        <div className="widget-popup-overlay" onClick={(e) => { if (e.target === e.currentTarget) setExpandedWidget(null) }}>
          <div className="widget-popup">
            <div className="widget-popup-head">
              <h3>
                {expandedWidget === "summary" ? t("widget.natalProfile") : null}
                {expandedWidget === "planets" ? t("widget.planetPositions") : null}
                {expandedWidget === "aspects" ? t("widget.natalAspects") : null}
                {expandedWidget === "transits" ? `${t("transits.title")}${activeDetail ? ` — ${activeDetail.profile.profile_name}` : ""}` : null}
                {expandedWidget === "synastry" ? "Synastry Report" : null}
              </h3>
              <div className="widget-popup-head__actions">
                {expandedWidget === "summary" && (() => {
                  const activeP = profiles.find((p) => p.profile_id === activeProfileId)
                  const isOwn = activeP != null && activeP.is_own !== false
                  return isOwn ? (
                    <>
                      <button type="button" className="edit-btn edit-btn--compact edit-btn--transfer" onClick={() => { setExpandedWidget(null); setShowInviteModal(true) }}>{t("invite.transfer")}</button>
                      <button type="button" className="edit-btn edit-btn--compact" onClick={() => { setExpandedWidget(null); setIsEditing(true) }}>{t("widget.edit")}</button>
                    </>
                  ) : null
                })()}
                <button type="button" className="settings-close" onClick={() => setExpandedWidget(null)}>&times;</button>
              </div>
            </div>
            <div className="widget-popup-body">
              {expandedWidget === "summary" && activeDetail ? (
                <div>
                  <ProfileSummaryCard detail={activeDetail} />
                  {natalPositions.length ? <NatalPositionsTable positions={natalPositions} interpretations={activeDetail?.chart.natal_interpretations} /> : null}
                  {natalAspects.length ? <NatalAspectsTable aspects={natalAspects} interpretations={activeDetail?.chart.natal_interpretations} positions={natalPositions} /> : null}
                </div>
              ) : null}
              {expandedWidget === "planets" && natalPositions.length ? (
                <NatalPositionsTable positions={natalPositions} interpretations={activeDetail?.chart.natal_interpretations} />
              ) : null}
              {expandedWidget === "aspects" && natalAspects.length ? (
                <NatalAspectsTable aspects={natalAspects} interpretations={activeDetail?.chart.natal_interpretations} positions={natalPositions} />
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
              {expandedWidget === "synastry" && synastryReport ? (
                <SynastryReport report={synastryReport} />
              ) : null}
            </div>
          </div>
        </div>
      ) : null}

      {/* ===== Fullscreen wheel overlay ===== */}
      {wheelExpanded && activeDetail ? (
        <div className="wheel-fullscreen" onClick={() => setWheelExpanded(false)}>
          <div className="wheel-fullscreen__top-left" onClick={(e) => e.stopPropagation()}>
            <button type="button" className="wheel-fullscreen__close" onClick={() => setWheelExpanded(false)}>&times;</button>
            <B3Logo size="sm" className="wheel-fullscreen__logo" />
          </div>
          <div className="wheel-fullscreen__top-right" onClick={(e) => e.stopPropagation()}>
            <button type="button" className="cw-toggle-wrap wheel-sp-toggle--fs" onClick={toggleSpecialPoints}>
              <span className="cw-toggle-label">{t("wheel.specialPoints")}</span>
              <div className={`cw-toggle${showSpecialPoints ? " cw-toggle--on" : ""}`}>
                <div className="cw-toggle-thumb" />
              </div>
            </button>
            {(() => {
              const canTransit = profiles.some((p) => p.profile_id === activeProfileId)
              return (
            <div className="wheel-fullscreen__toggle">
              <button type="button" className={wheelMode === "natal" ? "active" : ""} onClick={() => setWheelMode("natal")}>{t("wheel.natal")}</button>
              <span className={!canTransit ? "transit-locked-wrap" : ""} data-tooltip={!canTransit ? t("widget.followForTransit") : undefined}>
                <button type="button" className={`${wheelMode === "transit" ? "active" : ""} ${!canTransit ? "disabled" : ""}`} disabled={!canTransit} onClick={() => setWheelMode("transit")}>{t("wheel.transit")}</button>
              </span>
              <span className={!synastryReport ? "transit-locked-wrap" : ""} data-tooltip={!synastryReport ? t("widget.addSynastryFirst") : undefined}>
                <button type="button" className={`${wheelMode === "synastry" ? "active" : ""} ${!synastryReport ? "disabled" : ""}`} disabled={!synastryReport} onClick={() => setWheelMode("synastry")}>{t("wheel.synastry")}</button>
              </span>
            </div>
              )
            })()}
          </div>
          <div className="wheel-fullscreen__content" onClick={(e) => e.stopPropagation()}>
            <div className="wheel-fullscreen__ring">
              <NatalZodiacRing
                asc={coerceNumber(activeDetail.chart.asc)}
                mc={coerceNumber(activeDetail.chart.mc)}
                houses={activeDetail.chart.houses ?? null}
                planets={(natalPositions)
                  .filter((p) => Number.isFinite(p.longitude) && (showSpecialPoints || !SPECIAL_POINT_IDS.has(p.id)))
                  .map((p) => ({
                    id: p.id,
                    longitude: p.longitude,
                    glyph: OBJECT_GLYPHS[p.id] ?? p.id.slice(0, 2),
                  }))}
                transitPlanets={wheelMode === "transit" ? (transitReport?.transit_positions ?? [])
                  .filter((p) => Number.isFinite(p.longitude) && (showSpecialPoints || !SPECIAL_POINT_IDS.has(p.id)))
                  .map((p) => ({
                    id: p.id,
                    longitude: p.longitude,
                    glyph: OBJECT_GLYPHS[p.id] ?? p.id.slice(0, 2),
                  })) : wheelMode === "synastry" ? (synastryReport?.positions_b ?? [])
                  .filter((p) => showSpecialPoints || !SPECIAL_POINT_IDS.has(p.id))
                  .map((p) => ({
                    id: p.id,
                    longitude: (SIGN_OFFSETS[p.sign] ?? 0) + p.degree + p.minute / 60,
                    glyph: OBJECT_GLYPHS[p.id] ?? p.id.slice(0, 2),
                  })) : []}
                transitAspects={wheelMode === "transit" ? (transitReport?.active_aspects ?? [])
                  .filter((a) => a.is_within_orb && (showSpecialPoints || (!SPECIAL_POINT_IDS.has(a.transit_object) && !SPECIAL_POINT_IDS.has(a.natal_object))))
                  .map((a) => ({
                    transit_object: a.transit_object,
                    natal_object: a.natal_object,
                    aspect: a.aspect,
                    orb: a.orb,
                    strength: a.strength,
                  })) : wheelMode === "synastry" ? (synastryReport?.aspects ?? [])
                  .filter((a) => showSpecialPoints || (!SPECIAL_POINT_IDS.has(a.person_b_object) && !SPECIAL_POINT_IDS.has(a.person_a_object)))
                  .map((a) => ({
                    transit_object: a.person_b_object,
                    natal_object: a.person_a_object,
                    aspect: a.aspect,
                    orb: a.orb,
                    strength: a.strength,
                  })) : []}
                natalAspects={wheelMode === "natal" ? natalAspects
                  .filter((a) => showSpecialPoints || (!SPECIAL_POINT_IDS.has(a.p1) && !SPECIAL_POINT_IDS.has(a.p2)))
                  .map((a) => ({
                  p1: a.p1,
                  p2: a.p2,
                  aspect: a.aspect,
                  orb: a.orb,
                })) : []}
                hideSpecialPoints={!showSpecialPoints}
                size={700}
                theme="light"
              />
            </div>
            {natalPositions.length ? (
              <div className="wheel-fullscreen__positions">
                <ChartSidebar
                  positions={natalPositions}
                  natalAspects={natalAspects}
                  mode={wheelMode}
                  transitPositions={transitReport?.transit_positions ?? undefined}
                  transitAspects={transitReport?.active_aspects ?? undefined}
                  synastryPositions={synastryReport?.positions_b ?? undefined}
                  synastryAspects={synastryReport?.aspects ?? undefined}
                />
              </div>
            ) : null}
          </div>
        </div>
      ) : null}

      {guideOpen ? <TiiGuide onClose={() => setGuideOpen(false)} /> : null}

      {/* Unfollow confirmation popup */}
      {unfollowPopup ? (
        <div className="unfollow-popup-overlay" onClick={() => setUnfollowPopup(null)}>
          <div className="unfollow-popup" onClick={(e) => e.stopPropagation()}>
            <div className="unfollow-popup__name">{unfollowPopup.name}</div>
            <div className="unfollow-popup__username">@{unfollowPopup.username}</div>
            <div className="unfollow-popup__actions">
              <button
                type="button"
                className="unfollow-popup__btn unfollow-popup__btn--danger"
                onClick={() => {
                  handleUnfollowProfile(unfollowPopup.id)
                  setUnfollowPopup(null)
                }}
              >
                {t("sidebar.unfollow")}
              </button>
              <button
                type="button"
                className="unfollow-popup__btn unfollow-popup__btn--cancel"
                onClick={() => setUnfollowPopup(null)}
              >
                {t("sidebar.cancel")}
              </button>
            </div>
          </div>
        </div>
      ) : null}

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
          setBootDone(false)
          setTiiMap({})
          setPrimaryProfileId(null)
          // Clear all cached data so next user doesn't see stale profiles
          const keysToRemove = Object.keys(localStorage).filter((k) =>
            k.startsWith("cachedProfiles") || k.startsWith("cachedDetail_") || k.startsWith("cachedTransit_") || k === "cachedTiiMap" || k === "transitParams" || k === "primaryProfileId" || k === "profileOrder"
          )
          keysToRemove.forEach((k) => localStorage.removeItem(k))
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
          setPrimaryProfile(id).catch((err) => console.error("Failed to save primary profile:", err))
        }}
      />

      {/* Profile picker for synastry */}
      <ProfilePickerModal
        open={showProfilePicker}
        onClose={() => setShowProfilePicker(false)}
        onSelect={handleSelectSynastryPartner}
        profiles={profiles}
        excludeProfileId={activeProfileId}
      />
    </main>
  )
}
