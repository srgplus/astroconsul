import { useState } from "react"
import { createProfile, type PlaceCandidate } from "../api"
import { LocationAutocomplete } from "./LocationAutocomplete"
import { useLanguage } from "../contexts/LanguageContext"

type ProfileCreateFormProps = {
  onClose: () => void
  onCreated: (profileId: string) => void
}

export function ProfileCreateForm({ onClose, onCreated }: ProfileCreateFormProps) {
  const { t } = useLanguage()
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
    if (!timezone) {
      setError(t("form.errorSelectLocation"))
      return
    }
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
            <div className="eyebrow">{t("form.newProfile")}</div>
            <h2>{t("form.createNatal")}</h2>
          </div>
          <button type="button" className="edit-btn" onClick={onClose}>{t("form.close")}</button>
        </div>

        <form className="edit-form" onSubmit={handleSave}>
          <div className="edit-section">
            <h3>{t("form.profileBirth")}</h3>
            <p className="edit-section-desc">{t("form.createDesc")}</p>
            <div className="edit-form-grid">
              <div className="edit-form-field">
                <label>{t("form.profileName")}</label>
                <input type="text" value={profileName} onChange={(e) => setProfileName(e.target.value)} placeholder={t("form.placeholderName")} required />
              </div>
              <div className="edit-form-field">
                <label>{t("form.username")}</label>
                <input type="text" value={username} onChange={(e) => setUsername(e.target.value)} placeholder={t("form.placeholderUsername")} required />
              </div>
              <div className="edit-form-field">
                <label>{t("form.birthDate")}</label>
                <input type="date" value={birthDate} onChange={(e) => setBirthDate(e.target.value)} required />
              </div>
              <div className="edit-form-field">
                <label>{t("form.birthTime")}</label>
                <input type="time" step="1" value={birthTime} onChange={(e) => setBirthTime(e.target.value)} required />
              </div>
              <div className="edit-form-field edit-form-field--full">
                <label>{t("form.birthLocation")}</label>
                <LocationAutocomplete
                  value={locationName}
                  onChange={setLocationName}
                  onSelect={(place: PlaceCandidate) => {
                    setLocationName(place.display_name)
                    setLatitude(place.latitude)
                    setLongitude(place.longitude)
                    if (place.timezone) setTimezone(place.timezone)
                  }}
                  placeholder={t("form.placeholderLocation")}
                />
              </div>
            </div>
          </div>

          <div className="edit-section">
            <h3>{t("form.coordinates")}</h3>
            <p className="edit-section-desc">{t("form.coordDesc")}</p>
            <div className="edit-form-grid">
              <div className="edit-form-field edit-form-field--full">
                <label>{t("form.timezone")}</label>
                <input type="text" value={timezone} readOnly placeholder={t("form.autoLocation")} />
              </div>
              <div className="edit-form-field">
                <label>{t("form.latitude")}</label>
                <input type="number" step="any" value={latitude} readOnly tabIndex={-1} />
              </div>
              <div className="edit-form-field">
                <label>{t("form.longitude")}</label>
                <input type="number" step="any" value={longitude} readOnly tabIndex={-1} />
              </div>
            </div>
          </div>

          {error ? <div className="edit-error">{error}</div> : null}

          <button type="submit" className="save-btn" disabled={saving}>
            {saving ? t("form.creating") : t("form.createProfile")}
          </button>
        </form>
      </div>
    </div>
  )
}
