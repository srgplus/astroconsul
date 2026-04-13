import { useState } from "react"
import type { ProfileSummary, TransitReportResponse } from "../types"
import { useLanguage, type Lang } from "../contexts/LanguageContext"
import { deleteAccount, getAuthHeaders } from "../api"

const isNativeApp = (): boolean =>
  typeof window !== "undefined" && !!(window as any).Capacitor?.isNativePlatform?.()

type Theme = "light" | "dark" | "system"

type SettingsModalProps = {
  open: boolean
  onClose: () => void
  email: string | null
  theme: Theme
  onThemeChange: (t: Theme) => void
  onSignOut: () => void
  onResetCache: () => void
  transitReport: TransitReportResponse | null
  profiles: ProfileSummary[]
  primaryProfileId: string | null
  onPrimaryChange: (id: string) => void
  isPro?: boolean
  plan?: string
  expiresAt?: string | null
}

type SettingsPage = "account" | "appearance" | "system" | "about"

const PAGE_KEYS: Record<SettingsPage, string> = {
  account: "settings.account",
  appearance: "settings.appearance",
  system: "settings.system",
  about: "settings.about",
}

const LANG_OPTIONS: { id: Lang; label: string }[] = [
  { id: "en", label: "English" },
  { id: "ru", label: "Русский" },
]

export function SettingsModal({
  open,
  onClose,
  email,
  theme,
  onThemeChange,
  onSignOut,
  onResetCache,
  transitReport,
  profiles,
  primaryProfileId,
  onPrimaryChange,
  isPro = false,
  plan = "free",
  expiresAt = null,
}: SettingsModalProps) {
  const [page, setPage] = useState<SettingsPage>("account")
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  const { t, lang, setLang } = useLanguage()

  const handleDeleteAccount = async () => {
    setDeleteError(null)
    setDeleting(true)
    try {
      await deleteAccount()
      // Sign out locally to drop the now-invalid session, then reload.
      onSignOut()
      window.location.href = "/"
    } catch (err) {
      console.error("[Settings] delete account error:", err)
      setDeleteError(t("settings.deleteAccountError"))
      setDeleting(false)
    }
  }

  if (!open) return null

  const snapshot = transitReport?.snapshot
  const houseSystem = snapshot?.house_system ?? "Placidus"
  const ephemeris = snapshot?.ephemeris_version ?? "Swiss Ephemeris"
  const primaryProfile = profiles.find((p) => p.profile_id === primaryProfileId)

  const NAV_ITEMS: { id: SettingsPage; label: string }[] = [
    { id: "account", label: t("settings.account") },
    { id: "appearance", label: t("settings.appearance") },
    { id: "system", label: t("settings.system") },
    { id: "about", label: t("settings.about") },
  ]

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="stg" onClick={(e) => e.stopPropagation()}>
        {/* Sidebar nav */}
        <div className="stg-nav">
          <div className="stg-nav-list">
            {NAV_ITEMS.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`stg-nav-item${page === item.id ? " stg-nav-item--active" : ""}`}
                onClick={() => setPage(item.id)}
              >
                {item.label}
              </button>
            ))}
          </div>
          <div className="stg-nav-footer">
            <button type="button" className="stg-signout-btn" onClick={onSignOut}>
              {t("settings.signOut")}
            </button>
          </div>
        </div>

        {/* Content area */}
        <div className="stg-content">
          <div className="stg-content-header">
            <h2>{NAV_ITEMS.find((n) => n.id === page)?.label}</h2>
            <button type="button" className="stg-close" onClick={onClose}>✕</button>
          </div>

          <div className="stg-content-body">
            {page === "account" && (
              <>
                <div className="stg-card">
                  <div className="stg-card-title">{t("settings.profile")}</div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.email")}</span>
                    <span className="stg-val">{email ?? "—"}</span>
                  </div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.natalProfiles")}</span>
                    <span className="stg-val">{profiles.length}</span>
                  </div>
                </div>
                <div className="stg-card">
                  <div className="stg-card-title">{t("settings.primaryProfile")}</div>
                  <p className="stg-card-desc">{t("settings.primaryProfileDesc")}</p>
                  <div className="stg-select-wrap">
                    <select
                      className="stg-select"
                      value={primaryProfileId ?? ""}
                      onChange={(e) => onPrimaryChange(e.target.value)}
                    >
                      {profiles.map((p) => (
                        <option key={p.profile_id} value={p.profile_id}>
                          {p.profile_name} — @{p.username}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>
                <div className="stg-card">
                  <div className="stg-card-title">{t("settings.subscription")}</div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.plan")}</span>
                    <span className={`stg-val stg-val--badge${isPro ? " stg-val--pro" : ""}`}>
                      {isPro ? "Pro" : t("settings.freeBeta")}
                    </span>
                  </div>
                  {isPro && expiresAt ? (
                    <div className="stg-row">
                      <span className="stg-label">{lang === "ru" ? "Действует до" : "Valid until"}</span>
                      <span className="stg-val">{new Date(expiresAt).toLocaleDateString(lang === "ru" ? "ru-RU" : "en-US", { year: "numeric", month: "long", day: "numeric" })}</span>
                    </div>
                  ) : null}
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.transitReports")}</span>
                    <span className="stg-val">{t("settings.unlimited")}</span>
                  </div>
                  {isPro && !isNativeApp() ? (
                    <button
                      type="button"
                      className="stg-portal-link"
                      onClick={async () => {
                        try {
                          const auth = await getAuthHeaders()
                          const res = await fetch("/api/v1/payments/customer-portal", {
                            method: "POST",
                            headers: auth,
                          })
                          if (res.ok) {
                            const data = await res.json()
                            if (data.portal_url) window.location.href = data.portal_url
                          }
                        } catch (err) {
                          console.error("[Portal] error:", err)
                        }
                      }}
                    >
                      {lang === "ru" ? "Управление подпиской" : "Manage subscription"}
                    </button>
                  ) : isPro && isNativeApp() ? (
                    <p className="stg-card-desc" style={{ marginTop: 12, fontSize: "0.82rem" }}>
                      {lang === "ru"
                        ? "Подписка управляется через сайт, где она была оформлена."
                        : "Subscription is managed from the website where it was purchased."}
                    </p>
                  ) : null}
                </div>
                <div className="stg-card stg-card--danger">
                  <div className="stg-card-title">{t("settings.deleteAccount")}</div>
                  <p className="stg-card-desc">{t("settings.deleteAccountDesc")}</p>
                  <button
                    type="button"
                    className="stg-delete-btn"
                    onClick={() => setConfirmDelete(true)}
                  >
                    {t("settings.deleteAccount")}
                  </button>
                </div>
                <div className="stg-mobile-signout">
                  <button type="button" className="stg-signout-btn" onClick={onSignOut}>
                    {t("settings.signOut")}
                  </button>
                </div>
              </>
            )}

            {page === "appearance" && (
              <>
                <div className="stg-card">
                  <div className="stg-card-title">{t("settings.theme")}</div>
                  <div className="stg-theme-grid">
                    {(["light", "dark", "system"] as Theme[]).map((th) => (
                      <button
                        key={th}
                        type="button"
                        className={`stg-theme-card${theme === th ? " stg-theme-card--active" : ""}`}
                        onClick={() => onThemeChange(th)}
                      >
                        <div className={`stg-theme-preview stg-theme-preview--${th}`}>
                          <div className="stg-theme-preview-bar" />
                          <div className="stg-theme-preview-content">
                            <div className="stg-theme-preview-line" />
                            <div className="stg-theme-preview-line short" />
                          </div>
                        </div>
                        <span className="stg-theme-name">
                          {th === "light" ? t("settings.themeLight") : th === "dark" ? t("settings.themeDark") : t("settings.themeSystem")}
                        </span>
                      </button>
                    ))}
                  </div>
                </div>
                <div className="stg-card">
                  <div className="stg-card-title">{t("settings.language")}</div>
                  <div className="stg-select-wrap">
                    <select
                      className="stg-select"
                      value={lang}
                      onChange={(e) => setLang(e.target.value as Lang)}
                    >
                      {LANG_OPTIONS.map((opt) => (
                        <option key={opt.id} value={opt.id}>{opt.label}</option>
                      ))}
                    </select>
                  </div>
                </div>
              </>
            )}

            {page === "system" && (
              <>
                <div className="stg-card">
                  <div className="stg-card-title">{t("settings.cache")}</div>
                  <p className="stg-card-desc">{t("settings.cacheDesc")}</p>
                  <button type="button" className="stg-signout-btn" onClick={onResetCache}>
                    {t("settings.resetCache")}
                  </button>
                </div>
                <div className="stg-card">
                  <div className="stg-card-title">{t("settings.calcEngine")}</div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.ephemeris")}</span>
                    <span className="stg-val">{ephemeris}</span>
                  </div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.houseSystem")}</span>
                    <span className="stg-val">{houseSystem}</span>
                  </div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.zodiac")}</span>
                    <span className="stg-val">{t("settings.tropical")}</span>
                  </div>
                </div>
                <div className="stg-card">
                  <div className="stg-card-title">{t("settings.transitSettings")}</div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.orbLimit")}</span>
                    <span className="stg-val">{t("settings.orbLimitVal")}</span>
                  </div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.aspectTypes")}</span>
                    <span className="stg-val">☌ ☍ △ □ ✱</span>
                  </div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.descriptions")}</span>
                    <span className="stg-val">{t("settings.descCount")}</span>
                  </div>
                </div>
                <div className="stg-card">
                  <div className="stg-card-title">{t("settings.celestialBodies")}</div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.planets")}</span>
                    <span className="stg-val">☉ ☽ ☿ ♀ ♂ ♃ ♄ ♅ ♆ ♇</span>
                  </div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.points")}</span>
                    <span className="stg-val">AC MC ☊ ☋ ⚷ ⚸ ☽ Vtx PoF</span>
                  </div>
                </div>
              </>
            )}

            {page === "about" && (
              <>
                <div className="stg-card">
                  <div className="stg-card-title">{t("settings.appName")}</div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.version")}</span>
                    <span className="stg-val">{t("settings.versionVal")}</span>
                  </div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.builtBy")}</span>
                    <span className="stg-val">{t("settings.builtByVal")}</span>
                  </div>
                </div>
                <div className="stg-card">
                  <div className="stg-card-title">{t("settings.dataSources")}</div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.ephemeris")}</span>
                    <span className="stg-val">Swiss Ephemeris (Astrodienst)</span>
                  </div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.geocoding")}</span>
                    <span className="stg-val">{t("settings.geocodingVal")}</span>
                  </div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.timezone")}</span>
                    <span className="stg-val">{t("settings.timezoneVal")}</span>
                  </div>
                </div>
                <div className="stg-card">
                  <div className="stg-about-text">
                    {t("settings.aboutDesc")}
                  </div>
                </div>
              </>
            )}
          </div>
        </div>
      </div>
      {confirmDelete ? (
        <div
          className="modal-overlay stg-confirm-overlay"
          onClick={() => {
            if (!deleting) {
              setConfirmDelete(false)
              setDeleteError(null)
            }
          }}
        >
          <div className="stg-confirm" onClick={(e) => e.stopPropagation()}>
            <h3 className="stg-confirm-title">{t("settings.deleteAccountConfirmTitle")}</h3>
            <p className="stg-confirm-body">{t("settings.deleteAccountConfirmBody")}</p>
            {deleteError ? (
              <p className="stg-confirm-error">{deleteError}</p>
            ) : null}
            <div className="stg-confirm-actions">
              <button
                type="button"
                className="stg-confirm-cancel"
                disabled={deleting}
                onClick={() => {
                  setConfirmDelete(false)
                  setDeleteError(null)
                }}
              >
                {t("settings.deleteAccountCancel")}
              </button>
              <button
                type="button"
                className="stg-confirm-danger"
                disabled={deleting}
                onClick={handleDeleteAccount}
              >
                {deleting
                  ? t("settings.deleteAccountDeleting")
                  : t("settings.deleteAccountConfirmBtn")}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  )
}
