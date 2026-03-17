import { useState } from "react"
import { updateProfile, resolveLocation, type PlaceCandidate } from "../api"
import { LocationAutocomplete } from "./LocationAutocomplete"
import type { ProfileDetailResponse } from "../types"
import { useLanguage } from "../contexts/LanguageContext"

type ProfileEditFormProps = {
  profileId: string
  activeDetail: ProfileDetailResponse
  onClose: () => void
  onSaved: () => void
}

export function ProfileEditForm({ profileId, activeDetail, onClose, onSaved }: ProfileEditFormProps) {
  const { t } = useLanguage()
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
  const birthInput = (chart as Record<string, unknown>).birth_input as Record<string, unknown> | undefined
  const [timezone, setTimezone] = useState(() => {
    return (birthInput?.timezone as string) || ""
  })
  const [locationName, setLocationName] = useState(() => {
    return (birthInput?.location_name as string) || chart.location_name || profile.location_name || ""
  })
  const [latitude, setLatitude] = useState(() => {
    return (birthInput?.latitude as number) || 0
  })
  const [longitude, setLongitude] = useState(() => {
    return (birthInput?.longitude as number) || 0
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
            <div className="eyebrow">{t("form.profile")}</div>
            <h2>{t("form.editProfile")}</h2>
          </div>
          <button type="button" className="edit-btn" onClick={onClose}>{t("form.close")}</button>
        </div>

        <form className="edit-form" onSubmit={handleSave}>
          <div className="edit-section">
            <h3>{t("form.profileBirth")}</h3>
            <p className="edit-section-desc">{t("form.editDesc")}</p>
            <div className="edit-form-grid">
              <div className="edit-form-field">
                <label>{t("form.profileName")}</label>
                <input type="text" value={profileName} onChange={(e) => setProfileName(e.target.value)} required />
              </div>
              <div className="edit-form-field">
                <label>{t("form.username")}</label>
                <input type="text" value={username} onChange={(e) => setUsername(e.target.value)} required />
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
                <label>{t("form.locationName")}</label>
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
            <div className="edit-resolve-row">
              <button type="button" className="resolve-btn" onClick={handleResolve} disabled={resolving || !locationName.trim()}>
                {resolving ? t("form.resolving") : t("form.resolve")}
              </button>
              <span className="edit-resolve-hint">{t("form.resolveHint")}</span>
            </div>
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
            {saving ? t("form.saving") : t("form.saveProfile")}
          </button>
        </form>
      </div>
    </div>
  )
}
