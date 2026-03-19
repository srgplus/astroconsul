import { useState } from "react"
import { useLanguage } from "../contexts/LanguageContext"
import modifiersData from "../data/feels_like_time_modifiers.json"

const timeWindows = ["morning", "afternoon", "evening", "night"] as const
const timeIcons: Record<string, string> = { morning: "\u{1F305}", afternoon: "\u2600\uFE0F", evening: "\u{1F307}", night: "\u{1F319}" }

function Collapsible({ title, children, defaultOpen = true }: { title: string; children: React.ReactNode; defaultOpen?: boolean }) {
  const [open, setOpen] = useState(defaultOpen)
  return (
    <div className="guide-collapse">
      <button type="button" className="guide-collapse__head" onClick={() => setOpen(!open)}>
        <span className={`guide-chevron ${open ? "guide-chevron--open" : ""}`}>{"\u203A"}</span>
        <span>{title}</span>
      </button>
      {open ? <div className="guide-collapse__body">{children}</div> : null}
    </div>
  )
}

function ZoneSection({ zone, range, color, desc, items, lang }: {
  zone: string; range: string; color: string; desc: string; lang: "en" | "ru"
  items: readonly { emoji: string; label: string; tension: string; mood: string; text: string; feelsKey: string }[]
}) {
  const [open, setOpen] = useState(true)
  return (
    <div className="guide-zone">
      <button type="button" className="guide-zone__head" onClick={() => setOpen(!open)}>
        <span className={`guide-chevron ${open ? "guide-chevron--open" : ""}`}>{"\u203A"}</span>
        <span className="guide-zone__dot" style={{ background: color }} />
        <span className="guide-zone__name" style={{ color }}>{zone}</span>
        <span className="guide-zone__range">{range}</span>
      </button>
      {open ? (
        <div className="guide-zone__body">
          <p className="guide-text guide-text--muted">{desc}</p>
          {items.map(({ emoji, label, tension, mood, text, feelsKey }) => {
            const mod = (modifiersData as Record<string, Record<string, Record<string, { headline: string; description: string }>>>)[feelsKey]
            return (
              <div key={label} className="guide-feels">
                <div className="guide-feels__head">
                  <span className="guide-feels__emoji">{emoji}</span>
                  <strong>{label}</strong>
                  <span className="guide-text--muted">({tension})</span>
                </div>
                {mod && (
                  <div className="guide-feels__times">
                    {timeWindows.map((tw) => {
                      const m = mod[tw]?.[lang]
                      if (!m) return null
                      return (
                        <div key={tw} className="guide-feels__time-row">
                          <span className="guide-feels__time-icon">{timeIcons[tw]}</span>
                          <div>
                            <strong>{m.headline}</strong>
                            <span className="guide-text--muted"> &mdash; {m.description}</span>
                          </div>
                        </div>
                      )
                    })}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      ) : null}
    </div>
  )
}

function buildZones(t: (key: string) => string) {
  return [
    {
      zone: t("guide.zoneQuiet"),
      range: t("guide.zoneQuietRange"),
      color: "#4A90D9",
      desc: t("guide.zoneQuietDesc"),
      items: [
        {
          emoji: "\u2601\uFE0F",
          label: t("guide.feelsCalmLabel"),
          tension: t("guide.feelsCalmTension"),
          mood: t("mood.Calm"),
          text: t("guide.feelsCalmQuiet"),
          feelsKey: "Calm",
        },
        {
          emoji: "\u{1F32B}\uFE0F",
          label: t("guide.feelsSubtleLabel"),
          tension: t("guide.feelsSubtleTension"),
          mood: t("mood.Subtle pressure"),
          text: t("guide.feelsSubtleQuiet"),
          feelsKey: "Subtle pressure",
        },
        {
          emoji: "\u26CF",
          label: t("guide.feelsGrindingLabel"),
          tension: t("guide.feelsGrindingTension"),
          mood: t("mood.Grinding"),
          text: t("guide.feelsGrindingQuiet"),
          feelsKey: "Grinding",
        },
      ],
    },
    {
      zone: t("guide.zoneActive"),
      range: t("guide.zoneActiveRange"),
      color: "#5DCAA5",
      desc: t("guide.zoneActiveDesc"),
      items: [
        {
          emoji: "\u2600\uFE0F",
          label: t("guide.feelsFlowingLabel"),
          tension: t("guide.feelsFlowingTension"),
          mood: t("mood.Flowing"),
          text: t("guide.feelsFlowingActive"),
          feelsKey: "Flowing",
        },
        {
          emoji: "\u26A1",
          label: t("guide.feelsDynamicLabel"),
          tension: t("guide.feelsDynamicTension"),
          mood: t("mood.Dynamic"),
          text: t("guide.feelsDynamicActive"),
          feelsKey: "Dynamic",
        },
        {
          emoji: "\u{1FAA8}",
          label: t("guide.feelsPressuredLabel"),
          tension: t("guide.feelsPressuredTension"),
          mood: t("mood.Pressured"),
          text: t("guide.feelsPressuredActive"),
          feelsKey: "Pressured",
        },
      ],
    },
    {
      zone: t("guide.zoneHot"),
      range: t("guide.zoneHotRange"),
      color: "#E8651A",
      desc: t("guide.zoneHotDesc"),
      items: [
        {
          emoji: "\u{1F305}",
          label: t("guide.feelsExpansiveLabel"),
          tension: t("guide.feelsExpansiveTension"),
          mood: t("mood.Expansive"),
          text: t("guide.feelsExpansiveHot"),
          feelsKey: "Expansive",
        },
        {
          emoji: "\u26C8\uFE0F",
          label: t("guide.feelsChargedLabel"),
          tension: t("guide.feelsChargedTension"),
          mood: t("mood.Charged"),
          text: t("guide.feelsChargedHot"),
          feelsKey: "Charged",
        },
        {
          emoji: "\u{1F525}",
          label: t("guide.feelsIntenseLabel"),
          tension: t("guide.feelsIntenseTension"),
          mood: t("mood.Intense"),
          text: t("guide.feelsIntenseHot"),
          feelsKey: "Intense",
        },
      ],
    },
    {
      zone: t("guide.zoneExtreme"),
      range: t("guide.zoneExtremeRange"),
      color: "#E24B4A",
      desc: t("guide.zoneExtremeDesc"),
      items: [
        {
          emoji: "\u{1F680}",
          label: t("guide.feelsPowerfulLabel"),
          tension: t("guide.feelsPowerfulTension"),
          mood: t("mood.Powerful"),
          text: t("guide.feelsPowerfulExtreme"),
          feelsKey: "Powerful",
        },
        {
          emoji: "\u2694\uFE0F",
          label: t("guide.feelsVolatileLabel"),
          tension: t("guide.feelsVolatileTension"),
          mood: t("mood.Volatile"),
          text: t("guide.feelsVolatileExtreme"),
          feelsKey: "Volatile",
        },
        {
          emoji: "\u{1F4A5}",
          label: t("guide.feelsExplosiveLabel"),
          tension: t("guide.feelsExplosiveTension"),
          mood: t("mood.Explosive"),
          text: t("guide.feelsExplosiveExtreme"),
          feelsKey: "Explosive",
        },
      ],
    },
  ]
}

export function TiiGuide({ onClose }: { onClose: () => void }) {
  const { t } = useLanguage()
  const lang = (t("auth.signIn") === "Войти" ? "ru" : "en") as "en" | "ru"
  const zones = buildZones(t)

  return (
    <div className="settings-overlay" onClick={onClose}>
      <div className="guide-popup" onClick={(e) => e.stopPropagation()}>
        <div className="settings-popup-head">
          <h3>{t("guide.title")}</h3>
          <button type="button" className="settings-close" onClick={onClose}>&times;</button>
        </div>
        <div className="guide-body">

          {/* --- What is TII --- */}
          <section className="guide-section">
            <h4 className="guide-section__title">{t("guide.whatIsTii")}</h4>
            <p className="guide-text" style={{ fontSize: 13, color: "var(--muted)", marginBottom: 4 }}>
              TII &mdash; <strong style={{ color: "var(--ink)" }}>{t("guide.tiiFull")}</strong>
            </p>
            <p className="guide-text">
              {t("guide.tiiDesc")}
            </p>
            <p className="guide-text guide-text--muted">
              {t("guide.tiiCalcDesc")}
            </p>
            <Collapsible title={t("guide.howCalc")} defaultOpen={false}>
              <pre className="guide-formula">{t("guide.formula")}</pre>
              <div className="guide-detail-list">
                <div><strong>{t("guide.aspectWeight")}</strong> &mdash; {t("guide.aspectWeightDesc")}</div>
                <div><strong>{t("guide.orbScore")}</strong> &mdash; {t("guide.orbScoreDesc")}</div>
                <div><strong>{t("guide.planetFactor")}</strong> &mdash; {t("guide.planetFactorDesc")}</div>
                <div><strong>{t("guide.exactness")}</strong> &mdash; {t("guide.exactnessDesc")}</div>
              </div>
              <p className="guide-text guide-text--muted" style={{ marginTop: 10 }}>
                {t("guide.nasaNote")}
              </p>
            </Collapsible>
            <Collapsible title={t("guide.whatsIncluded")} defaultOpen={false}>
              <div className="guide-detail-list">
                <div>
                  <strong>{t("guide.transitPlanets")}</strong> &mdash;{" "}
                  {"\u2609"} {t("planet.Sun")}, {"\u263D"} {t("planet.Moon")}, {"\u263F"} {t("planet.Mercury")}, {"\u2640"} {t("planet.Venus")}, {"\u2642"} {t("planet.Mars")},{" "}
                  {"\u2643"} {t("planet.Jupiter")}, {"\u2644"} {t("planet.Saturn")}, {"\u2645"} {t("planet.Uranus")}, {"\u2646"} {t("planet.Neptune")}, {"\u2647"} {t("planet.Pluto")}
                </div>
                <div>
                  <strong>{t("guide.natalPoints")}</strong> &mdash; {t("guide.natalPointsDesc")}
                </div>
                <div>
                  <strong>{t("guide.aspectsCount")}</strong> &mdash;{" "}
                  {"\u260C"} {t("guide.conjunctionName")}, {"\u260D"} {t("guide.oppositionName")},{" "}
                  {"\u25A1"} {t("guide.squareName")}, {"\u25B3"} {t("guide.trineName")}, {"\u2731"} {t("guide.sextileName")}
                </div>
                <div>
                  <strong>{t("guide.planetWeights")}</strong> &mdash;{" "}
                  {t("guide.planetWeightsDesc")}
                </div>
                <div style={{ marginTop: 8, color: "var(--muted)", fontSize: 12 }}>
                  <strong>{t("guide.notIncluded")}</strong> {t("guide.notIncludedList")}
                </div>
              </div>
            </Collapsible>
          </section>

          {/* --- What is Tension --- */}
          <section className="guide-section">
            <h4 className="guide-section__title">{t("guide.whatIsTension")}</h4>
            <p className="guide-text">
              {t("guide.tensionDesc")}
            </p>
            <div className="guide-tension-scale">
              <div className="guide-tension-row">
                <span className="guide-tension-bar" style={{ background: "#5DCAA5" }} />
                <div>
                  <strong>{t("guide.tensionLow")}</strong>
                  <span className="guide-text--muted"> &mdash; {t("guide.tensionLowDesc")}</span>
                </div>
              </div>
              <div className="guide-tension-row">
                <span className="guide-tension-bar" style={{ background: "#E8A535" }} />
                <div>
                  <strong>{t("guide.tensionMixed")}</strong>
                  <span className="guide-text--muted"> &mdash; {t("guide.tensionMixedDesc")}</span>
                </div>
              </div>
              <div className="guide-tension-row">
                <span className="guide-tension-bar" style={{ background: "#E24B4A" }} />
                <div>
                  <strong>{t("guide.tensionHigh")}</strong>
                  <span className="guide-text--muted"> &mdash; {t("guide.tensionHighDesc")}</span>
                </div>
              </div>
            </div>
          </section>

          {/* --- What is Feels Like --- */}
          <section className="guide-section">
            <h4 className="guide-section__title">{t("guide.whatIsFeels")}</h4>
            <p className="guide-text">
              {t("guide.feelsDesc")}
            </p>
          </section>

          {/* --- Time of Day Context --- */}
          <section className="guide-section">
            <h4 className="guide-section__title">{t("guide.timeModifiers")}</h4>
            <p className="guide-text">
              {t("guide.timeModifiersDesc")}
            </p>
            <div className="guide-time-windows">
              <div className="guide-time-row">
                <span className="guide-time-icon">{"\u{1F305}"}</span>
                <div>
                  <strong>{t("guide.timeMorning")}</strong>
                  <span className="guide-text--muted"> &mdash; {t("guide.timeMorningDesc")}</span>
                </div>
              </div>
              <div className="guide-time-row">
                <span className="guide-time-icon">{"\u2600\uFE0F"}</span>
                <div>
                  <strong>{t("guide.timeAfternoon")}</strong>
                  <span className="guide-text--muted"> &mdash; {t("guide.timeAfternoonDesc")}</span>
                </div>
              </div>
              <div className="guide-time-row">
                <span className="guide-time-icon">{"\u{1F307}"}</span>
                <div>
                  <strong>{t("guide.timeEvening")}</strong>
                  <span className="guide-text--muted"> &mdash; {t("guide.timeEveningDesc")}</span>
                </div>
              </div>
              <div className="guide-time-row">
                <span className="guide-time-icon">{"\u{1F319}"}</span>
                <div>
                  <strong>{t("guide.timeNight")}</strong>
                  <span className="guide-text--muted"> &mdash; {t("guide.timeNightDesc")}</span>
                </div>
              </div>
            </div>
          </section>

          {/* --- Intensity Zones --- */}
          <section className="guide-section">
            <h4 className="guide-section__title">{t("guide.intensityZones")}</h4>
            <p className="guide-text guide-text--muted" style={{ marginBottom: 12 }}>
              {t("guide.zonesSubtitle")}
            </p>
            {zones.map((z) => (
              <ZoneSection key={z.zone} {...z} lang={lang} />
            ))}
          </section>

          {/* ===== Reference Guide ===== */}

          <section className="guide-section">
            <h4 className="guide-section__title">{t("guide.planetsTitle")}</h4>
            <Collapsible title={t("guide.majorPlanets")}>
              <div className="ref-list">
                {([
                  ["\u2609", t("planet.Sun"), t("guide.sunDesc")],
                  ["\u263D", t("planet.Moon"), t("guide.moonDesc")],
                  ["\u263F", t("planet.Mercury"), t("guide.mercuryDesc")],
                  ["\u2640", t("planet.Venus"), t("guide.venusDesc")],
                  ["\u2642", t("planet.Mars"), t("guide.marsDesc")],
                  ["\u2643", t("planet.Jupiter"), t("guide.jupiterDesc")],
                  ["\u2644", t("planet.Saturn"), t("guide.saturnDesc")],
                  ["\u2645", t("planet.Uranus"), t("guide.uranusDesc")],
                  ["\u2646", t("planet.Neptune"), t("guide.neptuneDesc")],
                  ["\u2647", t("planet.Pluto"), t("guide.plutoDesc")],
                ] as const).map(([glyph, name, desc]) => (
                  <div key={name} className="ref-item">
                    <span className="ref-glyph">{glyph}</span>
                    <div className="ref-body">
                      <strong>{name}</strong>
                      <span className="ref-desc">{desc}</span>
                    </div>
                  </div>
                ))}
              </div>
            </Collapsible>
            <Collapsible title={t("guide.otherPoints")}>
              <div className="ref-list">
                {([
                  ["\u260A", t("planet.North Node"), t("guide.northNodeDesc")],
                  ["\u260B", t("planet.South Node"), t("guide.southNodeDesc")],
                  ["\u26B7", t("planet.Chiron"), t("guide.chironDesc")],
                  ["\u26B8", t("planet.Lilith"), t("guide.lilithDesc")],
                  ["\u2297", t("planet.Part of Fortune"), t("guide.pofDesc")],
                  ["\u22C1", t("planet.Vertex"), t("guide.vertexDesc")],
                  ["\u263E", "Selena", t("guide.selenaDesc")],
                ] as const).map(([glyph, name, desc]) => (
                  <div key={name} className="ref-item">
                    <span className="ref-glyph">{glyph}</span>
                    <div className="ref-body">
                      <strong>{name}</strong>
                      <span className="ref-desc">{desc}</span>
                    </div>
                  </div>
                ))}
              </div>
            </Collapsible>
          </section>

          <section className="guide-section">
            <h4 className="guide-section__title">{t("guide.signsTitle")}</h4>
            <p className="guide-text guide-text--muted" style={{ marginBottom: 10 }}>
              {t("guide.signsSubtitle")}
            </p>
            <Collapsible title={t("guide.allSigns")}>
              <div className="ref-list">
                {([
                  ["\u2648", t("sign.Aries"), "fire", t("guide.fire"), t("guide.cardinal"), t("guide.ariesDesc"), t("guide.ariesMotto")],
                  ["\u2649", t("sign.Taurus"), "earth", t("guide.earth"), t("guide.fixed"), t("guide.taurusDesc"), t("guide.taurusMotto")],
                  ["\u264A", t("sign.Gemini"), "air", t("guide.air"), t("guide.mutable"), t("guide.geminiDesc"), t("guide.geminiMotto")],
                  ["\u264B", t("sign.Cancer"), "water", t("guide.water"), t("guide.cardinal"), t("guide.cancerDesc"), t("guide.cancerMotto")],
                  ["\u264C", t("sign.Leo"), "fire", t("guide.fire"), t("guide.fixed"), t("guide.leoDesc"), t("guide.leoMotto")],
                  ["\u264D", t("sign.Virgo"), "earth", t("guide.earth"), t("guide.mutable"), t("guide.virgoDesc"), t("guide.virgoMotto")],
                  ["\u264E", t("sign.Libra"), "air", t("guide.air"), t("guide.cardinal"), t("guide.libraDesc"), t("guide.libraMotto")],
                  ["\u264F", t("sign.Scorpio"), "water", t("guide.water"), t("guide.fixed"), t("guide.scorpioDesc"), t("guide.scorpioMotto")],
                  ["\u2650", t("sign.Sagittarius"), "fire", t("guide.fire"), t("guide.mutable"), t("guide.sagittariusDesc"), t("guide.sagittariusMotto")],
                  ["\u2651", t("sign.Capricorn"), "earth", t("guide.earth"), t("guide.cardinal"), t("guide.capricornDesc"), t("guide.capricornMotto")],
                  ["\u2652", t("sign.Aquarius"), "air", t("guide.air"), t("guide.fixed"), t("guide.aquariusDesc"), t("guide.aquariusMotto")],
                  ["\u2653", t("sign.Pisces"), "water", t("guide.water"), t("guide.mutable"), t("guide.piscesDesc"), t("guide.piscesMotto")],
                ] as const).map(([glyph, name, elKey, element, quality, desc, motto]) => (
                  <div key={name} className="ref-item">
                    <span className="ref-glyph">{glyph}</span>
                    <div className="ref-body">
                      <div className="ref-sign-head">
                        <strong>{name}</strong>
                        <span className={`ref-element ref-element--${elKey}`}>{element}</span>
                        <span className="ref-quality">{quality}</span>
                      </div>
                      <span className="ref-desc">{desc} <em>&ldquo;{motto}&rdquo;</em></span>
                    </div>
                  </div>
                ))}
              </div>
            </Collapsible>
          </section>

          <section className="guide-section">
            <h4 className="guide-section__title">{t("guide.aspectsTitle")}</h4>
            <p className="guide-text guide-text--muted" style={{ marginBottom: 10 }}>
              {t("guide.aspectsSubtitle")}
            </p>
            <Collapsible title={t("guide.allAspects")}>
              <div className="ref-list">
                <div className="ref-item">
                  <span className="ref-glyph">{"\u260C"}</span>
                  <div className="ref-body">
                    <strong>{t("guide.conjunctionName")}</strong>
                    <span className="ref-desc">{t("guide.conjunctionDesc")}</span>
                  </div>
                </div>
                <div className="ref-item">
                  <span className="ref-glyph">{"\u26B9"}</span>
                  <div className="ref-body">
                    <strong>{t("guide.sextileName")}</strong>
                    <span className="ref-desc">{t("guide.sextileDesc")}</span>
                  </div>
                </div>
                <div className="ref-item">
                  <span className="ref-glyph">{"\u25A1"}</span>
                  <div className="ref-body">
                    <strong>{t("guide.squareName")}</strong>
                    <span className="ref-desc">{t("guide.squareDesc")}</span>
                  </div>
                </div>
                <div className="ref-item">
                  <span className="ref-glyph">{"\u25B3"}</span>
                  <div className="ref-body">
                    <strong>{t("guide.trineName")}</strong>
                    <span className="ref-desc">{t("guide.trineDesc")}</span>
                  </div>
                </div>
                <div className="ref-item">
                  <span className="ref-glyph">{"\u260D"}</span>
                  <div className="ref-body">
                    <strong>{t("guide.oppositionName")}</strong>
                    <span className="ref-desc">{t("guide.oppositionDesc")}</span>
                  </div>
                </div>
              </div>
              <p className="guide-text guide-text--muted" style={{ marginTop: 12, fontStyle: "italic" }}>
                {t("guide.aspectsNote")}
              </p>
            </Collapsible>
          </section>

          <section className="guide-section">
            <h4 className="guide-section__title">{t("guide.housesTitle")}</h4>
            <p className="guide-text guide-text--muted" style={{ marginBottom: 10 }}>
              {t("guide.housesSubtitle")}
            </p>
            <Collapsible title={t("guide.allHouses")}>
              <div className="ref-list">
                {([
                  ["1", t("guide.house1")],
                  ["2", t("guide.house2")],
                  ["3", t("guide.house3")],
                  ["4", t("guide.house4")],
                  ["5", t("guide.house5")],
                  ["6", t("guide.house6")],
                  ["7", t("guide.house7")],
                  ["8", t("guide.house8")],
                  ["9", t("guide.house9")],
                  ["10", t("guide.house10")],
                  ["11", t("guide.house11")],
                  ["12", t("guide.house12")],
                ] as const).map(([num, desc]) => (
                  <div key={num} className="ref-item">
                    <span className="ref-glyph ref-house-num">{num}</span>
                    <div className="ref-body">
                      <span className="ref-desc">{desc}</span>
                    </div>
                  </div>
                ))}
              </div>
            </Collapsible>
          </section>

          <section className="guide-section">
            <h4 className="guide-section__title">{t("guide.strengthTitle")}</h4>
            <p className="guide-text guide-text--muted" style={{ marginBottom: 10 }}>
              {t("guide.strengthSubtitle")}
            </p>
            <Collapsible title={t("guide.strengthLevels")}>
              <div className="ref-list">
                <div className="ref-item">
                  <div className="ref-item__head">
                    <span className="natal-asp__str natal-asp__str--exact">{t("strength.exact")}</span>
                    <strong>{t("guide.exactOrb")}</strong>
                  </div>
                  <span className="ref-desc">{t("guide.exactDesc")}</span>
                </div>
                <div className="ref-item">
                  <div className="ref-item__head">
                    <span className="natal-asp__str natal-asp__str--strong">{t("strength.strong")}</span>
                    <strong>{t("guide.strongOrb")}</strong>
                  </div>
                  <span className="ref-desc">{t("guide.strongDesc")}</span>
                </div>
                <div className="ref-item">
                  <div className="ref-item__head">
                    <span className="natal-asp__str natal-asp__str--moderate">{t("strength.moderate")}</span>
                    <strong>{t("guide.moderateOrb")}</strong>
                  </div>
                  <span className="ref-desc">{t("guide.moderateDesc")}</span>
                </div>
                <div className="ref-item">
                  <div className="ref-item__head">
                    <span className="natal-asp__str natal-asp__str--wide">{t("strength.wide")}</span>
                    <strong>{t("guide.wideOrb")}</strong>
                  </div>
                  <span className="ref-desc">{t("guide.wideDesc")}</span>
                </div>
              </div>
              <p className="guide-text guide-text--muted" style={{ marginTop: 12, fontStyle: "italic" }}>
                {t("guide.applyingSep")}
              </p>
            </Collapsible>
          </section>

          <section className="guide-section">
            <h4 className="guide-section__title">{t("guide.symbolsTitle")}</h4>
            <div className="ref-list">
              <div className="ref-item"><span className="ref-glyph">{"\u24C7"}</span><div className="ref-body"><strong>{t("guide.retrograde")}</strong><span className="ref-desc">{t("guide.retrogradeDesc")}</span></div></div>
              <div className="ref-item"><span className="ref-glyph">{"\u25B3"}</span><div className="ref-body"><strong>{t("guide.houseNumber")}</strong><span className="ref-desc">{t("guide.houseNumberDesc")}</span></div></div>
              <div className="ref-item"><span className="ref-glyph">AC</span><div className="ref-body"><strong>{t("guide.ascendant")}</strong><span className="ref-desc">{t("guide.ascendantDesc")}</span></div></div>
              <div className="ref-item"><span className="ref-glyph">DC</span><div className="ref-body"><strong>{t("guide.descendant")}</strong><span className="ref-desc">{t("guide.descendantDesc")}</span></div></div>
              <div className="ref-item"><span className="ref-glyph">MC</span><div className="ref-body"><strong>{t("guide.midheaven")}</strong><span className="ref-desc">{t("guide.midheavenDesc")}</span></div></div>
              <div className="ref-item"><span className="ref-glyph">IC</span><div className="ref-body"><strong>{t("guide.imumCoeli")}</strong><span className="ref-desc">{t("guide.imumCoeliDesc")}</span></div></div>
            </div>
          </section>

        </div>
      </div>
    </div>
  )
}
