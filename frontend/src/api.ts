import type {
  HealthResponse,
  ProfileSummary,
  ProfileDetailResponse,
  ProfileUpsertRequest,
  LocationResponse,
  TransitReportResponse,
  TransitTimelineResponse,
} from "./types"

async function json<T>(response: Response): Promise<T> {
  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}`)
  }
  return response.json() as Promise<T>
}

export function fetchHealth(): Promise<HealthResponse> {
  return fetch("/api/v1/health/ready").then(json<HealthResponse>)
}

export function fetchProfiles(): Promise<{ profiles: ProfileSummary[] }> {
  return fetch("/api/v1/profiles").then(json<{ profiles: ProfileSummary[] }>)
}

export function fetchProfileDetail(
  profileId: string,
  signal?: AbortSignal,
): Promise<ProfileDetailResponse> {
  return fetch(`/api/v1/profiles/${encodeURIComponent(profileId)}`, { signal }).then(
    json<ProfileDetailResponse>,
  )
}

export function fetchTransitReport(
  profileId: string,
  body: {
    transit_date: string
    transit_time: string
    timezone?: string | null
    location_name?: string | null
    latitude?: number | null
    longitude?: number | null
    include_timing?: boolean
  },
  signal?: AbortSignal,
): Promise<TransitReportResponse> {
  return fetch(`/api/v1/profiles/${encodeURIComponent(profileId)}/transits/report`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal,
  }).then(json<TransitReportResponse>)
}

export function fetchTransitTimeline(
  profileId: string,
  params: {
    start_date: string
    end_date: string
    timezone: string
  },
  signal?: AbortSignal,
): Promise<TransitTimelineResponse> {
  const query = new URLSearchParams(params).toString()
  return fetch(
    `/api/v1/profiles/${encodeURIComponent(profileId)}/transits/timeline?${query}`,
    { signal },
  ).then(json<TransitTimelineResponse>)
}

export function updateProfile(
  profileId: string,
  data: ProfileUpsertRequest,
  signal?: AbortSignal,
): Promise<ProfileDetailResponse> {
  return fetch(`/api/v1/profiles/${encodeURIComponent(profileId)}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
    signal,
  }).then(json<ProfileDetailResponse>)
}

export function resolveLocation(
  locationName: string,
  signal?: AbortSignal,
): Promise<LocationResponse> {
  return fetch("/api/v1/locations/resolve", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
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

export function searchLocations(
  query: string,
  signal?: AbortSignal,
): Promise<PlaceCandidate[]> {
  return fetch(`/api/v1/locations/search?q=${encodeURIComponent(query)}`, { signal })
    .then(json<PlaceCandidate[]>)
}
