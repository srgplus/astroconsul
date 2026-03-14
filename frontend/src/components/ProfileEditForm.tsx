import { useState } from "react"
import { updateProfile, resolveLocation } from "../api"
import type { ProfileDetailResponse } from "../types"

type ProfileEditFormProps = {
  profileId: string
  activeDetail: ProfileDetailResponse
  onClose: () => void
  onSaved: () => void
}

export function ProfileEditForm({ profileId, activeDetail, onClose, onSaved }: ProfileEditFormProps) {
  const profile = activeDetail.profile
  const chart = activeDetail.chart

  const [profileName, setProfileName] = useState(profile.profile_name)
  const [username, setUsername] = useState(profile.username)
  const [birthDate, setBirthDate] = useState(() => {
    const dt = chart.local_birth_datetime || profile.local_birth_datetime || ""
    const match = dt.match(/^(\d{4}-\d{2}-\d{2})/)
    return match ? match[1] : ""
  })
  const [birthTime, setBirthTime] = useState(() => {
    const dt = chart.local_birth_datetime || profile.local_birth_datetime || ""
    const match = dt.match(/T(\d{2}:\d{2}:\d{2})/)
    return match ? match[1] : ""
  })
  const [timezone, setTimezone] = useState(() => {
    return (chart as Record<string, unknown>).timezone as string || ""
  })
  const [locationName, setLocationName] = useState(chart.location_name || profile.location_name || "")
  const [latitude, setLatitude] = useState(() => {
    return (chart as Record<string, unknown>).latitude as number || 0
  })
  const [longitude, setLongitude] = useState(() => {
    return (chart as Record<string, unknown>).longitude as number || 0
  })

  const [saving, setSaving] = useState(false)
  const [resolving, setResolving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleResolve() {
    if (!locationName.trim()) return
    setResolving(true)
    setError(null)
    try {
      const loc = await resolveLocation(locationName.trim())
      setLatitude(loc.latitude)
      setLongitude(loc.longitude)
      setTimezone(loc.timezone)
      setLocationName(loc.resolved_name || loc.location_name)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to resolve location")
    } finally {
      setResolving(false)
    }
  }

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    setError(null)
    try {
      await updateProfile(profileId, {
        profile_name: profileName,
        username: username.replace(/^@/, ""),
        birth_date: birthDate,
        birth_time: birthTime,
        timezone: timezone || null,
        location_name: locationName || null,
        latitude,
        longitude,
        time_basis: "local",
      })
      onSaved()
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save profile")
      setSaving(false)
    }
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content card" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <div>
            <div className="eyebrow">Profile</div>
            <h2>Edit Profile</h2>
          </div>
          <button type="button" className="edit-btn" onClick={onClose}>Close</button>
        </div>

        <form className="edit-form" onSubmit={handleSave}>
          <div className="edit-section">
            <h3>Profile &amp; Birth Details</h3>
            <p className="edit-section-desc">Each natal profile stores a public handle plus the birth data used to build its natal chart.</p>
            <div className="edit-form-grid">
              <div className="edit-form-field">
                <label>Profile name</label>
                <input type="text" value={profileName} onChange={(e) => setProfileName(e.target.value)} required />
              </div>
              <div className="edit-form-field">
                <label>Username</label>
                <input type="text" value={username} onChange={(e) => setUsername(e.target.value)} required />
              </div>
              <div className="edit-form-field">
                <label>Birth date</label>
                <input type="date" value={birthDate} onChange={(e) => setBirthDate(e.target.value)} required />
              </div>
              <div className="edit-form-field">
                <label>Birth time</label>
                <input type="time" step="1" value={birthTime} onChange={(e) => setBirthTime(e.target.value)} required />
              </div>
              <div className="edit-form-field edit-form-field--full">
                <label>Timezone</label>
                <input type="text" value={timezone} onChange={(e) => setTimezone(e.target.value)} placeholder="e.g. Europe/Moscow" />
              </div>
              <div className="edit-form-field edit-form-field--full">
                <label>Location name</label>
                <input type="text" value={locationName} onChange={(e) => setLocationName(e.target.value)} placeholder="e.g. Moscow, Russia" />
              </div>
            </div>
          </div>

          <div className="edit-section">
            <h3>Natal Location Controls</h3>
            <p className="edit-section-desc">Resolve and fine-tune saved birth coordinates for the active natal profile.</p>
            <div className="edit-resolve-row">
              <button type="button" className="resolve-btn" onClick={handleResolve} disabled={resolving || !locationName.trim()}>
                {resolving ? "Resolving…" : "Resolve Natal Location"}
              </button>
              <span className="edit-resolve-hint">Timezone and coordinates will autofill from the natal place name.</span>
            </div>
            <div className="edit-form-grid">
              <div className="edit-form-field">
                <label>Latitude</label>
                <input type="number" step="any" value={latitude} onChange={(e) => setLatitude(Number(e.target.value))} required />
              </div>
              <div className="edit-form-field">
                <label>Longitude</label>
                <input type="number" step="any" value={longitude} onChange={(e) => setLongitude(Number(e.target.value))} required />
              </div>
            </div>
          </div>

          {error ? <div className="edit-error">{error}</div> : null}

          <button type="submit" className="save-btn" disabled={saving}>
            {saving ? "Saving…" : "Save Natal Profile"}
          </button>
        </form>
      </div>
    </div>
  )
}
