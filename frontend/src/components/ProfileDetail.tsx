import { Fragment } from "react"
import { NatalZodiacRing } from "./NatalZodiacRing"
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

function formatPosition(p: NatalPosition): string {
  return `${p.sign} ${p.degree}\u00B0${String(p.minute).padStart(2, "0")}'${String(Math.round(p.second)).padStart(2, "0")}"`
}

function retroLabel(r: boolean | null): string {
  if (r === true) return "Yes"
  if (r === false) return "No"
  return "\u2014"
}

function NatalPositionsTable({ positions }: { positions: NatalPosition[] }) {
  const byId = new Map(positions.map((p) => [p.id, p]))

  return (
    <div className="natal-positions-card">
      <div className="eyebrow">Natal Positions</div>
      <table className="natal-positions-table">
        <thead>
          <tr>
            <th>Object</th>
            <th>Position</th>
            <th>House</th>
            <th>Retrograde</th>
          </tr>
        </thead>
        <tbody>
          {GROUPS.map((group) => {
            const rows = group.ids.map((id) => byId.get(id)).filter(Boolean) as NatalPosition[]
            if (!rows.length) return null
            return (
              <Fragment key={group.label}>
                <tr className="natal-positions-group">
                  <td colSpan={4}>{group.label}</td>
                </tr>
                {rows.map((p) => (
                  <tr key={p.id}>
                    <td className="natal-obj-cell">
                      <span className="natal-obj-glyph">{OBJECT_GLYPHS[p.id] ?? ""}</span>
                      <strong>{p.id}</strong>
                    </td>
                    <td>
                      <span className="natal-sign-glyph">{SIGN_GLYPHS[p.sign] ?? ""}</span>
                      {" "}{formatPosition(p)}
                    </td>
                    <td>{p.house}</td>
                    <td>{retroLabel(p.retrograde)}</td>
                  </tr>
                ))}
              </Fragment>
            )
          })}
        </tbody>
      </table>
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

function NatalAspectsTable({ aspects }: { aspects: NatalAspect[] }) {
  const sorted = [...aspects].sort((a, b) => a.orb - b.orb)

  return (
    <div className="natal-positions-card">
      <div className="eyebrow">Natal Aspects</div>
      <table className="natal-positions-table natal-aspects-table">
        <thead>
          <tr>
            <th>Planet 1</th>
            <th>Aspect</th>
            <th>Planet 2</th>
            <th>Orb</th>
            <th>Strength</th>
          </tr>
        </thead>
        <tbody>
          {sorted.map((a, i) => {
            const strength = aspectStrength(a.orb)
            return (
              <tr key={`${a.p1}-${a.p2}-${a.aspect}-${i}`}>
                <td className="natal-obj-cell">
                  <span className="natal-obj-glyph">{OBJECT_GLYPHS[a.p1] ?? ""}</span>
                  <strong>{a.p1}</strong>
                </td>
                <td className="natal-aspect-cell">
                  <span className="natal-aspect-glyph">{ASPECT_GLYPHS[a.aspect] ?? ""}</span>
                  {" "}{a.aspect}
                </td>
                <td className="natal-obj-cell">
                  <span className="natal-obj-glyph">{OBJECT_GLYPHS[a.p2] ?? ""}</span>
                  <strong>{a.p2}</strong>
                </td>
                <td>{a.orb.toFixed(2)}°</td>
                <td>
                  <span className={`strength-badge strength-badge--${strength}`}>{strength}</span>
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
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
  const activeAsc = coerceNumber(activeDetail?.chart.asc)
  const activeMc = coerceNumber(activeDetail?.chart.mc)

  return (
    <>
      <div className="card-head">
        <div className="detail-header">
          <div>
            <div className="eyebrow">Profile View</div>
            <h2>{activeDetail?.profile.profile_name || "Select a profile"}</h2>
            {activeDetail ? (
              <p>@{activeDetail.profile.username}</p>
            ) : null}
          </div>
          {activeDetail ? (
            <button type="button" className="edit-btn" onClick={onEditClick}>
              Edit
            </button>
          ) : null}
        </div>
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
            planets={(activeDetail?.chart.natal_positions ?? [])
              .filter((p) => Number.isFinite(p.longitude))
              .map((p) => ({
                id: p.id,
                longitude: p.longitude,
                glyph: OBJECT_GLYPHS[p.id] ?? p.id.slice(0, 2),
              }))}
            transitPlanets={(transitReport?.transit_positions ?? [])
              .filter((p) => Number.isFinite(p.longitude))
              .map((p) => ({
                id: p.id,
                longitude: p.longitude,
                glyph: OBJECT_GLYPHS[p.id] ?? p.id.slice(0, 2),
              }))}
            transitAspects={(transitReport?.active_aspects ?? [])
              .filter((a) => a.is_within_orb)
              .map((a) => ({
                transit_object: a.transit_object,
                natal_object: a.natal_object,
                aspect: a.aspect,
                orb: a.orb,
                strength: a.strength,
              }))}
            size={520}
            theme="light"
          />
        </div>
      ) : null}

      {!detailLoading && !detailError && activeProfileId ? (
        <div className="ring-legend">
          <div className="eyebrow">Ring Legend</div>
          <div className="ring-legend__grid">
            <div className="ring-legend__section">
              <div className="ring-legend__title">Rings (outer → inner)</div>
              <div className="ring-legend__item"><span className="ring-legend__swatch ring-legend__swatch--zodiac" />Zodiac signs</div>
              <div className="ring-legend__item"><span className="ring-legend__swatch ring-legend__swatch--house-num" />House numbers</div>
              <div className="ring-legend__item"><span className="ring-legend__swatch ring-legend__swatch--natal" />Natal planets</div>
              <div className="ring-legend__item"><span className="ring-legend__swatch ring-legend__swatch--natal-sp" />Natal special points</div>
              <div className="ring-legend__item"><span className="ring-legend__swatch ring-legend__swatch--transit" />Transit planets</div>
              <div className="ring-legend__item"><span className="ring-legend__swatch ring-legend__swatch--transit-sp" />Transit special points</div>
              <div className="ring-legend__item"><span className="ring-legend__swatch ring-legend__swatch--center" />Aspect lines (center)</div>
            </div>
            <div className="ring-legend__section">
              <div className="ring-legend__title">Lines</div>
              <div className="ring-legend__item"><span className="ring-legend__line ring-legend__line--axis" />AC/DC/MC/IC axes</div>
              <div className="ring-legend__item"><span className="ring-legend__line ring-legend__line--house-div" />House dividers</div>
              <div className="ring-legend__item"><span className="ring-legend__line ring-legend__line--tick" />Planet position tick</div>
            </div>
            <div className="ring-legend__section">
              <div className="ring-legend__title">Aspect colors</div>
              <div className="ring-legend__item"><span className="ring-legend__line ring-legend__line--conjunction" />Conjunction (solid)</div>
              <div className="ring-legend__item"><span className="ring-legend__line ring-legend__line--opposition" />Opposition (dashed)</div>
              <div className="ring-legend__item"><span className="ring-legend__line ring-legend__line--square" />Square (short dash)</div>
              <div className="ring-legend__item"><span className="ring-legend__line ring-legend__line--trine" />Trine (long dash)</div>
              <div className="ring-legend__item"><span className="ring-legend__line ring-legend__line--sextile" />Sextile (dots)</div>
            </div>
          </div>
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
