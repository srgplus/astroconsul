import type { ProfileDetailResponse } from "../types"

function getInitials(name: string): string {
  const parts = name.trim().split(/\s+/)
  if (parts.length === 1) return parts[0].charAt(0).toUpperCase()
  return parts.map((w) => w.charAt(0).toUpperCase()).join("").slice(0, 2)
}

type Props = {
  activeDetail: ProfileDetailResponse | null
  partnerName: string | null
  partnerHandle: string | null
  partnerNatalSummary: Record<string, string> | null
  onPickPartner: () => void
  onClearPartner: () => void
  onOpenReport: () => void
  loading?: boolean
}

export default function SynastryWidget({
  activeDetail,
  partnerName,
  onPickPartner,
  onClearPartner,
  onOpenReport,
  loading,
}: Props) {
  if (!activeDetail) return null

  const hasPartner = !!partnerName

  return (
    <div className="widget widget--synastry">
      <div className="synastry-widget-title">Synastry</div>
      <div className="synastry-slots">
        {/* Person A — always the active profile */}
        <div className="synastry-slot synastry-slot--a">
          <div className="synastry-avatar synastry-avatar--a">
            <span className="synastry-avatar-letter">{getInitials(activeDetail.profile.profile_name)}</span>
          </div>
          <div className="synastry-slot-name">{activeDetail.profile.profile_name}</div>
        </div>

        <span className="synastry-x">&times;</span>

        {/* Person B — partner or placeholder */}
        {hasPartner ? (
          <div className="synastry-slot synastry-slot--b synastry-slot--filled">
            <button type="button" className="synastry-clear-btn" onClick={(e) => { e.stopPropagation(); onClearPartner() }} title="Remove partner">&times;</button>
            <button type="button" className="synastry-slot-inner" onClick={onPickPartner}>
              <div className="synastry-avatar synastry-avatar--b">
                <span className="synastry-avatar-letter">{partnerName ? getInitials(partnerName) : "B"}</span>
              </div>
              <div className="synastry-slot-name">{partnerName}</div>
            </button>
          </div>
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
          {loading ? <span className="cw-spinner" /> : "View Synastry"}
        </button>
      )}
    </div>
  )
}
