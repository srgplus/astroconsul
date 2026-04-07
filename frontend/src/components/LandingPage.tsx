import { useState, useEffect } from "react"
import { fetchFeaturedProfiles, fetchPublicProfileDetail } from "../api"
import { useLanguage } from "../contexts/LanguageContext"
import B3Logo from "./B3Logo"
import { zoneColor, FEELS_EMOJI } from "../tii-zones"
import type { ProfileSummary, ProfileDetailResponse, ActiveAspect } from "../types"

type LandingPageProps = {
  onSignIn: () => void
  onSignUp: () => void
}

const OBJECT_GLYPHS: Record<string, string> = {
  Sun: "\u2609", Moon: "\u263D", Mercury: "\u263F", Venus: "\u2640", Mars: "\u2642",
  Jupiter: "\u2643", Saturn: "\u2644", Uranus: "\u2645", Neptune: "\u2646", Pluto: "\u2647",
  Chiron: "\u26B7", Lilith: "\u26B8", Selena: "\u263E",
  "North Node": "\u260A", "South Node": "\u260B", "Part of Fortune": "\u2297", Vertex: "\u22C1",
  ASC: "AC", MC: "MC",
}

const SIGN_GLYPHS: Record<string, string> = {
  Aries: "\u2648", Taurus: "\u2649", Gemini: "\u264A", Cancer: "\u264B",
  Leo: "\u264C", Virgo: "\u264D", Libra: "\u264E", Scorpio: "\u264F",
  Sagittarius: "\u2650", Capricorn: "\u2651", Aquarius: "\u2652", Pisces: "\u2653",
}

const ASPECT_GLYPHS: Record<string, string> = {
  conjunction: "\u260C", opposition: "\u260D", trine: "\u25B3", square: "\u25A1", sextile: "\u2731",
}

const STRENGTH_COLORS: Record<string, string> = {
  exact: "#FF2D55",
  strong: "#FF9500",
  moderate: "#5AC8FA",
  wide: "#8E8E93",
}

const PLANET_EMOJI: Record<string, string> = {
  Jupiter: "\uD83C\uDF0A", Saturn: "\uD83C\uDFD7", Uranus: "\u26A1", Neptune: "\uD83C\uDF0A", Pluto: "\uD83C\uDF00",
}

const PLANET_BAR_COLOR: Record<string, string> = {
  Pluto: "#FF2D55",
  Neptune: "#5AC8FA",
  Uranus: "#FFB800",
  Saturn: "#30D158",
  Jupiter: "#5E5CE6",
}

const PERSONAL_IDS = new Set(["Sun", "Moon", "Mercury", "Venus", "Mars"])
const OUTER_IDS = new Set(["Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"])

const GROUP_LABEL_KEYS: Record<string, string> = {
  personal: "transits.personalPlanets",
  outer: "transits.outerPlanets",
  special: "transits.specialPoints",
}

function categorizeAspect(a: ActiveAspect): string {
  if (PERSONAL_IDS.has(a.transit_object)) return "personal"
  if (OUTER_IDS.has(a.transit_object)) return "outer"
  return "special"
}

function formatMonthRange(startUtc: string | null, endUtc: string | null, t: (key: string) => string): string {
  if (!startUtc || !endUtc) return ""
  const s = new Date(startUtc)
  const e = new Date(endUtc)
  if (isNaN(s.getTime()) || isNaN(e.getTime())) return ""
  const sMonth = t(`month.${s.getMonth()}`)
  const eMonth = t(`month.${e.getMonth()}`)
  const sYear = s.getFullYear()
  const eYear = e.getFullYear()
  if (sYear === eYear) return `${sMonth} \u2014 ${eMonth} ${eYear}`
  return `${sMonth} ${sYear} \u2014 ${eMonth} ${eYear}`
}

export function LandingPage({ onSignIn, onSignUp }: LandingPageProps) {
  const { t } = useLanguage()
  const [profiles, setProfiles] = useState<ProfileSummary[]>([])
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [detail, setDetail] = useState<ProfileDetailResponse | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetchFeaturedProfiles()
      .then((data) => setProfiles(data.profiles))
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [])

  useEffect(() => {
    if (!selectedId) {
      setDetail(null)
      return
    }
    setLoading(true)
    fetchPublicProfileDetail(selectedId)
      .then((data) => setDetail(data))
      .catch(() => setDetail(null))
      .finally(() => setLoading(false))
  }, [selectedId])

  if (selectedId) {
    return (
      <LandingDetail
        detail={detail}
        loading={loading}
        onBack={() => setSelectedId(null)}
        onSignUp={onSignUp}
      />
    )
  }

  const ZODIAC = ["\u2648","\u2649","\u264A","\u264B","\u264C","\u264D","\u264E","\u264F","\u2650","\u2651","\u2652","\u2653"]

  return (
    <div className="landing-page">
      <header className="landing-header">
        <B3Logo size="md" />
        <nav className="landing-nav">
          <a href="/news/" className="landing-nav-link">News</a>
        </nav>
        <div className="landing-header-actions">
          <button type="button" className="landing-auth-btn" onClick={onSignIn}>
            {t("landing.signIn")}
          </button>
          <button type="button" className="landing-auth-btn landing-auth-btn--primary" onClick={onSignUp}>
            {t("landing.signUp")}
          </button>
        </div>
      </header>

      <section className="landing-hero">
        <div className="landing-zodiac-ring">
          <div className="landing-zodiac-ring__inner">
            {ZODIAC.map((g, i) => (
              <span key={i} className="landing-zodiac-ring__glyph" style={{ "--i": i } as React.CSSProperties}>{g}</span>
            ))}
          </div>
        </div>
        <h1 className="landing-hero-title landing-fade-in">{t("landing.hero")}</h1>
        <p className="landing-hero-subtitle landing-fade-in" style={{ animationDelay: "0.1s" }}>{t("landing.subtitle")}</p>
        <div className="landing-hero-ctas landing-fade-in" style={{ animationDelay: "0.2s" }}>
          <button type="button" className="landing-cta-btn" onClick={onSignUp}>
            {t("landing.cta")}
          </button>
        </div>
        <div className="landing-pills landing-fade-in" style={{ animationDelay: "0.3s" }}>
          <span className="landing-pill">Transit Alerts</span>
          <span className="landing-pill">Moon Phases</span>
          <span className="landing-pill">Natal Chart</span>
          <span className="landing-pill">Synastry</span>
        </div>
      </section>

      {loading ? (
        <div className="landing-loading">{t("landing.loading")}</div>
      ) : profiles.length > 0 ? (
        <>
          <div className="landing-section-label">Featured Charts</div>
          <section className="landing-grid">
            {profiles.map((p) => (
              <LandingCard key={p.profile_id} profile={p} onClick={() => setSelectedId(p.profile_id)} />
            ))}
          </section>
        </>
      ) : null}

      <footer className="landing-footer">
        <span className="landing-footer__copy">&copy; big3.me {new Date().getFullYear()}</span>
        <span className="landing-footer__links">
          <a href="/news/">News</a>
          <a href="/support">Support</a>
          <a href="/legal">Terms</a>
        </span>
      </footer>
    </div>
  )
}

function LandingCard({ profile, onClick }: { profile: ProfileSummary; onClick: () => void }) {
  const { t } = useLanguage()
  const lt = profile.latest_transit
  const tii = lt?.tii ?? null
  const feelsLike = lt?.feels_like ?? null
  const accent = tii != null ? zoneColor(tii) : "var(--muted)"
  const emoji = feelsLike ? (FEELS_EMOJI[feelsLike] ?? "\u2728") : null

  return (
    <button type="button" className="landing-card profile-list-item has-tii" onClick={onClick}>
      <div className="pli-name-row">
        <span className="pli-name">{profile.profile_name}</span>
        {tii != null ? (
          <span className="pli-tii" style={{ color: accent }}>{Math.round(tii)}&deg;</span>
        ) : null}
      </div>
      <div className="pli-username">@{profile.username}</div>
      {feelsLike ? (
        <div className="pli-bottom">
          <span className="pli-feels" style={{ color: accent }}>
            {emoji} {t(`feels.${feelsLike}`)}
          </span>
        </div>
      ) : null}
    </button>
  )
}

function LandingDetail({
  detail,
  loading,
  onBack,
  onSignUp,
}: {
  detail: ProfileDetailResponse | null
  loading: boolean
  onBack: () => void
  onSignUp: () => void
}) {
  const { t } = useLanguage()

  return (
    <div className="landing-page">
      <header className="landing-header">
        <button type="button" className="landing-back-btn" onClick={onBack}>
          &larr; {t("landing.back")}
        </button>
        <div className="landing-header-actions">
          <button type="button" className="landing-auth-btn landing-auth-btn--primary" onClick={onSignUp}>
            {t("landing.signUp")}
          </button>
        </div>
      </header>

      {loading ? (
        <div className="landing-loading">{t("landing.loading")}</div>
      ) : detail ? (
        <div className="landing-detail">
          <LandingHero detail={detail} />
          <LandingTransits detail={detail} />
          <LandingClimate detail={detail} />
          <section className="landing-cta">
            <p className="landing-cta-hint">{t("landing.signUpUnlock")}</p>
            <button type="button" className="landing-cta-btn" onClick={onSignUp}>
              {t("landing.signUp")}
            </button>
          </section>
        </div>
      ) : null}
    </div>
  )
}

function LandingHero({ detail }: { detail: ProfileDetailResponse }) {
  const { t } = useLanguage()
  const lt = detail.profile.latest_transit
  const tii = lt?.tii ?? 0
  const feelsLike = lt?.feels_like ?? "Calm"
  const tensionRatio = lt?.tension_ratio ?? 0
  const accent = zoneColor(tii)
  const emoji = FEELS_EMOJI[feelsLike] ?? "\u2728"
  const feelsLabel = t(`feels.${feelsLike}`)
  const mood = t(`mood.${feelsLike}`)

  const tz = lt?.timezone ?? ""
  const tzLabel = (() => {
    if (!tz) return ""
    const city = tz.split("/").pop()?.replace(/_/g, " ") ?? tz
    try {
      const offsetStr = new Intl.DateTimeFormat("en", { timeZone: tz, timeZoneName: "shortOffset" })
        .formatToParts(new Date())
        .find((p) => p.type === "timeZoneName")?.value ?? ""
      return `${city} ${offsetStr}`.toUpperCase()
    } catch {
      return city.toUpperCase()
    }
  })()

  return (
    <div className="cw">
      <div className="cw-hero">
        {tzLabel ? <div className="cw-location">{tzLabel}</div> : null}
        <div className="cw-title">{detail.profile.profile_name}</div>
        <div className="cw-emoji">{emoji}</div>
        <div className="cw-tii">{Math.round(tii)}&deg;</div>
        <div className="cw-tii-label">{t("weather.intensity")}</div>
        <div className="cw-feels" style={{ color: accent }}>{feelsLabel}</div>
        <div className="cw-mood">{mood}</div>
        <div className="cw-tension-bar">
          <div className="cw-tension-bar__track">
            <div
              className="cw-tension-bar__fill"
              style={{ width: `${Math.round(tensionRatio * 100)}%`, background: accent }}
            />
          </div>
          <span className="cw-tension-bar__label">{t("weather.tension")} {Math.round(tensionRatio * 100)}%</span>
        </div>
      </div>
    </div>
  )
}

function LandingTransits({ detail }: { detail: ProfileDetailResponse }) {
  const { t } = useLanguage()
  const chart = detail.chart as Record<string, unknown>
  const activeAspects = (chart.active_aspects as ActiveAspect[] | undefined) ?? []
  const [mostImpact, setMostImpact] = useState(true)

  if (!activeAspects.length) return null

  const aspects = mostImpact
    ? activeAspects.filter((a) => a.strength === "exact" || a.strength === "strong")
    : activeAspects

  const groupOrder = ["personal", "outer", "special"]
  const groups: Record<string, ActiveAspect[]> = {}
  for (const a of aspects) {
    const cat = categorizeAspect(a)
    if (!groups[cat]) groups[cat] = []
    groups[cat].push(a)
  }
  const groupedAspects = groupOrder
    .filter((key) => groups[key]?.length)
    .map((key) => ({ key, aspects: groups[key]! }))

  return (
    <div className="cw-transits">
      <div className="cw-transits-header">
        <span className="cw-transits-title">{t("transits.title")}</span>
        <label className="cw-toggle-wrap">
          <span className="cw-toggle-label">{t("transits.mostImpact")}</span>
          <div
            className={`cw-toggle${mostImpact ? " cw-toggle--on" : ""}`}
            onClick={() => setMostImpact(!mostImpact)}
          >
            <div className="cw-toggle-thumb" />
          </div>
        </label>
      </div>
      {groupedAspects.map((group) => (
        <div key={group.key} className="cw-transit-group">
          <div className="cw-transit-group-label">{t(GROUP_LABEL_KEYS[group.key]).toUpperCase()}</div>
          <div className="cw-transit-list">
            {group.aspects.map((a, i) => {
              const strengthColor = STRENGTH_COLORS[a.strength] ?? "#8E8E93"
              return (
                <div key={`${a.transit_object}-${a.natal_object}-${i}`} className="cw-transit-item">
                  <div className="cw-transit-row">
                    <span className="cw-transit-left">
                      <span className="cw-transit-glyphs">
                        <span className="cw-glyph-transit">{OBJECT_GLYPHS[a.transit_object] ?? a.transit_object}</span>
                        <span className="cw-glyph-aspect">{ASPECT_GLYPHS[a.aspect] ?? a.aspect}</span>
                        <span className="cw-glyph-natal">{OBJECT_GLYPHS[a.natal_object] ?? a.natal_object}</span>
                      </span>
                      <span className="cw-transit-label">
                        {t(`planet.${a.transit_object}`)} {t(`aspect.${a.aspect}`)} {t(`planet.${a.natal_object}`)}
                      </span>
                    </span>
                    <span className="cw-transit-right">
                      <span className="cw-transit-orb">{a.orb.toFixed(2)}&deg;</span>
                      <span
                        className="cw-transit-strength"
                        style={{ background: `${strengthColor}18`, color: strengthColor }}
                      >
                        {t(`strength.${a.strength}`)}
                      </span>
                    </span>
                  </div>
                  {a.meaning ? (
                    <div className="cw-transit-description">
                      <p className="cw-transit-meaning">{a.meaning}</p>
                    </div>
                  ) : null}
                </div>
              )
            })}
          </div>
        </div>
      ))}
    </div>
  )
}

function LandingClimate({ detail }: { detail: ProfileDetailResponse }) {
  const { t } = useLanguage()
  const chart = detail.chart as Record<string, unknown>
  const climateAspects = (chart.cosmic_climate as ActiveAspect[] | undefined) ?? []
  const nowDate = (chart.transit_date as string) ?? ""

  if (!climateAspects.length) return null

  return (
    <div className="cc-widget">
      <div className="cc-title">{t("climate.title")}</div>
      {climateAspects.map((a, i) => {
        const aGlyph = ASPECT_GLYPHS[a.aspect] ?? a.aspect
        const emoji = PLANET_EMOJI[a.transit_object] ?? "\u2728"
        const dateRange = formatMonthRange(a.timing?.start_utc ?? null, a.timing?.end_utc ?? null, t)
        const color = PLANET_BAR_COLOR[a.transit_object] ?? "#5AC8FA"

        let pct = 0
        if (a.timing?.start_utc && a.timing?.end_utc && nowDate) {
          const start = new Date(a.timing.start_utc).getTime()
          const end = new Date(a.timing.end_utc).getTime()
          const now = new Date(nowDate + "T12:00:00Z").getTime()
          const total = end - start
          if (total > 0) pct = Math.max(0, Math.min(100, ((now - start) / total) * 100))
        }

        return (
          <div key={`${a.transit_object}-${a.natal_object}-${i}`} className="cc-card">
            <div className="cc-card-header">
              <div className="cc-card-left">
                <span className="cc-card-emoji">{emoji}</span>
                <span className="cc-card-name">
                  {t(`planet.${a.transit_object}`)} {aGlyph} {t(`planet.${a.natal_object}`)}
                </span>
              </div>
              {dateRange ? <span className="cc-card-date">{dateRange}</span> : null}
            </div>
            {a.meaning ? <p className="cc-card-desc">{a.meaning}</p> : null}
            {a.insight ? <p className="cc-card-insight">{a.insight}</p> : null}
            <div className="cc-bar">
              <div className="cc-bar__track">
                <div className="cc-bar__fill" style={{ width: `${pct}%`, background: color }} />
              </div>
            </div>
          </div>
        )
      })}
    </div>
  )
}
