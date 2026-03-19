import { createProfile } from "../api"
import { useLanguage } from "../contexts/LanguageContext"
import { ProfileForm, type ProfileFormValues } from "./ProfileForm"

type ProfileCreateFormProps = {
  onClose: () => void
  onCreated: (profileId: string) => void
}

export function ProfileCreateForm({ onClose, onCreated }: ProfileCreateFormProps) {
  const { t } = useLanguage()

  const initial: ProfileFormValues = {
    profileName: "", username: "", birthDate: "", birthTime: "",
    timezone: "", locationName: "", latitude: 0, longitude: 0,
  }

  async function handleSubmit(values: ProfileFormValues) {
    const result = await createProfile({
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
    onCreated(result.profile.profile_id)
  }

  return (
    <ProfileForm
      title={t("form.createNatal")}
      submitLabel={t("form.createProfile")}
      savingLabel={t("form.creating")}
      initial={initial}
      onClose={onClose}
      onSubmit={handleSubmit}
      requireTimezone
    />
  )
}
