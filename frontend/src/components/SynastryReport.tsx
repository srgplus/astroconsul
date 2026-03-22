import type { SynastryReportResponse, SynastryAspect } from "../types"

const SIGN_GLYPHS: Record<string, string> = {
  Aries: "\u2648", Taurus: "\u2649", Gemini: "\u264A", Cancer: "\u264B",
  Leo: "\u264C", Virgo: "\u264D", Libra: "\u264E", Scorpio: "\u264F",
  Sagittarius: "\u2650", Capricorn: "\u2651", Aquarius: "\u2652", Pisces: "\u2653",
}

const OBJECT_GLYPHS: Record<string, string> = {
  Sun: "\u2609", Moon: "\u263D", Mercury: "\u263F", Venus: "\u2640", Mars: "\u2642",
  Jupiter: "\u2643", Saturn: "\u2644", Uranus: "\u2645", Neptune: "\u2646", Pluto: "\u2647",
  Chiron: "\u26B7", Lilith: "\u26B8", "North Node": "\u260A", "South Node": "\u260B",
  ASC: "AC", MC: "MC", Selena: "\u2BDB", "Part of Fortune": "\u2297", Vertex: "Vx",
}

const ASPECT_GLYPHS: Record<string, string> = {
  conjunction: "\u260C", sextile: "\u26B9", square: "\u25A1", trine: "\u25B3", opposition: "\u260D",
}

type Props = {
  report: SynastryReportResponse
}

function Big3Badges({ summary }: { summary: Record<string, string> | null }) {
  if (!summary) return null
  const sun = summary.Sun || summary.sun
  const moon = summary.Moon || summary.moon
  const asc = summary.Ascendant || summary.ascendant || summary.ASC
  return (
    <div className="syn-big3">
      {sun ? <span className="syn-sign-badge">{SIGN_GLYPHS[sun] || ""}</span> : null}
      {moon ? <span className="syn-sign-badge">{SIGN_GLYPHS[moon] || ""}</span> : null}
      {asc ? <span className="syn-sign-badge">{SIGN_GLYPHS[asc] || ""}</span> : null}
    </div>
  )
}

function ScoreGauge({ score, label }: { score: number; label: string }) {
  const radius = 70
  const circumference = 2 * Math.PI * radius
  const offset = circumference - (score / 100) * circumference

  return (
    <div className="syn-gauge">
      <svg viewBox="0 0 160 160" className="syn-gauge-svg">
        <circle cx="80" cy="80" r={radius} fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth="10" />
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
      <div className="syn-gauge-label">Overall Chemistry: <span className="syn-gauge-label-val">{label}</span></div>
    </div>
  )
}

function CategoryScores({ scores }: { scores: SynastryReportResponse["scores"] }) {
  const categories = [
    { key: "emotional", label: "EMOTIONAL", value: scores.emotional, color: "#ec4899" },
    { key: "mental", label: "MENTAL", value: scores.mental, color: "#6366f1" },
    { key: "physical", label: "PHYSICAL", value: scores.physical, color: "#f59e0b" },
    { key: "karmic", label: "KARMIC", value: scores.karmic, color: "#8b5cf6" },
  ]

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

function AspectCard({ aspect }: { aspect: SynastryAspect }) {
  const aGlyph = OBJECT_GLYPHS[aspect.person_a_object] || aspect.person_a_object
  const bGlyph = OBJECT_GLYPHS[aspect.person_b_object] || aspect.person_b_object
  const aspectGlyph = ASPECT_GLYPHS[aspect.aspect] || aspect.aspect

  // Extract sign+degree from the position data embedded in delta/exact_angle
  // We show the object name + glyph instead
  const orbColor = aspect.strength === "exact" ? "#22c55e" : aspect.strength === "strong" ? "#22c55e" : "#8e8e93"

  return (
    <div className="syn-aspect-card">
      <div className="syn-aspect-header">
        <div className="syn-aspect-name">
          {aspect.person_a_object} {aspect.aspect} {aspect.person_b_object}
        </div>
        <span className="syn-aspect-orb" style={{ color: orbColor }}>
          {aspect.orb.toFixed(1)}&deg;
        </span>
      </div>
      <div className="syn-aspect-chips">
        <span className="syn-chip syn-chip--a">A {aGlyph} {aspect.person_a_object}</span>
        <span className="syn-aspect-glyph">{aspectGlyph}</span>
        <span className="syn-chip syn-chip--b">B {bGlyph} {aspect.person_b_object}</span>
      </div>
      {aspect.meaning && <div className="syn-aspect-meaning">{aspect.meaning}</div>}
    </div>
  )
}

export default function SynastryReport({ report }: Props) {
  const { scores, aspects } = report
  const exactAspects = aspects.filter((a) => a.strength === "exact")
  const strongAspects = aspects.filter((a) => a.strength === "strong")

  return (
    <div className="syn-report">
      {/* Header */}
      <div className="syn-header">
        <div className="syn-header-persons">
          <div className="syn-person">
            <div className="syn-avatar syn-avatar--a"><span>A</span></div>
            <div className="syn-person-name">{report.person_a.name}</div>
            <Big3Badges summary={report.person_a.natal_summary} />
          </div>
          <span className="syn-header-x">&times;</span>
          <div className="syn-person">
            <div className="syn-avatar syn-avatar--b"><span>B</span></div>
            <div className="syn-person-name">{report.person_b.name}</div>
            <Big3Badges summary={report.person_b.natal_summary} />
          </div>
        </div>
        <h2 className="syn-title">Synastry Report</h2>
        <div className="syn-subtitle">
          {report.aspect_count} inter-aspects found &middot; {report.exact_count} exact or tight
        </div>
      </div>

      {/* Score card */}
      <div className="syn-score-card">
        <ScoreGauge score={scores.overall} label={scores.overall_label} />
        <CategoryScores scores={scores} />
      </div>

      {/* Exact aspects */}
      {exactAspects.length > 0 && (
        <div className="syn-section">
          <h3 className="syn-section-title">EXACT ASPECTS</h3>
          {exactAspects.map((a, i) => (
            <AspectCard key={`exact-${i}`} aspect={a} />
          ))}
        </div>
      )}

      {/* Strong aspects */}
      {strongAspects.length > 0 && (
        <div className="syn-section">
          <h3 className="syn-section-title">STRONG ASPECTS</h3>
          {strongAspects.map((a, i) => (
            <AspectCard key={`strong-${i}`} aspect={a} />
          ))}
        </div>
      )}

      {/* Overall reading */}
      {report.overall_reading && (
        <div className="syn-reading">
          <h3 className="syn-reading-title">Overall Reading</h3>
          <div className="syn-reading-text">{report.overall_reading}</div>
        </div>
      )}

      {/* Footer */}
      <div className="syn-footer">
        <div className="syn-footer-brand">
          <span className="brand-big">big</span><span className="brand-3">3</span><span className="brand-me">.me</span>
        </div>
      </div>
    </div>
  )
}
