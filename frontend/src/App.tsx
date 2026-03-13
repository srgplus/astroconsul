import { useEffect, useState } from "react"
import { NatalZodiacRing } from "./components/NatalZodiacRing"

type HealthResponse = {
  status: string
  checks?: Record<string, { status: string; detail?: string }>
}

type ProfileSummary = {
  profile_id: string
  profile_name: string
  username: string
  location_name?: string | null
  local_birth_datetime?: string | null
}

type SavedChart = {
  asc?: number | string | null
  mc?: number | string | null
  houses?: Array<number | string> | null
  location_name?: string | null
  local_birth_datetime?: string | null
}

type ProfileDetailResponse = {
  profile: ProfileSummary
  chart: SavedChart
}

function coerceNumber(value: number | string | null | undefined): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value
  }

  if (typeof value === "string") {
    const numeric = Number(value)
    return Number.isFinite(numeric) ? numeric : null
  }

  return null
}

function profileMeta(detail: ProfileDetailResponse | null): string {
  if (!detail) return "Natal chart profile"

  const bits = [
    detail.profile.username ? `@${detail.profile.username}` : null,
    detail.chart.location_name || detail.profile.location_name || null,
    detail.chart.local_birth_datetime || detail.profile.local_birth_datetime || null,
  ].filter(Boolean)

  return bits.length ? bits.join(" · ") : "Natal chart profile"
}

export function App() {
  const [health, setHealth] = useState<HealthResponse | null>(null)
  const [profiles, setProfiles] = useState<ProfileSummary[]>([])
  const [activeProfileId, setActiveProfileId] = useState<string | null>(null)
  const [activeDetail, setActiveDetail] = useState<ProfileDetailResponse | null>(null)
  const [bootError, setBootError] = useState<string | null>(null)
  const [detailError, setDetailError] = useState<string | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)

  useEffect(() => {
    let cancelled = false

    async function bootstrap() {
      try {
        const [healthResponse, profilesResponse] = await Promise.all([
          fetch("/api/v1/health/ready"),
          fetch("/api/v1/profiles"),
        ])

        if (!healthResponse.ok) {
          throw new Error("Health endpoint did not respond successfully.")
        }

        if (!profilesResponse.ok) {
          throw new Error("Profiles endpoint did not respond successfully.")
        }

        const [healthPayload, profilesPayload] = await Promise.all([
          healthResponse.json() as Promise<HealthResponse>,
          profilesResponse.json() as Promise<{ profiles: ProfileSummary[] }>,
        ])

        if (cancelled) {
          return
        }

        setHealth(healthPayload)
        setProfiles(profilesPayload.profiles)
        setActiveProfileId((currentValue) => currentValue || profilesPayload.profiles[0]?.profile_id || null)
      } catch (caughtError) {
        if (!cancelled) {
          setBootError(caughtError instanceof Error ? caughtError.message : "Unknown error")
        }
      }
    }

    bootstrap()
    return () => {
      cancelled = true
    }
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

    async function loadProfileDetail() {
      try {
        const response = await fetch(`/api/v1/profiles/${encodeURIComponent(activeProfileId)}`, {
          signal: controller.signal,
        })

        if (!response.ok) {
          throw new Error("Profile detail endpoint did not respond successfully.")
        }

        const payload = await response.json() as ProfileDetailResponse
        setActiveDetail(payload)
      } catch (caughtError) {
        if (controller.signal.aborted) {
          return
        }

        setActiveDetail(null)
        setDetailError(caughtError instanceof Error ? caughtError.message : "Unknown error")
      } finally {
        if (!controller.signal.aborted) {
          setDetailLoading(false)
        }
      }
    }

    loadProfileDetail()
    return () => controller.abort()
  }, [activeProfileId])

  const activeAsc = coerceNumber(activeDetail?.chart.asc)
  const activeMc = coerceNumber(activeDetail?.chart.mc)

  return (
    <main className="app-shell">
      <section className="hero">
        <div className="hero-topline">
          <div className="eyebrow">Astro Consul</div>
          {health ? <span className={`status ${health.status}`}>API {health.status}</span> : null}
        </div>
        <h1>Natal Zodiac Ring</h1>
        <p>
          Phase one is intentionally narrow: render only the outer zodiac ring in SVG, rotate it from the active
          profile&apos;s natal ASC, and keep the center empty until the next layers arrive.
        </p>
      </section>

      <section className="profile-layout">
        <article className="card profile-list-card">
          <div className="card-head">
            <div className="eyebrow">Profile</div>
            <h2>Active natal source</h2>
          </div>

          {profiles.length ? (
            <div className="profile-list">
              {profiles.map((profile) => (
                <button
                  key={profile.profile_id}
                  type="button"
                  className={`profile-list-item ${profile.profile_id === activeProfileId ? "active" : ""}`}
                  onClick={() => setActiveProfileId(profile.profile_id)}
                >
                  <strong>{profile.profile_name}</strong>
                  <span>@{profile.username}</span>
                  {profile.location_name ? <span>{profile.location_name}</span> : null}
                </button>
              ))}
            </div>
          ) : (
            <div className="empty-card">
              <strong>No profiles yet</strong>
              <span>Create a natal profile first to preview the zodiac ring.</span>
            </div>
          )}
        </article>

        <article className="card ring-card">
          <div className="card-head">
            <div className="eyebrow">Profile View</div>
            <h2>{activeDetail?.profile.profile_name || "Waiting for an active profile"}</h2>
            <p>{profileMeta(activeDetail)}</p>
          </div>

          {detailLoading ? (
            <div className="ring-stage loading-state">
              <p>Loading natal chart context…</p>
            </div>
          ) : null}

          {!detailLoading && detailError ? (
            <div className="ring-stage error-state">
              <strong>Unable to load profile detail</strong>
              <span>{detailError}</span>
            </div>
          ) : null}

          {!detailLoading && !detailError && !activeProfileId ? (
            <div className="ring-stage empty-state">
              <strong>Select a profile</strong>
              <span>The natal zodiac ring will appear here for the active profile.</span>
            </div>
          ) : null}

          {!detailLoading && !detailError && activeProfileId ? (
            <div className="ring-stage">
              <NatalZodiacRing
                asc={activeAsc}
                mc={activeMc}
                houses={activeDetail?.chart.houses ?? null}
                size={520}
                theme="light"
              />
            </div>
          ) : null}
        </article>
      </section>

      {bootError ? (
        <section className="card error-card">
          <h2>Bootstrap Error</h2>
          <p>{bootError}</p>
        </section>
      ) : null}
    </main>
  )
}
