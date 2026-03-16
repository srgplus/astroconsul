import { useState } from "react"
import type { ProfileSummary, TransitReportResponse } from "../types"
import { useLanguage, type Lang } from "../contexts/LanguageContext"

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
}: SettingsModalProps) {
  const [page, setPage] = useState<SettingsPage>("account")
  const { t, lang, setLang } = useLanguage()

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
                    <span className="stg-val stg-val--badge">{t("settings.freeBeta")}</span>
                  </div>
                  <div className="stg-row">
                    <span className="stg-label">{t("settings.transitReports")}</span>
                    <span className="stg-val">{t("settings.unlimited")}</span>
                  </div>
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
                  <div className="stg-theme-grid">
                    {LANG_OPTIONS.map((opt) => (
                      <button
                        key={opt.id}
                        type="button"
                        className={`stg-theme-card${lang === opt.id ? " stg-theme-card--active" : ""}`}
                        onClick={() => setLang(opt.id)}
                      >
                        <div className={`stg-theme-preview stg-theme-preview--${opt.id === "en" ? "light" : "dark"}`}>
                          <div className="stg-theme-preview-bar" />
                          <div className="stg-theme-preview-content">
                            <div className="stg-theme-preview-line" />
                            <div className="stg-theme-preview-line short" />
                          </div>
                        </div>
                        <span className="stg-theme-name">{opt.label}</span>
                      </button>
                    ))}
                  </div>
                </div>
              </>
            )}

            {page === "system" && (
              <>
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
                <div className="stg-card">
                  <div className="stg-card-title">{t("settings.cache")}</div>
                  <p className="stg-card-desc">{t("settings.cacheDesc")}</p>
                  <button type="button" className="stg-signout-btn" onClick={onResetCache}>
                    {t("settings.resetCache")}
                  </button>
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
    </div>
  )
}
