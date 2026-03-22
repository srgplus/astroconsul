import type { ProfileDetailResponse } from "../types"

const SIGN_GLYPHS: Record<string, string> = {
  Aries: "\u2648", Taurus: "\u2649", Gemini: "\u264A", Cancer: "\u264B",
  Leo: "\u264C", Virgo: "\u264D", Libra: "\u264E", Scorpio: "\u264F",
  Sagittarius: "\u2650", Capricorn: "\u2651", Aquarius: "\u2652", Pisces: "\u2653",
}

type Props = {
  activeDetail: ProfileDetailResponse | null
  partnerName: string | null
  partnerHandle: string | null
  partnerNatalSummary: Record<string, string> | null
  onPickPartner: () => void
  onOpenReport: () => void
  loading?: boolean
}

function Big3Badges({ summary }: { summary: Record<string, string> | null }) {
  if (!summary) return null
  const sun = summary.Sun || summary.sun
  const moon = summary.Moon || summary.moon
  const asc = summary.Ascendant || summary.ascendant || summary.ASC
  return (
    <div className="synastry-big3">
      {sun ? <span className="synastry-sign-badge">{SIGN_GLYPHS[sun] || ""}</span> : null}
      {moon ? <span className="synastry-sign-badge">{SIGN_GLYPHS[moon] || ""}</span> : null}
      {asc ? <span className="synastry-sign-badge">{SIGN_GLYPHS[asc] || ""}</span> : null}
    </div>
  )
}

export default function SynastryWidget({
  activeDetail,
  partnerName,
  partnerHandle,
  partnerNatalSummary,
  onPickPartner,
  onOpenReport,
  loading,
}: Props) {
  if (!activeDetail) return null

  const chart = activeDetail.chart
  const natalSummary = (chart as Record<string, unknown>).natal_summary as Record<string, string> | null

  const hasPartner = !!partnerName

  return (
    <div className="widget widget--synastry">
      <div className="synastry-widget-title">Synastry</div>
      <div className="synastry-slots">
        {/* Person A — always the active profile */}
        <div className="synastry-slot synastry-slot--a">
          <div className="synastry-avatar synastry-avatar--a">
            <span className="synastry-avatar-letter">A</span>
          </div>
          <div className="synastry-slot-name">{activeDetail.profile.profile_name}</div>
          <Big3Badges summary={natalSummary} />
        </div>

        <span className="synastry-x">&times;</span>

        {/* Person B — partner or placeholder */}
        {hasPartner ? (
          <button type="button" className="synastry-slot synastry-slot--b synastry-slot--filled" onClick={onPickPartner}>
            <div className="synastry-avatar synastry-avatar--b">
              <span className="synastry-avatar-letter">B</span>
            </div>
            <div className="synastry-slot-name">{partnerName}</div>
            <Big3Badges summary={partnerNatalSummary} />
          </button>
        ) : (
          <button type="button" className="synastry-slot synastry-slot--b synastry-slot--empty" onClick={onPickPartner}>
            <div className="synastry-avatar synastry-avatar--plus">
              <span>+</span>
            </div>
            <div className="synastry-slot-name synastry-slot-name--hint">Choose</div>
          </button>
        )}
      </div>

      {hasPartner && (
        <button
          type="button"
          className="synastry-go-btn"
          onClick={onOpenReport}
          disabled={loading}
        >
          {loading ? <span className="spinner" /> : "View Synastry"}
        </button>
      )}
    </div>
  )
}
