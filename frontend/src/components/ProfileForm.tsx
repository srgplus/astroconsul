import { useState, useEffect } from "react"
import { type PlaceCandidate } from "../api"
import { LocationAutocomplete } from "./LocationAutocomplete"
import { useLanguage } from "../contexts/LanguageContext"

export type ProfileFormValues = {
  profileName: string
  username: string
  birthDate: string
  birthTime: string
  timezone: string
  locationName: string
  latitude: number
  longitude: number
}

type ProfileFormProps = {
  title: string
  submitLabel: string
  savingLabel: string
  initial: ProfileFormValues
  onClose: () => void
  onSubmit: (values: ProfileFormValues) => Promise<void>
  requireTimezone?: boolean
}

export function ProfileForm({ title, submitLabel, savingLabel, initial, onClose, onSubmit, requireTimezone = false }: ProfileFormProps) {
  const { t } = useLanguage()
  const [profileName, setProfileName] = useState(initial.profileName)
  const [username, setUsername] = useState(initial.username)
  const [birthDate, setBirthDate] = useState(initial.birthDate)
  const [birthTime, setBirthTime] = useState(initial.birthTime)
  const [timezone, setTimezone] = useState(initial.timezone)
  const [locationName, setLocationName] = useState(initial.locationName)
  const [latitude, setLatitude] = useState(initial.latitude)
  const [longitude, setLongitude] = useState(initial.longitude)
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
    if (requireTimezone && !timezone) {
      setError(t("form.errorSelectLocation"))
      return
    }
    setSaving(true)
    setError(null)
    try {
      await onSubmit({
        profileName,
        username: username.replace(/^@/, ""),
        birthDate,
        birthTime,
        timezone,
        locationName,
        latitude,
        longitude,
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong")
      setSaving(false)
    }
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content card" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header modal-header--sticky">
          <h2>{title}</h2>
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
              <div className="date-input-wrap" data-placeholder={!birthDate ? t("form.placeholderDate") : undefined}>
                <input
                  type="date"
                  value={birthDate}
                  onChange={(e) => setBirthDate(e.target.value)}
                  onFocus={(e) => { try { (e.target as any).showPicker() } catch {} }}
                  className={birthDate ? "" : "date-input--empty"}
                  required
                />
              </div>
            </div>
            <div className="edit-form-field edit-form-field--full">
              <label>{t("form.birthTime")}</label>
              <div className="date-input-wrap" data-placeholder={!birthTime ? t("form.placeholderTime") : undefined}>
                <input
                  type="time"
                  value={birthTime}
                  onChange={(e) => setBirthTime(e.target.value)}
                  onFocus={(e) => { try { (e.target as any).showPicker() } catch {} }}
                  step="1"
                  className={birthTime ? "" : "date-input--empty"}
                  required
                />
              </div>
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
              {saving ? savingLabel : submitLabel}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
