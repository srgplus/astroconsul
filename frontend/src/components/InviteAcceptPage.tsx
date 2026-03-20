import { useEffect, useState } from "react"
import { useAuth } from "../contexts/AuthContext"
import { useLanguage } from "../contexts/LanguageContext"
import { fetchInviteInfo, acceptInvite, type InviteInfo } from "../api"
import AuthScreen from "./AuthScreen"
import B3Logo from "./B3Logo"

export function InviteAcceptPage({ token }: { token: string }) {
  const { user, loading: authLoading } = useAuth()
  const { t } = useLanguage()
  const [invite, setInvite] = useState<InviteInfo | null>(null)
  const [loadError, setLoadError] = useState(false)
  const [accepting, setAccepting] = useState(false)
  const [accepted, setAccepted] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetchInviteInfo(token)
      .then(setInvite)
      .catch(() => setLoadError(true))
  }, [token])

  // After accepting, redirect to main app
  useEffect(() => {
    if (accepted) {
      const timer = setTimeout(() => {
        window.history.replaceState({}, "", "/")
        window.location.reload()
      }, 1500)
      return () => clearTimeout(timer)
    }
  }, [accepted])

  const handleAccept = async () => {
    setAccepting(true)
    setError(null)
    try {
      await acceptInvite(token)
      setAccepted(true)
    } catch {
      setError(t("invite.error"))
    } finally {
      setAccepting(false)
    }
  }

  const goToApp = () => {
    window.history.replaceState({}, "", "/")
    window.location.reload()
  }

  // Loading state
  if (!invite && !loadError) {
    return (
      <div className="invite-page">
        <div className="invite-card">
          <B3Logo />
          <p className="invite-loading">{t("invite.loading")}</p>
        </div>
      </div>
    )
  }

  // Not found / error
  if (loadError || !invite) {
    return (
      <div className="invite-page">
        <div className="invite-card">
          <B3Logo />
          <p className="invite-error-msg">{t("invite.notFound")}</p>
          <button className="invite-btn" onClick={goToApp}>{t("invite.backToApp")}</button>
        </div>
      </div>
    )
  }

  // Already accepted
  if (invite.status === "accepted") {
    return (
      <div className="invite-page">
        <div className="invite-card">
          <B3Logo />
          <p className="invite-status">{t("invite.accepted")}</p>
          <button className="invite-btn" onClick={goToApp}>{t("invite.backToApp")}</button>
        </div>
      </div>
    )
  }

  // Expired
  if (invite.status === "expired") {
    return (
      <div className="invite-page">
        <div className="invite-card">
          <B3Logo />
          <p className="invite-status">{t("invite.expired")}</p>
          <button className="invite-btn" onClick={goToApp}>{t("invite.backToApp")}</button>
        </div>
      </div>
    )
  }

  // Success
  if (accepted) {
    return (
      <div className="invite-page">
        <div className="invite-card">
          <B3Logo />
          <p className="invite-success">{t("invite.success")}</p>
        </div>
      </div>
    )
  }

  // Not logged in — show auth
  if (authLoading) {
    return (
      <div className="invite-page">
        <div className="invite-card">
          <B3Logo />
          <p className="invite-loading">{t("invite.loading")}</p>
        </div>
      </div>
    )
  }

  if (!user) {
    return (
      <div className="invite-page">
        <div className="invite-card">
          <B3Logo />
          <h2 className="invite-profile-name">{invite.profile_name}</h2>
          <p className="invite-from">
            <strong>{invite.invited_by_email}</strong> {t("invite.gifted")} <strong>"{invite.profile_name}"</strong>
          </p>
          <p className="invite-login-hint">{t("invite.loginToAccept")}</p>
        </div>
        <AuthScreen />
      </div>
    )
  }

  // Logged in — show accept button
  return (
    <div className="invite-page">
      <div className="invite-card">
        <B3Logo />
        <h2 className="invite-profile-name">{invite.profile_name}</h2>
        <p className="invite-from">
          <strong>{invite.invited_by_email}</strong> {t("invite.gifted")} <strong>"{invite.profile_name}"</strong>
        </p>
        {error && <p className="invite-error-msg">{error}</p>}
        <button
          className="invite-btn invite-btn--primary"
          onClick={handleAccept}
          disabled={accepting}
        >
          {accepting ? t("invite.accepting") : t("invite.accept")}
        </button>
      </div>
    </div>
  )
}
