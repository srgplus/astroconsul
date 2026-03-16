import type {
  HealthResponse,
  ProfileSummary,
  ProfileDetailResponse,
  ProfileUpsertRequest,
  LocationResponse,
  TransitReportResponse,
  TransitTimelineResponse,
  PublicSearchResult,
} from "./types"
import { supabase } from "./lib/supabase"

// Keep a synchronous cache of the current access token, updated by the
// auth state listener.  This avoids the race condition where
// supabase.auth.getSession() returns null during early page load.
let _cachedToken: string | null = null

supabase.auth.onAuthStateChange((_event, session) => {
  _cachedToken = session?.access_token ?? null
})

// Wait for the cached token to appear (set by onAuthStateChange listener).
// On page reload the listener fires asynchronously, so bootstrap may call
// getAuthHeaders() before the token is cached.  Poll briefly instead of
// sending an unauthenticated request that returns empty data.
function waitForToken(timeoutMs = 3000): Promise<string | null> {
  if (_cachedToken) return Promise.resolve(_cachedToken)
  return new Promise((resolve) => {
    const start = Date.now()
    const id = setInterval(() => {
      if (_cachedToken || Date.now() - start > timeoutMs) {
        clearInterval(id)
        resolve(_cachedToken)
      }
    }, 50)
  })
}

async function getAuthHeaders(): Promise<Record<string, string>> {
  // Wait for the auth listener to populate the cached token
  let token = await waitForToken()

  // Fallback to getSession for edge cases
  if (!token) {
    const { data } = await supabase.auth.getSession()
    token = data.session?.access_token ?? null

    // If token is expiring within 60s, proactively refresh
    if (data.session) {
      const expiresAt = data.session.expires_at ?? 0
      const nowSec = Math.floor(Date.now() / 1000)
      if (expiresAt - nowSec < 60) {
        const { data: refreshed } = await supabase.auth.refreshSession()
        token = refreshed.session?.access_token ?? token
      }
    }
  }

  return token ? { Authorization: `Bearer ${token}` } : {}
}

async function json<T>(response: Response): Promise<T> {
  if (!response.ok) {
    if (response.status === 401) {
      // Try refreshing the session before signing out
      const { data } = await supabase.auth.refreshSession()
      if (!data.session) {
        await supabase.auth.signOut()
      }
    }
    throw new Error(`${response.status} ${response.statusText}`)
  }
  return response.json() as Promise<T>
}

export function fetchHealth(): Promise<HealthResponse> {
  return fetch("/api/v1/health/ready").then(json<HealthResponse>)
}

export async function fetchProfiles(): Promise<{ profiles: ProfileSummary[] }> {
  const headers = await getAuthHeaders()
  return fetch("/api/v1/profiles", { headers }).then(json<{ profiles: ProfileSummary[] }>)
}

export async function fetchProfileDetail(
  profileId: string,
  signal?: AbortSignal,
): Promise<ProfileDetailResponse> {
  const headers = await getAuthHeaders()
  return fetch(`/api/v1/profiles/${encodeURIComponent(profileId)}`, { headers, signal }).then(
    json<ProfileDetailResponse>,
  )
}

export async function fetchTransitReport(
  profileId: string,
  body: {
    transit_date: string
    transit_time: string
    timezone?: string | null
    location_name?: string | null
    latitude?: number | null
    longitude?: number | null
    include_timing?: boolean
    lang?: string
  },
  signal?: AbortSignal,
): Promise<TransitReportResponse> {
  const auth = await getAuthHeaders()
  return fetch(`/api/v1/profiles/${encodeURIComponent(profileId)}/transits/report`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...auth },
    body: JSON.stringify({ lang: body.lang || localStorage.getItem("lang") || "ru", ...body }),
    signal,
  }).then(json<TransitReportResponse>)
}

export async function fetchTransitTimeline(
  profileId: string,
  params: {
    start_date: string
    end_date: string
    timezone: string
  },
  signal?: AbortSignal,
): Promise<TransitTimelineResponse> {
  const auth = await getAuthHeaders()
  const query = new URLSearchParams(params).toString()
  return fetch(
    `/api/v1/profiles/${encodeURIComponent(profileId)}/transits/timeline?${query}`,
    { headers: auth, signal },
  ).then(json<TransitTimelineResponse>)
}

export async function createProfile(
  data: ProfileUpsertRequest,
  signal?: AbortSignal,
): Promise<ProfileDetailResponse> {
  const auth = await getAuthHeaders()
  return fetch("/api/v1/profiles", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...auth },
    body: JSON.stringify(data),
    signal,
  }).then(json<ProfileDetailResponse>)
}

export async function updateProfile(
  profileId: string,
  data: ProfileUpsertRequest,
  signal?: AbortSignal,
): Promise<ProfileDetailResponse> {
  const auth = await getAuthHeaders()
  return fetch(`/api/v1/profiles/${encodeURIComponent(profileId)}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", ...auth },
    body: JSON.stringify(data),
    signal,
  }).then(json<ProfileDetailResponse>)
}

export async function resolveLocation(
  locationName: string,
  signal?: AbortSignal,
): Promise<LocationResponse> {
  const auth = await getAuthHeaders()
  return fetch("/api/v1/locations/resolve", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...auth },
    body: JSON.stringify({ location_name: locationName }),
    signal,
  }).then(json<LocationResponse>)
}

export type PlaceCandidate = {
  display_name: string
  latitude: number
  longitude: number
  timezone: string | null
}

export async function searchPublicProfiles(
  query: string,
  signal?: AbortSignal,
): Promise<PublicSearchResult[]> {
  const auth = await getAuthHeaders()
  return fetch(`/api/v1/profiles/search?q=${encodeURIComponent(query)}`, { headers: auth, signal })
    .then(json<{ results: PublicSearchResult[] }>)
    .then((data) => data.results)
}

export async function followProfile(
  profileId: string,
  signal?: AbortSignal,
): Promise<{ status: string }> {
  const auth = await getAuthHeaders()
  return fetch(`/api/v1/profiles/${encodeURIComponent(profileId)}/follow`, {
    method: "POST",
    headers: auth,
    signal,
  }).then(json<{ status: string }>)
}

export async function unfollowProfile(
  profileId: string,
  signal?: AbortSignal,
): Promise<{ status: string }> {
  const auth = await getAuthHeaders()
  return fetch(`/api/v1/profiles/${encodeURIComponent(profileId)}/follow`, {
    method: "DELETE",
    headers: auth,
    signal,
  }).then(json<{ status: string }>)
}

export async function searchLocations(
  query: string,
  signal?: AbortSignal,
): Promise<PlaceCandidate[]> {
  const auth = await getAuthHeaders()
  return fetch(`/api/v1/locations/search?q=${encodeURIComponent(query)}`, { headers: auth, signal })
    .then(json<PlaceCandidate[]>)
}
