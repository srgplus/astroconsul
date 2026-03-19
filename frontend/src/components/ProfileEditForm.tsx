import { updateProfile } from "../api"
import { useLanguage } from "../contexts/LanguageContext"
import { ProfileForm, type ProfileFormValues } from "./ProfileForm"
import type { ProfileDetailResponse } from "../types"

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
  const birthInput = (chart as Record<string, unknown>).birth_input as Record<string, unknown> | undefined

  const dt = chart.local_birth_datetime || profile.local_birth_datetime || ""
  const dateMatch = dt.match(/^(\d{4}-\d{2}-\d{2})/)
  const timeMatch = dt.match(/T(\d{2}:\d{2}:\d{2})/)

  const initial: ProfileFormValues = {
    profileName: profile.profile_name,
    username: profile.username,
    birthDate: dateMatch ? dateMatch[1] : "",
    birthTime: timeMatch ? timeMatch[1] : "",
    timezone: (birthInput?.timezone as string) || "",
    locationName: (birthInput?.location_name as string) || chart.location_name || profile.location_name || "",
    latitude: (birthInput?.latitude as number) || 0,
    longitude: (birthInput?.longitude as number) || 0,
  }

  async function handleSubmit(values: ProfileFormValues) {
    await updateProfile(profileId, {
      profile_name: values.profileName,
      username: values.username,
      birth_date: values.birthDate,
      birth_time: values.birthTime,
      timezone: values.timezone || null,
      location_name: values.locationName || null,
      latitude: values.latitude,
      longitude: values.longitude,
      time_basis: "local",
    })
    onSaved()
  }

  return (
    <ProfileForm
      title={t("form.editProfile")}
      submitLabel={t("form.saveProfile")}
      savingLabel={t("form.saving")}
      initial={initial}
      onClose={onClose}
      onSubmit={handleSubmit}
    />
  )
}
