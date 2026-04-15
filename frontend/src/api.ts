import type {
  HealthResponse,
  ProfileSummary,
  ProfileDetailResponse,
  ProfileUpsertRequest,
  LocationResponse,
  TransitReportResponse,
  TransitTimelineResponse,
  PublicSearchResult,
  ForecastResponse,
  SynastryReportResponse,
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

export async function getAuthHeaders(): Promise<Record<string, string>> {
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
    let detail = response.statusText
    try {
      const body = await response.json()
      if (body.detail) detail = body.detail
    } catch { /* not JSON */ }
    throw new Error(detail)
  }
  return response.json() as Promise<T>
}

export function fetchHealth(): Promise<HealthResponse> {
  return fetch("/api/v1/health/ready").then(json<HealthResponse>)
}

export async function fetchProfiles(): Promise<{ profiles: ProfileSummary[]; primary_profile_id?: string | null }> {
  const headers = await getAuthHeaders()
  return fetch("/api/v1/profiles", { headers }).then(json<{ profiles: ProfileSummary[]; primary_profile_id?: string | null }>)
}

export async function setPrimaryProfile(profileId: string): Promise<{ status: string }> {
  const headers = await getAuthHeaders()
  return fetch("/api/v1/profiles/primary", {
    method: "PUT",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({ profile_id: profileId }),
  }).then(json<{ status: string }>)
}

export async function fetchProfileDetail(
  profileId: string,
  signal?: AbortSignal,
  lang?: string,
): Promise<ProfileDetailResponse> {
  const headers = await getAuthHeaders()
  const l = lang || localStorage.getItem("lang") || "en"
  return fetch(`/api/v1/profiles/${encodeURIComponent(profileId)}?lang=${l}`, { headers, signal }).then(
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
    body: JSON.stringify({ ...body, lang: body.lang || localStorage.getItem("lang") || "en" }),
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

export async function fetchForecast(
  profileId: string,
  params: { days?: number; timezone: string; lang?: string },
  signal?: AbortSignal,
): Promise<ForecastResponse> {
  const auth = await getAuthHeaders()
  const query = new URLSearchParams({
    days: String(params.days ?? 10),
    timezone: params.timezone,
    lang: params.lang || localStorage.getItem("lang") || "en",
  }).toString()
  return fetch(
    `/api/v1/profiles/${encodeURIComponent(profileId)}/transits/forecast?${query}`,
    { headers: auth, signal },
  ).then(json<ForecastResponse>)
}

// --- Invite endpoints ---

export type InviteInfo = {
  token: string
  profile_name: string
  invited_email: string
  invited_by_email: string
  status: string
  expires_at: string
}

export async function createProfileInvite(
  profileId: string,
  email: string,
): Promise<{ status: string; token: string; invite_url: string; email_sent: boolean }> {
  const auth = await getAuthHeaders()
  return fetch(`/api/v1/profiles/${encodeURIComponent(profileId)}/invite`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...auth },
    body: JSON.stringify({ email }),
  }).then(json<{ status: string; token: string; invite_url: string; email_sent: boolean }>)
}

export function fetchInviteInfo(token: string): Promise<InviteInfo> {
  return fetch(`/api/v1/invites/${encodeURIComponent(token)}`).then(json<InviteInfo>)
}

export async function acceptInvite(
  token: string,
): Promise<{ status: string; profile_id: string; profile_name: string }> {
  const auth = await getAuthHeaders()
  return fetch(`/api/v1/invites/${encodeURIComponent(token)}/accept`, {
    method: "POST",
    headers: auth,
  }).then(json<{ status: string; profile_id: string; profile_name: string }>)
}

// --- Synastry ---

export async function fetchSynastryReport(
  profileId: string,
  partnerProfileId: string,
  signal?: AbortSignal,
): Promise<SynastryReportResponse> {
  const auth = await getAuthHeaders()
  const lang = localStorage.getItem("lang") || "en"
  return fetch(`/api/v1/profiles/${encodeURIComponent(profileId)}/synastry`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...auth },
    body: JSON.stringify({ partner_profile_id: partnerProfileId, lang }),
    signal,
  }).then(json<SynastryReportResponse>)
}

// --- Public (no-auth) endpoints ---

export function fetchFeaturedProfiles(): Promise<{ profiles: ProfileSummary[] }> {
  return fetch("/api/v1/public/featured").then(json<{ profiles: ProfileSummary[] }>)
}

export function fetchPublicProfileDetail(profileId: string, lang?: string): Promise<ProfileDetailResponse> {
  const l = lang || localStorage.getItem("lang") || "en"
  return fetch(`/api/v1/public/profiles/${encodeURIComponent(profileId)}?lang=${l}`).then(json<ProfileDetailResponse>)
}

// ── Subscriptions & Payments ────────────────────────────────────────

export async function fetchSubscriptionStatus(): Promise<{
  plan: string
  is_pro: boolean
  expires_at: string | null
}> {
  const auth = await getAuthHeaders()
  return fetch("/api/v1/subscriptions/status", { headers: auth }).then(
    json<{ plan: string; is_pro: boolean; expires_at: string | null }>
  )
}

export async function createCheckoutSession(plan: string): Promise<{ checkout_url: string }> {
  const auth = await getAuthHeaders()
  return fetch("/api/v1/payments/create-checkout", {
    method: "POST",
    headers: { ...auth, "Content-Type": "application/json" },
    body: JSON.stringify({ plan }),
  }).then(json<{ checkout_url: string }>)
}

export async function verifyAppleTransaction(
  transactionId: string,
  productId: string,
  originalTransactionId?: string,
): Promise<{ status: string; plan: string; already_active?: boolean }> {
  const auth = await getAuthHeaders()
  return fetch("/api/v1/payments/verify-apple", {
    method: "POST",
    headers: { ...auth, "Content-Type": "application/json" },
    body: JSON.stringify({
      transaction_id: transactionId,
      product_id: productId,
      original_transaction_id: originalTransactionId || null,
    }),
  }).then(json<{ status: string; plan: string; already_active?: boolean }>)
}

export async function deleteAccount(): Promise<void> {
  const auth = await getAuthHeaders()
  const res = await fetch("/api/v1/auth/account", {
    method: "DELETE",
    headers: auth,
  })
  if (!res.ok && res.status !== 204) {
    const text = await res.text().catch(() => "")
    throw new Error(`Account deletion failed (${res.status}): ${text}`)
  }
}
