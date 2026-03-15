import type { ProfileSummary } from "../types"
import { zoneColor, FEELS_EMOJI } from "../tii-zones"

export type ProfileTiiData = {
  tii: number
  tension_ratio: number
  feels_like: string
  location: string
}

type ProfileListProps = {
  profiles: ProfileSummary[]
  activeProfileId: string | null
  onSelect: (id: string) => void
  tiiMap: Record<string, ProfileTiiData>
}

export function ProfileList({ profiles, activeProfileId, onSelect, tiiMap }: ProfileListProps) {
  if (!profiles.length) {
    return (
      <div className="empty-card">
        <strong>No profiles yet</strong>
        <span>Create a natal profile to get started.</span>
      </div>
    )
  }

  return (
    <div className="profile-list">
      {profiles.map((p) => {
        const tii = tiiMap[p.profile_id]
        const accent = tii ? zoneColor(tii.tii) : undefined
        const emoji = tii ? (FEELS_EMOJI[tii.feels_like] ?? "\u2728") : undefined
        // Show timezone name: "Europe/Moscow" → "Europe / Moscow"
        const tzLabel = tii?.location
          ? tii.location.replace(/\//g, " / ").replace(/_/g, " ")
          : ""

        return (
          <button
            key={p.profile_id}
            type="button"
            className={`profile-list-item ${p.profile_id === activeProfileId ? "active" : ""} ${tii ? "has-tii" : ""}`}
            onClick={() => onSelect(p.profile_id)}
          >
            {tii ? (
              <>
                <div className="pli-top">
                  <div className="pli-left">
                    <div className="pli-name">{p.profile_name}</div>
                    <div className="pli-location">{tzLabel}</div>
                  </div>
                  <div className="pli-tii" style={{ color: accent }}>{Math.round(tii.tii)}&deg;</div>
                </div>
                <div className="pli-bottom">
                  <span className="pli-feels" style={{ color: accent }}>{emoji} {tii.feels_like}</span>
                  <span className="pli-tension">T {Math.round(tii.tension_ratio * 100)}%</span>
                </div>
              </>
            ) : (
              <>
                <strong>{p.profile_name}</strong>
                <span>@{p.username}</span>
              </>
            )}
          </button>
        )
      })}
    </div>
  )
}
