import type { ProfileSummary } from "../types"

type ProfileListProps = {
  profiles: ProfileSummary[]
  activeProfileId: string | null
  onSelect: (id: string) => void
}

export function ProfileList({ profiles, activeProfileId, onSelect }: ProfileListProps) {
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
      {profiles.map((p) => (
        <button
          key={p.profile_id}
          type="button"
          className={`profile-list-item ${p.profile_id === activeProfileId ? "active" : ""}`}
          onClick={() => onSelect(p.profile_id)}
        >
          <strong>{p.profile_name}</strong>
          <span>@{p.username}</span>
          {p.location_name ? <span>{p.location_name}</span> : null}
        </button>
      ))}
    </div>
  )
}
