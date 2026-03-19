import { useState, useEffect } from "react"
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
  const [coordsOpen, setCoordsOpen] = useState(false)

  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Lock body scroll while modal is open
  useEffect(() => {
    document.body.style.overflow = "hidden"
    return () => { document.body.style.overflow = "" }
  }, [])

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
        <div className="modal-header modal-header--sticky">
          <h2>{t("form.createNatal")}</h2>
          <button type="button" className="edit-btn" onClick={onClose}>{t("form.close")}</button>
        </div>

        <form className="edit-form" onSubmit={handleSave}>
          <div className="edit-form-grid">
            <div className="edit-form-field edit-form-field--full">
              <label>{t("form.profileName")}</label>
              <input type="text" value={profileName} onChange={(e) => setProfileName(e.target.value)} placeholder={t("form.placeholderName")} required />
            </div>
            <div className="edit-form-field edit-form-field--full">
              <label>{t("form.username")}</label>
              <input type="text" value={username} onChange={(e) => setUsername(e.target.value)} placeholder={t("form.placeholderUsername")} required />
            </div>
            <div className="edit-form-field edit-form-field--full">
              <label>{t("form.birthDate")}</label>
              <input
                type="date"
                value={birthDate}
                onChange={(e) => setBirthDate(e.target.value)}
                placeholder={t("form.placeholderDate")}
                required
              />
            </div>
            <div className="edit-form-field edit-form-field--full">
              <label>{t("form.birthTime")}</label>
              <input
                type="time"
                value={birthTime}
                onChange={(e) => setBirthTime(e.target.value)}
                step="1"
                placeholder={t("form.placeholderTime")}
                required
              />
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

          <div className="edit-section">
            <button type="button" className="edit-section-toggle" onClick={() => setCoordsOpen(!coordsOpen)}>
              <h3>{t("form.coordsAndTz")}</h3>
              <span className={`edit-section-chevron ${coordsOpen ? "open" : ""}`} />
            </button>
            {coordsOpen && (
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
            )}
          </div>

          {error ? <div className="edit-error">{error}</div> : null}

          <div className="modal-sticky-footer">
            <button type="submit" className="save-btn" disabled={saving}>
              {saving ? t("form.creating") : t("form.createProfile")}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
