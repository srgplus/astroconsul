import { useState } from "react"

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

function ZoneSection({ zone, range, color, desc, items }: {
  zone: string; range: string; color: string; desc: string
  items: readonly { emoji: string; label: string; tension: string; text: string }[]
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
          {items.map(({ emoji, label, tension, text }) => (
            <div key={label} className="guide-feels">
              <div className="guide-feels__head">
                <span className="guide-feels__emoji">{emoji}</span>
                <strong>{label}</strong>
                <span className="guide-text--muted">({tension})</span>
              </div>
              <p className="guide-feels__text">{text}</p>
            </div>
          ))}
        </div>
      ) : null}
    </div>
  )
}

const ZONES = [
  {
    zone: "Quiet Zone",
    range: "0\u201325\u00B0",
    color: "#4A90D9",
    desc: "Low planetary activity. Few or weak aspects to your natal chart.",
    items: [
      {
        emoji: "\u2601\uFE0F",
        label: "Calm",
        tension: "tension <30%",
        text: "Quiet day with gentle energy. Good for rest, reflection, routine tasks. Nothing demanding your attention cosmically.",
      },
      {
        emoji: "\u{1F32B}\uFE0F",
        label: "Subtle pressure",
        tension: "tension 30\u201360%",
        text: "Outwardly quiet but something feels slightly off. Minor friction beneath the surface. Pay attention to small signals.",
      },
      {
        emoji: "\u26CF",
        label: "Grinding",
        tension: "tension >60%",
        text: "Low energy but what\u2019s there is heavy. Like walking through mud. Not many events, but they feel difficult. Take it slow.",
      },
    ],
  },
  {
    zone: "Active Zone",
    range: "25\u201355\u00B0",
    color: "#5DCAA5",
    desc: "Moderate planetary activity. Several aspects engaging your chart.",
    items: [
      {
        emoji: "\u2600\uFE0F",
        label: "Flowing",
        tension: "tension <30%",
        text: "Good active day. Energy moves smoothly. Ideas come easily, interactions feel natural. Best day type for creative work and socializing.",
      },
      {
        emoji: "\u26A1",
        label: "Dynamic",
        tension: "tension 30\u201360%",
        text: "Busy, stimulating day with a mix of support and challenge. Things are happening. Stay flexible and respond to opportunities.",
      },
      {
        emoji: "\u{1FAA8}",
        label: "Pressured",
        tension: "tension >60%",
        text: "Active day but everything feels heavy. Like a workout \u2014 productive but demanding. Pace yourself, prioritize what matters.",
      },
    ],
  },
  {
    zone: "Hot Zone",
    range: "55\u201380\u00B0",
    color: "#E8651A",
    desc: "High planetary activity. Multiple significant aspects, some exact.",
    items: [
      {
        emoji: "\u{1F305}",
        label: "Expansive",
        tension: "tension <30%",
        text: "Big energy day with doors opening. Opportunities arrive naturally. Good for launches, big conversations, bold moves. Say yes.",
      },
      {
        emoji: "\u26C8\uFE0F",
        label: "Charged",
        tension: "tension 30\u201360%",
        text: "Intense energy building up. Like a storm gathering \u2014 powerful but unpredictable. Important decisions may arise. Stay centered.",
      },
      {
        emoji: "\u{1F525}",
        label: "Intense",
        tension: "tension >60%",
        text: "Hot day with strong pressure. Conflicts and breakthroughs both possible. Emotions run high. Channel the energy, don\u2019t let it control you.",
      },
    ],
  },
  {
    zone: "Extreme Zone",
    range: "80\u2013100\u00B0",
    color: "#E24B4A",
    desc: "Rare. Multiple exact aspects including outer planets. Happens a few times per year.",
    items: [
      {
        emoji: "\u{1F680}",
        label: "Powerful",
        tension: "tension <30%",
        text: "Maximum energy with minimal friction. Rare launch window. Whatever you start today has enormous momentum behind it.",
      },
      {
        emoji: "\u2694\uFE0F",
        label: "Volatile",
        tension: "tension 30\u201360%",
        text: "Extreme energy, unpredictable direction. Major shifts possible. Stay alert, avoid impulsive decisions. Big things are moving.",
      },
      {
        emoji: "\u{1F4A5}",
        label: "Explosive",
        tension: "tension >60%",
        text: "Maximum intensity, maximum pressure. Life-changing moments. Everything amplified. Not good or bad \u2014 just very, very powerful.",
      },
    ],
  },
] as const

export function TiiGuide({ onClose }: { onClose: () => void }) {
  return (
    <div className="settings-overlay" onClick={onClose}>
      <div className="guide-popup" onClick={(e) => e.stopPropagation()}>
        <div className="settings-popup-head">
          <h3>How It Works</h3>
          <button type="button" className="settings-close" onClick={onClose}>&times;</button>
        </div>
        <div className="guide-body">

          {/* --- What is TII --- */}
          <section className="guide-section">
            <h4 className="guide-section__title">What is TII?</h4>
            <p className="guide-text" style={{ fontSize: 13, color: "var(--muted)", marginBottom: 4 }}>
              TII &mdash; <strong style={{ color: "var(--ink)" }}>Transit Influence Index</strong>
            </p>
            <p className="guide-text">
              TII measures how much planetary activity is affecting your natal chart right now.
              Think of it as a thermometer for cosmic weather &mdash; higher number means more is happening.
            </p>
            <p className="guide-text guide-text--muted">
              It&rsquo;s calculated from real astronomical data: the positions of planets, the angles
              between them, and how precisely they align with your birth chart.
            </p>
            <Collapsible title="How it's calculated" defaultOpen={false}>
              <pre className="guide-formula">{`TII = \u03A3 (aspect_weight \u00D7 orb_score \u00D7 planet_factor \u00D7 exactness_bonus)`}</pre>
              <div className="guide-detail-list">
                <div><strong>Aspect weight</strong> &mdash; conjunction = 10, opposition = 8, square = 7, trine = 6, sextile = 5</div>
                <div><strong>Orb score</strong> &mdash; min(10, 1/(orb + 0.1)) &mdash; tighter aspect = higher score</div>
                <div><strong>Planet factor</strong> &mdash; Moon = 0.5, Sun&ndash;Mars = 1.0, Jupiter&ndash;Saturn = 1.3, Uranus&ndash;Pluto = 1.5</div>
                <div><strong>Exactness</strong> &mdash; partile (&lt;0.1&deg;) = +50%, exact (&lt;1&deg;) = +20%</div>
              </div>
              <p className="guide-text guide-text--muted" style={{ marginTop: 10 }}>
                Every number in TII can be traced back to actual planetary positions verified by NASA JPL ephemeris data.
              </p>
            </Collapsible>
            <Collapsible title="What's included" defaultOpen={false}>
              <div className="guide-detail-list">
                <div>
                  <strong>Transit planets (10)</strong> &mdash;{" "}
                  {"\u2609"} Sun, {"\u263D"} Moon, {"\u263F"} Mercury, {"\u2640"} Venus, {"\u2642"} Mars,{" "}
                  {"\u2643"} Jupiter, {"\u2644"} Saturn, {"\u2645"} Uranus, {"\u2646"} Neptune, {"\u2647"} Pluto
                </div>
                <div>
                  <strong>Natal points (12)</strong> &mdash; Same 10 planets + ASC + MC
                </div>
                <div>
                  <strong>Aspects (5)</strong> &mdash;{" "}
                  {"\u260C"} Conjunction (8&deg;), {"\u260D"} Opposition (8&deg;),{" "}
                  {"\u25A1"} Square (6&deg;), {"\u25B3"} Trine (6&deg;), {"\u2731"} Sextile (4&deg;)
                </div>
                <div>
                  <strong>Planet weights</strong> &mdash;{" "}
                  Outer planets (Uranus&ndash;Pluto) count 1.5&times; more &mdash; slower and rarer.{" "}
                  Jupiter &amp; Saturn = 1.3&times;. Moon = 0.5&times; (moves fast, changes daily).
                </div>
                <div style={{ marginTop: 8, color: "var(--muted)", fontSize: 12 }}>
                  <strong>Not included:</strong> Chiron, Lilith, Selena, Nodes, Part of Fortune, Vertex, DC, IC
                </div>
              </div>
            </Collapsible>
          </section>

          {/* --- What is Tension --- */}
          <section className="guide-section">
            <h4 className="guide-section__title">What is Tension?</h4>
            <p className="guide-text">
              Tension shows the balance between challenging aspects (squares &#x25A1; and oppositions &#x260D;)
              and supportive aspects (trines &#x25B3; and sextiles &#x26B9;). High tension doesn&rsquo;t mean bad &mdash;
              it means more friction and pressure, which can drive action and breakthroughs.
            </p>
            <div className="guide-tension-scale">
              <div className="guide-tension-row">
                <span className="guide-tension-bar" style={{ background: "#5DCAA5" }} />
                <div>
                  <strong>Low (0&ndash;30%)</strong>
                  <span className="guide-text--muted"> &mdash; Mostly supportive aspects. Energy flows easily.</span>
                </div>
              </div>
              <div className="guide-tension-row">
                <span className="guide-tension-bar" style={{ background: "#E8A535" }} />
                <div>
                  <strong>Mixed (30&ndash;60%)</strong>
                  <span className="guide-text--muted"> &mdash; Balance of challenge and support. Dynamic day.</span>
                </div>
              </div>
              <div className="guide-tension-row">
                <span className="guide-tension-bar" style={{ background: "#E24B4A" }} />
                <div>
                  <strong>High (60&ndash;100%)</strong>
                  <span className="guide-text--muted"> &mdash; Dominated by challenging aspects. High pressure, high potential.</span>
                </div>
              </div>
            </div>
          </section>

          {/* --- What is Feels Like --- */}
          <section className="guide-section">
            <h4 className="guide-section__title">What does Feels Like mean?</h4>
            <p className="guide-text">
              Just like weather has a &ldquo;Feels Like&rdquo; temperature (actual temp adjusted for wind chill),
              we combine TII with Tension to describe how the day actually feels.
              Same intensity can feel very different depending on whether the energy is flowing or pressured.
            </p>
          </section>

          {/* --- Intensity Zones --- */}
          <section className="guide-section">
            <h4 className="guide-section__title">Intensity Zones</h4>
            <p className="guide-text guide-text--muted" style={{ marginBottom: 12 }}>
              4 zones &times; 3 tension levels = 12 unique states. Tap a zone to see details.
            </p>
            {ZONES.map((z) => (
              <ZoneSection key={z.zone} {...z} />
            ))}
          </section>

          {/* ===== Reference Guide ===== */}

          <section className="guide-section">
            <h4 className="guide-section__title">Planets &mdash; what each one governs</h4>
            <Collapsible title="Major planets">
              <div className="ref-list">
                {([
                  ["\u2609", "Sun", "Your core identity, ego, vitality. What drives you."],
                  ["\u263D", "Moon", "Emotions, instincts, inner world. How you feel."],
                  ["\u263F", "Mercury", "Communication, thinking, learning. How you process information."],
                  ["\u2640", "Venus", "Love, beauty, values, money. What you attract."],
                  ["\u2642", "Mars", "Action, drive, ambition, anger. How you pursue goals."],
                  ["\u2643", "Jupiter", "Growth, luck, expansion, wisdom. Where life opens up."],
                  ["\u2644", "Saturn", "Structure, discipline, limits, lessons. Where you must earn it."],
                  ["\u2645", "Uranus", "Change, rebellion, innovation, surprises. Where you break free."],
                  ["\u2646", "Neptune", "Dreams, intuition, illusion, spirituality. Where boundaries dissolve."],
                  ["\u2647", "Pluto", "Transformation, power, death/rebirth. Where you evolve deeply."],
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
            <Collapsible title="Other points">
              <div className="ref-list">
                {([
                  ["\u260A", "North Node", "Your karmic direction. Where you\u2019re growing toward."],
                  ["\u260B", "South Node", "Your karmic past. What you\u2019re releasing."],
                  ["\u26B7", "Chiron", "Your deepest wound and healing gift."],
                  ["\u26B8", "Lilith", "Your shadow side. Suppressed power."],
                  ["\u2297", "Part of Fortune", "Where luck and talent naturally flow."],
                  ["\u22C1", "Vertex", "Fated encounters. Points of destiny."],
                  ["\u263E", "Selena", "(White Moon) Your guardian angel point."],
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
            <h4 className="guide-section__title">Zodiac Signs &mdash; 12 archetypes of energy</h4>
            <p className="guide-text guide-text--muted" style={{ marginBottom: 10 }}>
              Each sign has an element (Fire/Earth/Air/Water) and quality (Cardinal/Fixed/Mutable).
            </p>
            <Collapsible title="All 12 signs">
              <div className="ref-list">
                {([
                  ["\u2648", "Aries", "Fire", "Cardinal", "Initiator. Bold, direct, competitive.", "I act."],
                  ["\u2649", "Taurus", "Earth", "Fixed", "Builder. Patient, sensual, stubborn.", "I have."],
                  ["\u264A", "Gemini", "Air", "Mutable", "Communicator. Curious, adaptable, restless.", "I think."],
                  ["\u264B", "Cancer", "Water", "Cardinal", "Nurturer. Emotional, protective, intuitive.", "I feel."],
                  ["\u264C", "Leo", "Fire", "Fixed", "Creator. Confident, dramatic, generous.", "I shine."],
                  ["\u264D", "Virgo", "Earth", "Mutable", "Analyst. Practical, precise, helpful.", "I improve."],
                  ["\u264E", "Libra", "Air", "Cardinal", "Diplomat. Harmonious, fair, indecisive.", "I balance."],
                  ["\u264F", "Scorpio", "Water", "Fixed", "Transformer. Intense, deep, secretive.", "I transform."],
                  ["\u2650", "Sagittarius", "Fire", "Mutable", "Explorer. Optimistic, free, philosophical.", "I seek."],
                  ["\u2651", "Capricorn", "Earth", "Cardinal", "Achiever. Ambitious, disciplined, strategic.", "I build."],
                  ["\u2652", "Aquarius", "Air", "Fixed", "Innovator. Independent, humanitarian, eccentric.", "I change."],
                  ["\u2653", "Pisces", "Water", "Mutable", "Dreamer. Compassionate, imaginative, boundless.", "I believe."],
                ] as const).map(([glyph, name, element, quality, desc, motto]) => (
                  <div key={name} className="ref-item">
                    <span className="ref-glyph">{glyph}</span>
                    <div className="ref-body">
                      <div className="ref-sign-head">
                        <strong>{name}</strong>
                        <span className={`ref-element ref-element--${element.toLowerCase()}`}>{element}</span>
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
            <h4 className="guide-section__title">Aspects &mdash; how planets talk to each other</h4>
            <p className="guide-text guide-text--muted" style={{ marginBottom: 10 }}>
              Aspects are geometric angles between planets. They define the nature of planetary interaction.
            </p>
            <Collapsible title="All 5 major aspects">
              <div className="ref-list">
                <div className="ref-item">
                  <span className="ref-glyph">{"\u260C"}</span>
                  <div className="ref-body">
                    <strong>Conjunction (0&deg;)</strong>
                    <span className="ref-desc">Fusion. Two planets merge energy. Powerful amplification. Neither easy nor hard &mdash; depends on the planets involved.</span>
                  </div>
                </div>
                <div className="ref-item">
                  <span className="ref-glyph">{"\u26B9"}</span>
                  <div className="ref-body">
                    <strong>Sextile (60&deg;)</strong>
                    <span className="ref-desc">Opportunity. Gentle support between planets. Talent that activates with small effort. Easy but requires initiative.</span>
                  </div>
                </div>
                <div className="ref-item">
                  <span className="ref-glyph">{"\u25A1"}</span>
                  <div className="ref-body">
                    <strong>Square (90&deg;)</strong>
                    <span className="ref-desc">Tension. Friction that forces action. Challenging but productive. The engine of growth. Creates results through pressure.</span>
                  </div>
                </div>
                <div className="ref-item">
                  <span className="ref-glyph">{"\u25B3"}</span>
                  <div className="ref-body">
                    <strong>Trine (120&deg;)</strong>
                    <span className="ref-desc">Flow. Natural harmony between planets. Effortless talent. Can be so easy you take it for granted.</span>
                  </div>
                </div>
                <div className="ref-item">
                  <span className="ref-glyph">{"\u260D"}</span>
                  <div className="ref-body">
                    <strong>Opposition (180&deg;)</strong>
                    <span className="ref-desc">Polarity. Two planets face each other. Awareness through contrast. Relationships, projection, finding balance.</span>
                  </div>
                </div>
              </div>
              <p className="guide-text guide-text--muted" style={{ marginTop: 12, fontStyle: "italic" }}>
                Squares and oppositions are not &ldquo;bad.&rdquo; They create the tension that drives achievement.
                Trines and sextiles are not &ldquo;good.&rdquo; Without challenge, talent stays dormant.
              </p>
            </Collapsible>
          </section>

          <section className="guide-section">
            <h4 className="guide-section__title">Houses &mdash; 12 areas of life</h4>
            <p className="guide-text guide-text--muted" style={{ marginBottom: 10 }}>
              Houses are sections of the sky at the moment of birth. Each governs a specific life area.
              When a transit activates a house, that area of life becomes active.
            </p>
            <Collapsible title="All 12 houses">
              <div className="ref-list">
                {([
                  ["1", "Self, appearance, identity. How the world sees you. Your mask."],
                  ["2", "Money, possessions, values. What you own and what you value."],
                  ["3", "Communication, siblings, short trips. Daily interactions and learning."],
                  ["4", "Home, family, roots, privacy. Your foundation and inner sanctuary."],
                  ["5", "Creativity, romance, children, fun. What you create and enjoy."],
                  ["6", "Health, daily routines, work, service. How you maintain yourself."],
                  ["7", "Relationships, partnerships, marriage. The people who mirror you."],
                  ["8", "Transformation, shared resources, intimacy, death/rebirth. Deep merging."],
                  ["9", "Travel, philosophy, higher education, beliefs. Expanding your world."],
                  ["10", "Career, reputation, public image, ambition. Your legacy."],
                  ["11", "Friends, community, hopes, humanitarian goals. Your tribe."],
                  ["12", "Subconscious, spirituality, hidden enemies, isolation. What\u2019s invisible."],
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
            <h4 className="guide-section__title">Aspect Strength &mdash; how close is the alignment</h4>
            <p className="guide-text guide-text--muted" style={{ marginBottom: 10 }}>
              Orb is the distance from perfect alignment. Smaller orb = stronger effect.
            </p>
            <Collapsible title="Strength levels">
              <div className="ref-list">
                <div className="ref-item">
                  <span className="natal-asp__str natal-asp__str--exact">EXACT</span>
                  <div className="ref-body">
                    <strong>Orb &lt; 0.3&deg;</strong>
                    <span className="ref-desc">Planets are almost perfectly aligned. Maximum intensity. Like standing directly under the spotlight.</span>
                  </div>
                </div>
                <div className="ref-item">
                  <span className="natal-asp__str natal-asp__str--strong">STRONG</span>
                  <div className="ref-body">
                    <strong>Orb 0.3&deg;&ndash;1.0&deg;</strong>
                    <span className="ref-desc">Very close alignment. Clearly felt influence. The effect is strong and unmistakable.</span>
                  </div>
                </div>
                <div className="ref-item">
                  <span className="natal-asp__str natal-asp__str--moderate">MODERATE</span>
                  <div className="ref-body">
                    <strong>Orb 1.0&deg;&ndash;2.0&deg;</strong>
                    <span className="ref-desc">Noticeable influence but softer. Background effect that colors the day without dominating it.</span>
                  </div>
                </div>
                <div className="ref-item">
                  <span className="natal-asp__str natal-asp__str--wide">WIDE</span>
                  <div className="ref-body">
                    <strong>Orb &gt; 2.0&deg;</strong>
                    <span className="ref-desc">Faint influence. The aspect is entering or leaving range. Subtle background energy.</span>
                  </div>
                </div>
              </div>
              <p className="guide-text guide-text--muted" style={{ marginTop: 12, fontStyle: "italic" }}>
                APPLYING means the aspect is getting tighter &mdash; building toward peak.
                SEPARATING means the aspect already peaked and is fading.
                Applying aspects are generally felt more strongly.
              </p>
            </Collapsible>
          </section>

          <section className="guide-section">
            <h4 className="guide-section__title">Symbols</h4>
            <div className="ref-list">
              <div className="ref-item"><span className="ref-glyph">{"\u24C7"}</span><div className="ref-body"><strong>Retrograde</strong><span className="ref-desc">Planet appears to move backward. Energy turns inward, delays and revisions.</span></div></div>
              <div className="ref-item"><span className="ref-glyph">{"\u25B3"}</span><div className="ref-body"><strong>House number</strong><span className="ref-desc">e.g. {"\u25B3"}4 means the transit activates your 4th house (home, family).</span></div></div>
              <div className="ref-item"><span className="ref-glyph">AC</span><div className="ref-body"><strong>Ascendant</strong><span className="ref-desc">Your rising sign. The mask you wear. How others first perceive you.</span></div></div>
              <div className="ref-item"><span className="ref-glyph">DC</span><div className="ref-body"><strong>Descendant</strong><span className="ref-desc">Opposite your Ascendant. What you seek in partners and relationships.</span></div></div>
              <div className="ref-item"><span className="ref-glyph">MC</span><div className="ref-body"><strong>Midheaven</strong><span className="ref-desc">Top of the chart. Your career, public reputation, and life direction.</span></div></div>
              <div className="ref-item"><span className="ref-glyph">IC</span><div className="ref-body"><strong>Imum Coeli</strong><span className="ref-desc">Bottom of the chart. Your roots, home, private inner world.</span></div></div>
            </div>
          </section>

        </div>
      </div>
    </div>
  )
}
