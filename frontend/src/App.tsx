import { useEffect, useState, useCallback } from "react"
import { fetchHealth, fetchProfiles, fetchProfileDetail, fetchTransitReport } from "./api"
import { ProfileList } from "./components/ProfileList"
import { ProfileDetail } from "./components/ProfileDetail"
import { ProfileEditForm } from "./components/ProfileEditForm"
import { TransitsTab } from "./components/TransitsTab"
import type { HealthResponse, ProfileSummary, ProfileDetailResponse, TransitReportResponse } from "./types"

type View = "profile" | "transits"
type Theme = "system" | "light" | "dark"

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

export function App() {
  const [theme, setTheme] = useTheme()
  const [health, setHealth] = useState<HealthResponse | null>(null)
  const [profiles, setProfiles] = useState<ProfileSummary[]>([])
  const [activeProfileId, setActiveProfileId] = useState<string | null>(null)
  const [activeDetail, setActiveDetail] = useState<ProfileDetailResponse | null>(null)
  const [bootError, setBootError] = useState<string | null>(null)
  const [detailError, setDetailError] = useState<string | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [activeView, setActiveView] = useState<View>("profile")
  const [isEditing, setIsEditing] = useState(false)
  const [transitReport, setTransitReport] = useState<TransitReportResponse | null>(null)

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
          // Saved params failed — retry with current time
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

  return (
    <main className="app-shell">
      <section className="hero">
        <div className="hero-topline">
          <div className="eyebrow">Astro Consul</div>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <button
              type="button"
              className="theme-toggle"
              onClick={() => setTheme(theme === "dark" ? "light" : theme === "light" ? "system" : "dark")}
              title={`Theme: ${theme}`}
            >
              {theme === "dark" ? "\u263D" : theme === "light" ? "\u2600" : "\u25D0"}
            </button>
            {health ? <span className={`status ${health.status}`}>API {health.status}</span> : null}
          </div>
        </div>
        <h1>Astro Consul</h1>
        <p>Natal chart profiles and transit reports.</p>
      </section>

      <div className="main-layout">
        <aside className="sidebar">
          <div className="sidebar-head">
            <div className="eyebrow">Profiles</div>
          </div>
          <ProfileList
            profiles={profiles}
            activeProfileId={activeProfileId}
            onSelect={setActiveProfileId}
          />
        </aside>

        <section className="content-area">
          <nav className="content-tabs">
            <button
              type="button"
              className={`tab-button ${activeView === "profile" ? "active" : ""}`}
              onClick={() => setActiveView("profile")}
            >
              Profile
            </button>
            <button
              type="button"
              className={`tab-button ${activeView === "transits" ? "active" : ""}`}
              onClick={() => setActiveView("transits")}
            >
              Transits
            </button>
          </nav>

          <div className="content-body card">
            <div style={{ display: activeView === "profile" ? "contents" : "none" }}>
              <ProfileDetail
                activeDetail={activeDetail}
                detailLoading={detailLoading}
                detailError={detailError}
                activeProfileId={activeProfileId}
                transitReport={transitReport}
                onEditClick={() => setIsEditing(true)}
              />
            </div>
            <div style={{ display: activeView === "transits" ? "contents" : "none" }}>
              <TransitsTab
                activeProfileId={activeProfileId}
                activeDetail={activeDetail}
                onTransitReport={setTransitReport}
                initialReport={transitReport}
              />
            </div>
          </div>
        </section>
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
    </main>
  )
}
