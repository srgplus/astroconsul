import { useState } from "react"
import type { SynastryReportResponse, SynastryScoresBusiness, SynastryAspect, SynastryPosition } from "../types"
import { useLanguage } from "../contexts/LanguageContext"

const SIGN_GLYPHS: Record<string, string> = {
  Aries: "\u2648", Taurus: "\u2649", Gemini: "\u264A", Cancer: "\u264B",
  Leo: "\u264C", Virgo: "\u264D", Libra: "\u264E", Scorpio: "\u264F",
  Sagittarius: "\u2650", Capricorn: "\u2651", Aquarius: "\u2652", Pisces: "\u2653",
}

const OBJECT_GLYPHS: Record<string, string> = {
  Sun: "\u2609", Moon: "\u263D", Mercury: "\u263F", Venus: "\u2640", Mars: "\u2642",
  Jupiter: "\u2643", Saturn: "\u2644", Uranus: "\u2645", Neptune: "\u2646", Pluto: "\u2647",
  Chiron: "\u26B7", Lilith: "\u26B8", "North Node": "\u260A", "South Node": "\u260B",
  ASC: "AC", MC: "MC", Selena: "\u263E", "Part of Fortune": "\u2297", Vertex: "Vx",
}

const ASPECT_GLYPHS: Record<string, string> = {
  conjunction: "\u260C", sextile: "\u26B9", square: "\u25A1", trine: "\u25B3", opposition: "\u260D",
}

const STRENGTH_COLORS: Record<string, string> = {
  exact: "#FF2D55",
  strong: "#FF9500",
  moderate: "#5AC8FA",
  wide: "#8E8E93",
}

const PLANET_ORDER: string[] = [
  "Sun", "Moon", "Mercury", "Venus", "Mars", "ASC", "MC",
  "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto",
  "Chiron", "Lilith", "Selena", "North Node", "South Node", "Part of Fortune", "Vertex",
]
const PLANET_RANK = new Map(PLANET_ORDER.map((id, i) => [id, i]))

const PERSONAL_IDS = new Set(["Sun", "Moon", "Mercury", "Venus", "Mars", "ASC", "MC"])
const OUTER_IDS = new Set(["Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"])

function categorizeAspect(a: SynastryAspect): string {
  if (PERSONAL_IDS.has(a.person_a_object) || PERSONAL_IDS.has(a.person_b_object)) return "personal"
  if (OUTER_IDS.has(a.person_a_object) || OUTER_IDS.has(a.person_b_object)) return "outer"
  return "special"
}

const GROUP_LABELS: Record<string, string> = {
  personal: "PERSONAL PLANETS",
  outer: "OUTER PLANETS",
  special: "SPECIAL POINTS",
}

type Props = {
  report: SynastryReportResponse
}

function getInitials(name: string): string {
  const parts = name.trim().split(/\s+/)
  if (parts.length === 1) return parts[0].charAt(0).toUpperCase()
  return parts.map((w) => w.charAt(0).toUpperCase()).join("")
}

function ScoreGauge({ score, label, chemistryLabel }: { score: number; label: string; chemistryLabel: string }) {
  const radius = 70
  const circumference = 2 * Math.PI * radius
  const offset = circumference - (score / 100) * circumference

  return (
    <div className="syn-gauge">
      <svg viewBox="0 0 160 160" className="syn-gauge-svg">
        <circle cx="80" cy="80" r={radius} fill="none" className="syn-gauge-track" strokeWidth="10" />
        <circle
          cx="80" cy="80" r={radius} fill="none"
          stroke="url(#synGrad)" strokeWidth="10"
          strokeDasharray={circumference}
          strokeDashoffset={offset}
          strokeLinecap="round"
          transform="rotate(-90 80 80)"
        />
        <defs>
          <linearGradient id="synGrad" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#a855f7" />
            <stop offset="100%" stopColor="#ec4899" />
          </linearGradient>
        </defs>
        <text x="80" y="88" textAnchor="middle" className="syn-gauge-number">{score}</text>
      </svg>
      <div className="syn-gauge-label">{chemistryLabel} <span className="syn-gauge-label-val">{label}</span></div>
    </div>
  )
}

type CategoryDef = { key: string; label: string; value: number; color: string }

function CategoryScores({ categories }: { categories: CategoryDef[] }) {
  return (
    <div className="syn-categories">
      {categories.map((c) => (
        <div key={c.key} className="syn-cat">
          <div className="syn-cat-label">{c.label}</div>
          <div className="syn-cat-value" style={{ color: c.color }}>{c.value}%</div>
          <div className="syn-cat-bar">
            <div className="syn-cat-bar-fill" style={{ width: `${c.value}%`, backgroundColor: c.color }} />
          </div>
        </div>
      ))}
    </div>
  )
}

type SynMode = "love" | "business"

export default function SynastryReport({ report }: Props) {
  const { t } = useLanguage()
  const { scores, aspects } = report
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [mostImpact, setMostImpact] = useState(true)
  const [mode, setMode] = useState<SynMode>("love")

  const groupLabels: Record<string, string> = {
    personal: t("synastry.personalPlanets"),
    outer: t("synastry.outerPlanets"),
    special: t("synastry.specialPoints"),
  }

  const hasBusiness = !!report.scores_business
  const activeScores = mode === "business" && report.scores_business
    ? report.scores_business
    : scores
  const activeReading = mode === "business"
    ? report.overall_reading_business
    : report.overall_reading

  const loveCategories: CategoryDef[] = [
    { key: "emotional", label: t("synastry.emotional"), value: scores.emotional, color: "#ec4899" },
    { key: "mental", label: t("synastry.mental"), value: scores.mental, color: "#6366f1" },
    { key: "physical", label: t("synastry.physical"), value: scores.physical, color: "#f59e0b" },
    { key: "karmic", label: t("synastry.karmic"), value: scores.karmic, color: "#8b5cf6" },
  ]
  const businessCategories: CategoryDef[] = report.scores_business ? [
    { key: "communication", label: t("synastry.communication"), value: report.scores_business.communication, color: "#6366f1" },
    { key: "drive", label: t("synastry.drive"), value: report.scores_business.drive, color: "#f59e0b" },
    { key: "trust", label: t("synastry.trust"), value: report.scores_business.trust, color: "#10b981" },
    { key: "vision", label: t("synastry.vision"), value: report.scores_business.vision, color: "#8b5cf6" },
  ] : []
  const activeCategories = mode === "business" ? businessCategories : loveCategories

  // Build position maps
  const posMapA = new Map((report.positions_a ?? []).map((p: SynastryPosition) => [p.id, p]))
  const posMapB = new Map((report.positions_b ?? []).map((p: SynastryPosition) => [p.id, p]))

  // Filter
  const filtered = mostImpact
    ? aspects.filter((a) => a.strength === "exact" || a.strength === "strong")
    : aspects

  // Group by category
  const groupOrder = ["personal", "outer", "special"]
  const groups: Record<string, SynastryAspect[]> = {}
  for (const a of filtered) {
    const cat = categorizeAspect(a)
    if (!groups[cat]) groups[cat] = []
    groups[cat].push(a)
  }
  // Sort within each group by planet order (like natal), then by orb
  for (const key of groupOrder) {
    if (groups[key]) {
      groups[key].sort((a, b) => {
        const ra = PLANET_RANK.get(a.person_a_object) ?? 99
        const rb = PLANET_RANK.get(b.person_a_object) ?? 99
        if (ra !== rb) return ra - rb
        return a.orb - b.orb
      })
    }
  }
  const groupedAspects = groupOrder
    .filter((key) => groups[key]?.length)
    .map((key) => ({ key, aspects: groups[key]! }))

  const toggle = (key: string) => {
    setExpanded((prev) => {
      const next = new Set(prev)
      next.has(key) ? next.delete(key) : next.add(key)
      return next
    })
  }

  return (
    <div className="syn-report">
      {/* Header */}
      <div className="syn-header">
        <div className="syn-header-persons">
          <div className="syn-person">
            <div className="syn-avatar syn-avatar--a"><span>{getInitials(report.person_a.name)}</span></div>
            <div className="syn-person-name">{report.person_a.name}</div>
          </div>
          <span className="syn-header-x">&times;</span>
          <div className="syn-person">
            <div className="syn-avatar syn-avatar--b"><span>{getInitials(report.person_b.name)}</span></div>
            <div className="syn-person-name">{report.person_b.name}</div>
          </div>
        </div>
        <h2 className="syn-title">{t("synastry.report")}</h2>
        <div className="syn-subtitle">
          {report.aspect_count} {t("synastry.interAspects")} &middot; {report.exact_count} {t("synastry.exactOrTight")}
        </div>
      </div>

      {/* Mode toggle: Love / Business */}
      {hasBusiness && (
        <div className="syn-mode-toggle">
          <button
            type="button"
            className={`syn-mode-btn${mode === "love" ? " syn-mode-btn--active" : ""}`}
            onClick={() => setMode("love")}
          >{t("synastry.love")}</button>
          <button
            type="button"
            className={`syn-mode-btn${mode === "business" ? " syn-mode-btn--active" : ""}`}
            onClick={() => setMode("business")}
          >{t("synastry.business")}</button>
        </div>
      )}

      {/* Score card */}
      <div className="syn-score-card">
        <ScoreGauge score={activeScores.overall} label={activeScores.overall_label} chemistryLabel={t("synastry.overallChemistry")} />
        <CategoryScores categories={activeCategories} />
      </div>

      {/* Overall reading — ABOVE aspects */}
      {activeReading && (
        <div className="syn-reading">
          <h3 className="syn-reading-title">{t("synastry.overallReading")}</h3>
          <div className="syn-reading-text">{activeReading}</div>
        </div>
      )}

      {/* Aspects table — natal style */}
      <div className="natal-asp">
        <div className="natal-asp__header">
          <span className="natal-asp__title">{t("synastry.aspects")}</span>
          <button type="button" className="cw-toggle-wrap" onClick={() => setMostImpact(!mostImpact)}>
            <span className="cw-toggle-label">{t("synastry.mostImpact")}</span>
            <div className={`cw-toggle${mostImpact ? " cw-toggle--on" : ""}`}>
              <div className="cw-toggle-thumb" />
            </div>
          </button>
        </div>
        {groupedAspects.map((group) => (
          <div key={group.key} className="cw-transit-group">
            <div className="cw-transit-group-label">{groupLabels[group.key]}</div>
            <div className="cw-transit-list">
              {group.aspects.map((a, i) => {
                const strengthColor = STRENGTH_COLORS[a.strength] ?? "#8E8E93"
                const aspKey = `${a.person_a_object}_${a.aspect}_${a.person_b_object}_${i}`
                const clickable = !!a.meaning
                const isOpen = expanded.has(aspKey)
                return (
                  <div
                    key={aspKey}
                    className={`cw-transit-item${isOpen ? " cw-transit-item--expanded" : ""}`}
                    style={clickable ? { cursor: "pointer" } : undefined}
                    onClick={clickable ? () => toggle(aspKey) : undefined}
                  >
                    <div className="cw-transit-row">
                      <span className="cw-transit-left">
                        <span className="cw-transit-glyphs">
                          <span className="syn-glyph-a">{OBJECT_GLYPHS[a.person_a_object] ?? ""}</span>
                          <span className="cw-glyph-aspect">{ASPECT_GLYPHS[a.aspect] ?? ""}</span>
                          <span className="syn-glyph-b">{OBJECT_GLYPHS[a.person_b_object] ?? ""}</span>
                        </span>
                        <span className="cw-transit-label">
                          {a.person_a_object} {a.aspect} {a.person_b_object}
                        </span>
                      </span>
                      <span className="cw-transit-right">
                        <span className="cw-transit-orb">{a.orb.toFixed(2)}°</span>
                        <span
                          className="cw-transit-strength"
                          style={{ background: `${strengthColor}18`, color: strengthColor }}
                        >
                          {a.strength.toUpperCase()}
                        </span>
                      </span>
                    </div>

                    {isOpen && a.meaning ? (
                      <div className="cw-transit-description">
                        <p className="cw-transit-meaning">{a.meaning}</p>
                        {a.keywords?.length ? (
                          <div className="cw-transit-keywords">
                            {a.keywords.map((kw, ki) => (
                              <span key={ki} className="cw-transit-keyword-tag">{kw}</span>
                            ))}
                          </div>
                        ) : null}
                        {(() => {
                          const aPos = posMapA.get(a.person_a_object)
                          const bPos = posMapB.get(a.person_b_object)
                          if (!aPos && !bPos) return null
                          return (
                            <div className="cw-transit-positions">
                              {aPos ? (
                                <div className="cw-pos-line">
                                  <span className="syn-glyph-a" style={{ fontSize: 13 }}>{OBJECT_GLYPHS[a.person_a_object]}</span>
                                  <span className="cw-pos-name" style={{ color: "#a5b4fc" }}>{a.person_a_object}</span>
                                  <span className="cw-pos-deg">{aPos.degree}°{String(aPos.minute).padStart(2, "0")}′</span>
                                  <span className="cw-pos-sign">{SIGN_GLYPHS[aPos.sign] ?? ""} {aPos.sign}</span>
                                  {aPos.house ? <span className="cw-pos-house">△{aPos.house}</span> : null}
                                  {aPos.retrograde ? <span className="cw-pos-retro">Ⓡ</span> : null}
                                </div>
                              ) : null}
                              {bPos ? (
                                <div className="cw-pos-line">
                                  <span className="syn-glyph-b" style={{ fontSize: 13 }}>{OBJECT_GLYPHS[a.person_b_object]}</span>
                                  <span className="cw-pos-name" style={{ color: "#f9a8d4" }}>{a.person_b_object}</span>
                                  <span className="cw-pos-deg">{bPos.degree}°{String(bPos.minute).padStart(2, "0")}′</span>
                                  <span className="cw-pos-sign">{SIGN_GLYPHS[bPos.sign] ?? ""} {bPos.sign}</span>
                                  {bPos.house ? <span className="cw-pos-house">△{bPos.house}</span> : null}
                                  {bPos.retrograde ? <span className="cw-pos-retro">Ⓡ</span> : null}
                                </div>
                              ) : null}
                            </div>
                          )
                        })()}
                      </div>
                    ) : null}
                  </div>
                )
              })}
            </div>
          </div>
        ))}
      </div>

      {/* Footer */}
      <div className="syn-footer">
        <div className="syn-footer-brand">
          <span className="brand-big">big</span><span className="brand-3">3</span><span className="brand-me">.me</span>
        </div>
      </div>
    </div>
  )
}
