import { useState } from "react"
import { useLanguage } from "../contexts/LanguageContext"
import { createProfileInvite } from "../api"

export function InviteModal({
  profileId,
  profileName,
  onClose,
}: {
  profileId: string
  profileName: string
  onClose: () => void
}) {
  const { t } = useLanguage()
  const [email, setEmail] = useState("")
  const [sending, setSending] = useState(false)
  const [sent, setSent] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email.trim()) return
    setSending(true)
    setError(null)
    try {
      await createProfileInvite(profileId, email.trim())
      setSent(true)
    } catch {
      setError(t("invite.sendError"))
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="modal-overlay" onClick={(e) => { if (e.target === e.currentTarget) onClose() }}>
      <div className="modal-content card invite-modal">
        <div className="modal-header modal-header--sticky">
          <h2>{t("invite.transferTitle")}</h2>
          <button className="modal-close-btn" onClick={onClose}>&times;</button>
        </div>

        {sent ? (
          <div className="invite-modal-body">
            <p className="invite-success">{t("invite.sent")}</p>
            <p className="invite-modal-hint">{email}</p>
            <button className="invite-btn" onClick={onClose}>OK</button>
          </div>
        ) : (
          <form className="invite-modal-body" onSubmit={handleSubmit}>
            <p className="invite-modal-desc">{t("invite.transferDesc")}</p>
            <p className="invite-modal-profile">
              <strong>{profileName}</strong>
            </p>
            <input
              type="email"
              className="invite-email-input"
              placeholder={t("invite.emailPlaceholder")}
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoFocus
            />
            {error && <p className="invite-error-msg">{error}</p>}
            <button
              type="submit"
              className="invite-btn invite-btn--primary"
              disabled={sending || !email.trim()}
            >
              {sending ? t("invite.sending") : t("invite.send")}
            </button>
          </form>
        )}
      </div>
    </div>
  )
}
