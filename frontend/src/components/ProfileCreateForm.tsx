import { useState } from "react"
import { createProfile, type PlaceCandidate } from "../api"
import { LocationAutocomplete } from "./LocationAutocomplete"

type ProfileCreateFormProps = {
  onClose: () => void
  onCreated: (profileId: string) => void
}

export function ProfileCreateForm({ onClose, onCreated }: ProfileCreateFormProps) {
  const [profileName, setProfileName] = useState("")
  const [username, setUsername] = useState("")
  const [birthDate, setBirthDate] = useState("")
  const [birthTime, setBirthTime] = useState("")
  const [timezone, setTimezone] = useState("")
  const [locationName, setLocationName] = useState("")
  const [latitude, setLatitude] = useState(0)
  const [longitude, setLongitude] = useState(0)

  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    setError(null)
    try {
      const result = await createProfile({
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
      onCreated(result.profile.profile_id)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create profile")
      setSaving(false)
    }
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content card" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <div>
            <div className="eyebrow">New Profile</div>
            <h2>Create Natal Profile</h2>
          </div>
          <button type="button" className="edit-btn" onClick={onClose}>Close</button>
        </div>

        <form className="edit-form" onSubmit={handleSave}>
          <div className="edit-section">
            <h3>Profile &amp; Birth Details</h3>
            <p className="edit-section-desc">Enter the birth data to generate a natal chart.</p>
            <div className="edit-form-grid">
              <div className="edit-form-field">
                <label>Profile name</label>
                <input type="text" value={profileName} onChange={(e) => setProfileName(e.target.value)} placeholder="e.g. John" required />
              </div>
              <div className="edit-form-field">
                <label>Username</label>
                <input type="text" value={username} onChange={(e) => setUsername(e.target.value)} placeholder="e.g. johndoe" required />
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
                <input type="text" value={timezone} readOnly placeholder="Auto-filled from location" />
              </div>
              <div className="edit-form-field edit-form-field--full">
                <label>Birth location</label>
                <LocationAutocomplete
                  value={locationName}
                  onChange={setLocationName}
                  onSelect={(place: PlaceCandidate) => {
                    setLocationName(place.display_name)
                    setLatitude(place.latitude)
                    setLongitude(place.longitude)
                    if (place.timezone) setTimezone(place.timezone)
                  }}
                  placeholder="e.g. Moscow, Russia"
                />
              </div>
            </div>
          </div>

          <div className="edit-section">
            <h3>Coordinates</h3>
            <p className="edit-section-desc">Auto-filled from location. Fine-tune if needed.</p>
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
            {saving ? "Creating..." : "Create Profile"}
          </button>
        </form>
      </div>
    </div>
  )
}
