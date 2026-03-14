import { Fragment } from "react"
import type { NatalAspect, NatalPosition, ProfileDetailResponse, TransitReportResponse } from "../types"

type ProfileDetailProps = {
  activeDetail: ProfileDetailResponse | null
  detailLoading: boolean
  detailError: string | null
  activeProfileId: string | null
  transitReport: TransitReportResponse | null
  onEditClick: () => void
}

function coerceNumber(value: number | string | null | undefined): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value === "string") {
    const n = Number(value)
    return Number.isFinite(n) ? n : null
  }
  return null
}

const OBJECT_GLYPHS: Record<string, string> = {
  Sun: "\u2609",
  Moon: "\u263D",
  Mercury: "\u263F",
  Venus: "\u2640",
  Mars: "\u2642",
  Jupiter: "\u2643",
  Saturn: "\u2644",
  Uranus: "\u2645",
  Neptune: "\u2646",
  Pluto: "\u2BD3",
  Chiron: "\u26B7",
  Lilith: "\u26B8",
  Selena: "\u2BCC",
  "North Node": "\u260A",
  "South Node": "\u260B",
  "Part of Fortune": "\u2297",
  Vertex: "\u22C1",
  ASC: "",
  MC: "",
}

const SIGN_GLYPHS: Record<string, string> = {
  Aries: "\u2648",
  Taurus: "\u2649",
  Gemini: "\u264A",
  Cancer: "\u264B",
  Leo: "\u264C",
  Virgo: "\u264D",
  Libra: "\u264E",
  Scorpio: "\u264F",
  Sagittarius: "\u2650",
  Capricorn: "\u2651",
  Aquarius: "\u2652",
  Pisces: "\u2653",
}

type ObjectGroup = { label: string; ids: string[] }

const GROUPS: ObjectGroup[] = [
  { label: "Personal Planets", ids: ["Sun", "ASC", "MC", "Moon", "Mercury", "Venus", "Mars"] },
  { label: "Outer Planets", ids: ["Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"] },
  { label: "Special Points", ids: ["Chiron", "Lilith", "Selena", "North Node", "South Node", "Part of Fortune", "Vertex"] },
]

const DISPLAY_NAMES: Record<string, string> = { Selena: "Selene" }
function dn(id: string): string { return DISPLAY_NAMES[id] ?? id }

function formatPosition(p: NatalPosition): string {
  return `${p.sign} ${p.degree}\u00B0${String(p.minute).padStart(2, "0")}'${String(Math.round(p.second)).padStart(2, "0")}"`
}

function retroLabel(r: boolean | null): string {
  if (r === true) return "Yes"
  if (r === false) return "No"
  return "\u2014"
}

export function NatalPositionsTable({ positions }: { positions: NatalPosition[] }) {
  const byId = new Map(positions.map((p) => [p.id, p]))

  return (
    <div className="natal-pos">
      {GROUPS.map((group) => {
        const rows = group.ids.map((id) => byId.get(id)).filter(Boolean) as NatalPosition[]
        if (!rows.length) return null
        return (
          <Fragment key={group.label}>
            <div className="natal-pos__group">{group.label}</div>
            {rows.map((p) => (
              <div key={p.id} className="natal-pos__row">
                <span className="natal-pos__glyph">{OBJECT_GLYPHS[p.id] ?? ""}</span>
                <span className="natal-pos__name">{dn(p.id)}</span>
                <span className="natal-pos__house">△{p.house || "—"}</span>
                <span className="natal-pos__sign">{SIGN_GLYPHS[p.sign] ?? ""}</span>
                <span className="natal-pos__sign-name">{p.sign}</span>
                <span className="natal-pos__deg">{p.degree}°{String(p.minute).padStart(2, "0")}′</span>
                {p.retrograde ? <span className="natal-pos__retro">Ⓡ</span> : null}
              </div>
            ))}
          </Fragment>
        )
      })}
    </div>
  )
}

const ASPECT_GLYPHS: Record<string, string> = {
  conjunction: "\u260C",
  opposition: "\u260D",
  trine: "\u25B3",
  square: "\u25A1",
  sextile: "\u26B9",
}

function aspectStrength(orb: number): string {
  if (orb < 1) return "exact"
  if (orb < 3) return "strong"
  if (orb < 5) return "moderate"
  return "wide"
}

const PERSONAL_IDS = new Set(["Sun", "Moon", "Mercury", "Venus", "Mars", "ASC", "MC"])
const OUTER_IDS = new Set(["Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"])

function categorizeNatalAspect(a: NatalAspect): string {
  if (PERSONAL_IDS.has(a.p1)) return "Personal Planets"
  if (OUTER_IDS.has(a.p1)) return "Outer Planets"
  return "Special Points"
}

export function NatalAspectsTable({ aspects }: { aspects: NatalAspect[] }) {
  const sorted = [...aspects].sort((a, b) => a.orb - b.orb)

  const groupOrder = ["Personal Planets", "Outer Planets", "Special Points"]
  const groups: Record<string, NatalAspect[]> = {}
  for (const a of sorted) {
    const cat = categorizeNatalAspect(a)
    if (!groups[cat]) groups[cat] = []
    groups[cat].push(a)
  }
  const groupedAspects = groupOrder
    .filter((label) => groups[label]?.length)
    .map((label) => ({ label, aspects: groups[label]! }))

  return (
    <div className="natal-asp">
      <div className="natal-asp__header">
        <span>Planet 1</span>
        <span className="natal-asp__header-center">Aspect</span>
        <span>Planet 2</span>
        <span style={{ textAlign: "right" }}>Orb</span>
        <span style={{ textAlign: "right" }}>Str</span>
      </div>
      {groupedAspects.map((group) => (
        <Fragment key={group.label}>
          <div className="natal-asp__group">{group.label}</div>
          {group.aspects.map((a, i) => {
            const strength = aspectStrength(a.orb)
            return (
              <div key={`${a.p1}-${a.p2}-${a.aspect}-${i}`} className="natal-asp__row">
                <span className="natal-asp__planet">
                  <span className="natal-pos__glyph">{OBJECT_GLYPHS[a.p1] ?? ""}</span>
                  <strong>{dn(a.p1)}</strong>
                </span>
                <span className="natal-asp__aspect">
                  <span className="natal-asp__glyph">{ASPECT_GLYPHS[a.aspect] ?? ""}</span>
                  <span className="natal-asp__aspect-name">{a.aspect}</span>
                </span>
                <span className="natal-asp__planet">
                  <span className="natal-pos__glyph">{OBJECT_GLYPHS[a.p2] ?? ""}</span>
                  <strong>{dn(a.p2)}</strong>
                </span>
                <span className="natal-asp__orb">{a.orb.toFixed(2)}°</span>
                <span className={`natal-asp__str natal-asp__str--${strength}`}>{strength.toUpperCase()}</span>
              </div>
            )
          })}
        </Fragment>
      ))}
    </div>
  )
}

function computeAge(birthDate: string): number | null {
  const d = new Date(birthDate)
  if (isNaN(d.getTime())) return null
  const now = new Date()
  let age = now.getFullYear() - d.getFullYear()
  const monthDiff = now.getMonth() - d.getMonth()
  if (monthDiff < 0 || (monthDiff === 0 && now.getDate() < d.getDate())) age--
  return age
}

export function ProfileSummaryCard({ detail }: { detail: ProfileDetailResponse }) {
  const positions = detail.chart.natal_positions ?? []
  const byId = new Map(positions.map((p) => [p.id, p]))
  const sun = byId.get("Sun")
  const moon = byId.get("Moon")
  const asc = byId.get("ASC")

  const birthInput = (detail.chart as Record<string, unknown>).birth_input as Record<string, unknown> | undefined
  const birthDate = (birthInput?.birth_date as string) ?? detail.chart.local_birth_datetime?.slice(0, 10) ?? null
  const birthTime = (birthInput?.birth_time as string) ?? null
  const timezone = (birthInput?.timezone as string) ?? null
  const localDt = (birthInput?.local_birth_datetime as string) ?? detail.chart.local_birth_datetime ?? null
  const locationName = (birthInput?.location_name as string) ?? detail.chart.location_name ?? null
  const age = birthDate ? computeAge(birthDate) : null

  const formatDate = (d: string) => {
    const parts = d.split("-")
    if (parts.length === 3) return `${parts[2]}.${parts[1]}.${parts[0]}`
    return d
  }

  // Extract GMT offset from ISO datetime like "1994-03-27T00:30:00+03:00"
  const gmtOffset = (() => {
    if (!localDt) return null
    const m = localDt.match(/([+-])(\d{2}):(\d{2})$/)
    if (!m) return null
    const sign = m[1]
    const hours = parseInt(m[2], 10)
    const mins = parseInt(m[3], 10)
    const label = mins > 0 ? `GMT${sign}${hours}:${String(mins).padStart(2, "0")}` : `GMT${sign}${hours}`
    return label.replace("+0", "+").replace("-0", "-").replace("GMT+", "UTC+").replace("GMT-", "UTC-")
  })()

  return (
    <div className="profile-summary">
      <div className="profile-summary__signs">
        {sun ? (
          <div className="profile-summary__sign-item">
            <span className="profile-summary__sign-icon">{SIGN_GLYPHS[sun.sign] ?? ""}</span>
            <div>
              <div className="profile-summary__sign-label">Sun</div>
              <div className="profile-summary__sign-value">{sun.sign}</div>
            </div>
          </div>
        ) : null}
        {moon ? (
          <div className="profile-summary__sign-item">
            <span className="profile-summary__sign-icon">{SIGN_GLYPHS[moon.sign] ?? ""}</span>
            <div>
              <div className="profile-summary__sign-label">Moon</div>
              <div className="profile-summary__sign-value">{moon.sign}</div>
            </div>
          </div>
        ) : null}
        {asc ? (
          <div className="profile-summary__sign-item">
            <span className="profile-summary__sign-icon">{SIGN_GLYPHS[asc.sign] ?? ""}</span>
            <div>
              <div className="profile-summary__sign-label">ASC</div>
              <div className="profile-summary__sign-value">{asc.sign}</div>
            </div>
          </div>
        ) : null}
        {age !== null ? (
          <div className="profile-summary__sign-item">
            <span className="profile-summary__sign-icon age-badge">{age}</span>
            <div>
              <div className="profile-summary__sign-label">Age</div>
              <div className="profile-summary__sign-value">y.o.</div>
            </div>
          </div>
        ) : null}
      </div>
      <div className="profile-summary__meta">
        {locationName ? <span>{locationName}</span> : null}
        <span>
          {birthDate ? formatDate(birthDate) : ""}
          {birthTime ? `, ${birthTime.slice(0, 5)}` : ""}
          {timezone ? ` (${timezone}` : ""}
          {gmtOffset ? `, ${gmtOffset}` : ""}
          {timezone || gmtOffset ? ")" : ""}
        </span>
      </div>
    </div>
  )
}

export function ProfileDetail({
  activeDetail,
  detailLoading,
  detailError,
  activeProfileId,
  transitReport,
  onEditClick,
}: ProfileDetailProps) {
  return (
    <>
      {!detailLoading && !detailError && activeDetail ? (
        <div className="profile-summary-row">
          <ProfileSummaryCard detail={activeDetail} />
          <button type="button" className="edit-btn" onClick={onEditClick}>Edit</button>
        </div>
      ) : null}

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
          <span>Choose a natal profile to view chart details.</span>
        </div>
      ) : null}

      {!detailLoading && !detailError && activeDetail?.chart.natal_positions?.length ? (
        <NatalPositionsTable positions={activeDetail.chart.natal_positions} />
      ) : null}

      {!detailLoading && !detailError && activeDetail?.chart.natal_aspects?.length ? (
        <NatalAspectsTable aspects={activeDetail.chart.natal_aspects} />
      ) : null}
    </>
  )
}
