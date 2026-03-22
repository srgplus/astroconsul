// ---------------------------------------------------------------------------
// Shared TypeScript types — mirrors actual backend API payloads
// ---------------------------------------------------------------------------

// --- Health ---

export type HealthCheck = {
  status: string
  detail?: string
}

export type HealthResponse = {
  status: string
  checks?: Record<string, HealthCheck>
}

// --- Profiles ---

export type LatestTransit = {
  transit_date: string
  transit_time: string
  timezone: string
  location_name: string | null
  latitude: number | null
  longitude: number | null
  updated_at: string
  tii: number | null
  tension_ratio: number | null
  feels_like: string | null
}

export type ProfileSummary = {
  profile_id: string
  profile_name: string
  username: string
  location_name?: string | null
  local_birth_datetime?: string | null
  latest_transit?: LatestTransit | null
  is_own?: boolean | null
  is_following?: boolean | null
  followers_count?: number
  following_count?: number
}

export type NatalPosition = {
  id: string
  longitude: number
  degree: number
  minute: number
  second: number
  sign: string
  formatted_position: string
  house: number
  retrograde: boolean | null
  speed: number | null
}

export type AnglePosition = {
  id: string
  longitude: number
  degree: number
  minute: number
  second: number
  sign: string
  formatted_position: string
}

export type NatalAspect = {
  p1: string
  p2: string
  aspect: string
  angle: number
  delta: number
  orb: number
}

export type NatalInterpretation = {
  meaning: string
  keywords: string[]
}

export type NatalAspectInterpretation = {
  p1: string
  p2: string
  aspect: string
  meaning: string
  keywords: string[]
}

export type HouseCuspInterpretation = NatalInterpretation & { sign: string }

export type NatalInterpretations = {
  planets_in_signs: Record<string, NatalInterpretation>
  planets_in_houses: Record<string, NatalInterpretation>
  house_cusps_in_signs: Record<string, HouseCuspInterpretation>
  aspects: NatalAspectInterpretation[]
}

export type SavedChart = {
  chart_id?: string
  asc?: number | string | null
  mc?: number | string | null
  houses?: Array<number | string> | null
  planets?: Record<string, number> | null
  natal_positions?: NatalPosition[] | null
  angle_positions?: AnglePosition[] | null
  natal_aspects?: NatalAspect[] | null
  natal_interpretations?: NatalInterpretations | null
  location_name?: string | null
  local_birth_datetime?: string | null
  house_system?: string | null
  [key: string]: unknown
}

export type ProfileDetailResponse = {
  profile: ProfileSummary
  chart: SavedChart
}

// --- Transits ---

export type TransitSnapshot = {
  chart_id: string
  profile_id?: string | null
  transit_utc_datetime: string
  transit_date: string
  transit_time_ut: string
  transit_timezone: string
  transit_location_name: string | null
  transit_latitude: number | null
  transit_longitude: number | null
  house_system: string | null
  ephemeris_version: string
  [key: string]: unknown
}

export type TransitPosition = {
  id: string
  longitude: number
  degree: number
  minute: number
  second: number
  sign: string
  formatted_position: string
  speed: number
  retrograde: boolean
  natal_house: number
}

export type ExactPass = {
  utc: string
  orb: number
}

export type AspectTiming = {
  start_utc: string | null
  peak_utc: string | null
  exact_utc: string | null
  end_utc: string | null
  peak_orb: number | null
  status: string | null
  will_perfect: boolean
  duration_hours: number | null
  exact_passes?: ExactPass[]
}

export type ActiveAspect = {
  transit_object: string
  natal_object: string
  aspect: string
  exact_angle: number
  delta: number
  orb: number
  is_within_orb: boolean
  strength: string
  timing: AspectTiming | null
  meaning: string | null
  action: string | null
  insight: string | null
  keywords: string[] | null
}

export type TopTransit = {
  transit_object: string
  natal_object: string
  aspect: string
  orb: number
  strength: string
  _tii_contribution: number
}

export type RetrogradeIndex = {
  count: number
  index: number
  planets: string[]
}

export type MoonPhase = {
  phase_name: string
  phase_angle: number
  illumination_pct: number
  moon_sign: string
  moon_degree: number
  phase_emoji: string
}

export type TransitReportResponse = {
  snapshot: TransitSnapshot | null
  natal_positions: NatalPosition[] | null
  angle_positions: AnglePosition[] | null
  transit_positions: TransitPosition[] | null
  active_aspects: ActiveAspect[] | null
  tii: number | null
  tension_ratio: number | null
  feels_like: string | null
  top_transits: TopTransit[] | null
  cosmic_climate: ActiveAspect[] | null
  ope: number | null
  retrograde_index: RetrogradeIndex | null
  moon_phase: MoonPhase | null
}

export type TimelineItem = {
  transit: string
  natal: string
  aspect: string
  start_utc: string | null
  exact_utc: string | null
  end_utc: string | null
  display_utc: string | null
  strength: string
}

export type TransitTimelineResponse = {
  timeline: TimelineItem[]
}

// --- Profile Edit ---

export type ProfileUpsertRequest = {
  profile_name: string
  username: string
  birth_date: string
  birth_time: string
  timezone: string | null
  location_name: string | null
  latitude: number
  longitude: number
  time_basis?: string | null
  name?: string | null
}

// --- Public Profile Search ---

export type PublicSearchResult = {
  profile_id: string
  profile_name: string
  username: string
  birth_date: string
  birth_time: string
  timezone: string
  location_name: string
  latitude: number
  longitude: number
  natal_summary: Record<string, string> | string | null
}

export type LocationResponse = {
  location_name: string
  resolved_name: string
  latitude: number
  longitude: number
  timezone: string
  source: string | null
}

// --- Forecast ---

export type DailyForecastItem = {
  date: string
  tii: number
  tension_ratio: number
  feels_like: string
  ope: number
  retrograde_count: number
  retrograde_planets: string[]
  velocity_delta: number | null
  velocity_direction: string | null
  top_transits: TopTransit[]
  moon_phase?: MoonPhase | null
}

export type ForecastResponse = {
  days: DailyForecastItem[]
}

// --- Synastry ---

export type SynastryScores = {
  overall: number
  overall_label: string
  emotional: number
  mental: number
  physical: number
  karmic: number
}

export type SynastryAspect = {
  person_a_object: string
  person_b_object: string
  aspect: string
  exact_angle?: number
  delta?: number
  orb: number
  strength: string
  meaning: string | null
  keywords: string[] | null
}

export type SynastryPersonSummary = {
  name: string
  handle: string
  profile_id: string
  natal_summary: Record<string, string> | null
}

export type SynastryReportResponse = {
  person_a: SynastryPersonSummary
  person_b: SynastryPersonSummary
  scores: SynastryScores
  aspects: SynastryAspect[]
  aspect_count: number
  exact_count: number
  strong_count?: number
  overall_reading: string | null
}
