import { useEffect, useState } from "react"
import { useAuth } from "../contexts/AuthContext"
import { useLanguage } from "../contexts/LanguageContext"
import { fetchInviteInfo, acceptInvite, setPrimaryProfile, type InviteInfo } from "../api"
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
  // The profile just received, while the page asks whether it is the
  // recipient's own chart. Asked only when they have none: most gifts are
  // their subject's, but a parent can be handed a child's.
  const [askingOwn, setAskingOwn] = useState<string | null>(null)
  const [savingOwn, setSavingOwn] = useState(false)
  const [ownError, setOwnError] = useState<string | null>(null)

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
      const result = await acceptInvite(token)
      // Null, not missing: a server that predates the question says nothing,
      // and the page then goes straight on as it always did.
      if (result.primary_profile_id === null) {
        setAskingOwn(result.profile_id)
      } else {
        setAccepted(true)
      }
    } catch (err) {
      console.error("Failed to accept invite:", err)
      setError(t("invite.error"))
    } finally {
      setAccepting(false)
    }
  }

  const answerOwn = async (isMine: boolean) => {
    if (!askingOwn) return
    // "Someone else's" leaves the account without a chart of its own, and
    // the app asks again, listing every chart the account owns.
    if (!isMine) {
      setAccepted(true)
      return
    }
    setSavingOwn(true)
    setOwnError(null)
    try {
      await setPrimaryProfile(askingOwn)
      setAccepted(true)
    } catch (err) {
      console.error("Failed to save primary profile:", err)
      setOwnError(t("invite.ownError"))
    } finally {
      setSavingOwn(false)
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

  // Accepted, and the account has no chart of its own yet
  if (askingOwn) {
    return (
      <div className="invite-page">
        <div className="invite-card">
          <B3Logo />
          <h2 className="invite-profile-name">{invite.profile_name}</h2>
          <p className="invite-question">{t("invite.isYours")}</p>
          <p className="invite-login-hint">{t("invite.isYoursHint")}</p>
          {ownError && <p className="invite-error-msg">{ownError}</p>}
          <div className="invite-actions">
            <button
              className="invite-btn invite-btn--primary"
              onClick={() => answerOwn(true)}
              disabled={savingOwn}
            >
              {savingOwn ? t("invite.savingOwn") : t("invite.itsMe")}
            </button>
            <button className="invite-btn" onClick={() => answerOwn(false)} disabled={savingOwn}>
              {t("invite.notMe")}
            </button>
          </div>
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
