---
name: big3me-content-design
description: Generate branded visual content cards for big3.me blog posts, Instagram carousels, social media graphics, and news articles. Use this skill whenever the user asks to create visual cards, carousel slides, social media graphics, blog post visuals, transit highlight cards, aspect diagrams, natal chart cards, cosmic weather graphics, celebrity transit visuals, or any branded content for big3.me. Also trigger when the user mentions Instagram posts, story cards, carousel generation, content repurposing from blog to social, or visual templates for astrology content. This skill covers the complete big3.me visual design system: color palettes (dark and light), typography, component patterns, slide layouts, and data visualization for astrological content.
---
# big3.me Content Design System
Generate branded visual content from big3.me blog posts and transit data. All visuals follow the big3.me design system and can be repurposed across platforms.
---
## 1. Brand Foundation
### Color System
**Dark Theme (Primary)**
```css
--bg-dark: #0a0a0b;
--surface-dark: #131316;
--surface-2-dark: #1a1a1f;
--border-dark: rgba(255, 255, 255, 0.06);
--text-dark: #e8e8ec;
--text-muted-dark: #8e8e96;
```
**Light Theme (Secondary)**
```css
--bg-light: #faf9f7;
--surface-light: #ffffff;
--surface-2-light: #f2f0ed;
--border-light: rgba(0, 0, 0, 0.08);
--text-light: #1a1a1f;
--text-muted-light: #6e6e76;
```
**Accent Colors (same in both themes)**
```css
--accent-purple: #a78bfa;
--accent-purple-glow: rgba(167, 139, 250, 0.15);
--accent-pink: #f472b6;
--accent-pink-glow: rgba(244, 114, 182, 0.15);
--accent-green: #34d399;       /* EXACT aspects */
--accent-green-glow: rgba(52, 211, 153, 0.12);
--accent-orange: #fb923c;      /* STRONG aspects */
--accent-orange-glow: rgba(251, 146, 60, 0.12);
--accent-blue: #60a5fa;        /* APPLYING aspects */
--accent-blue-glow: rgba(96, 165, 250, 0.12);
--accent-gold: #fbbf24;
--accent-red: #f87171;
```
**Aspect Strength Colors**
| Strength | Color | Badge BG | Badge Text |
|----------|-------|----------|------------|
| EXACT (0-1°) | green | rgba(52,211,153,0.12) | #34d399 |
| STRONG (1-3°) | orange | rgba(251,146,60,0.12) | #fb923c |
| APPLYING (3-5°) | blue | rgba(96,165,250,0.12) | #60a5fa |
| SEPARATING | muted | rgba(255,255,255,0.04) | #8e8e96 |
**Planet Colors (for accent dots/circles)**
| Planet | Color | Usage |
|--------|-------|-------|
| Sun | #fbbf24 (gold) | Core identity aspects |
| Moon | #e8e8ec (silver) | Emotional aspects |
| Mercury | #60a5fa (blue) | Communication aspects |
| Venus | #f472b6 (pink) | Love/beauty aspects |
| Mars | #f87171 (red) | Action/drive aspects |
| Jupiter | #a78bfa (purple) | Expansion aspects |
| Saturn | #8e8e96 (gray) | Structure/discipline |
| Uranus | #34d399 (teal) | Change/innovation |
| Neptune | #818cf8 (indigo) | Intuition/dreams |
| Pluto | #c084fc (deep purple) | Transformation |
### Typography
**Primary Headlines:** 'Instrument Serif', Georgia, serif
- Weight: 400 (normal)
- Use for: slide titles, article names, big numbers, CTA headlines
**Body/UI:** 'DM Sans', system-ui, sans-serif
- Weight: 300 (light), 400 (regular), 500 (medium), 600 (semibold), 700 (bold)
- Use for: body text, labels, badges, data, navigation
**Monospace (data):** 'JetBrains Mono', monospace
- Use for: degrees, coordinates, technical data (sparingly)
**Font Sizes by Context:**
| Element | Size | Weight | Font |
|---------|------|--------|------|
| Slide title | 28-32px | 400 | Instrument Serif |
| Section title | 22-26px | 400 | Instrument Serif |
| Subtitle/tagline | 14px | 400 | DM Sans |
| Body text | 13px | 400 | DM Sans |
| Badge text | 10px | 600 | DM Sans |
| Tag/label | 9-10px | 400 | DM Sans, letter-spacing: 2px |
| Data/degree | 11px | 400 | DM Sans |
| Logo "big3.me" | 13px | 600 | DM Sans |
| CTA button | 14px | 600 | DM Sans |
### Logo Usage
```html
<span class="logo">big<span style="color: #a78bfa">3</span>.me</span>
```
- "3" is always accent purple (#a78bfa) in dark mode
- "3" is always deep purple (#7c3aed) in light mode
- Rest of logo is primary text color
- Font: DM Sans, weight 600
- Tagline below logo: "TRANSIT ASTROLOGY" in muted, 10px, letter-spacing 3px
### Spacing and Layout
- Card padding: 24-28px
- Element gaps: 8px (tight), 12px (normal), 20px (loose), 32px (section)
- Border radius: 4px (cards), 16px (inner panels), 20px (pills/badges), 50px (buttons)
- Border width: 1px
- Glow effects: radial-gradient, 300-350px diameter, 0.06-0.12 opacity max
---
## 2. Slide Formats
### Supported Dimensions
| Format | Pixels | Ratio | Use |
|--------|--------|-------|-----|
| Instagram Feed | 1080 x 1080 | 1:1 | Feed posts, X/Twitter |
| Instagram Portrait | 1080 x 1350 | 4:5 | Carousel slides, portrait |
| Instagram Story | 1080 x 1920 | 9:16 | Stories, Reels, TikTok |
| Blog Hero | 1200 x 630 | ~1.9:1 | OG images, blog headers |
| X/Twitter | 1200 x 675 | 16:9 | Twitter cards |
### Display Sizes (for HTML prototyping at 0.4x)
| Format | Display W x H |
|--------|---------------|
| 1:1 | 432 x 432px |
| 4:5 | 432 x 540px |
| 9:16 | 432 x 768px |
| Blog Hero | 480 x 252px |
---
## 3. Slide Types
### Type 1: Hero Slide
**Purpose:** Opening slide for carousels, article header card.
**Structure:**
```
+------------------------------+
| [logo]              [tag]    |  <- header strip
|                              |
|         [portrait/icon]      |  <- optional
|       [CELEBRITY NAME]       |  <- Instrument Serif, 32px
|    Sun sign Moon sign ASC    |  <- accent purple, 14px
|                              |
|  [Title of transit analysis] |  <- Instrument Serif, 20px
|                              |
|    [birth data] [date]       |  <- muted, 11px
|         SWIPE ->             |  <- muted, 10px, 50% opacity
+------------------------------+
```
**Rules:**
- Always dark theme
- Decorative: 2-3 subtle orbital rings (1px, 3% opacity), 5-8 star dots (2-3px, 15-30% opacity)
- Glow: top-right purple, bottom-left orange/pink
- Portrait: 140px circle, gradient border, initials or photo
- "SWIPE ->" only on carousel slide 1
### Type 2: Aspect Detail Slide
**Purpose:** Deep dive on one specific transit aspect.
**Structure:**
```
+------------------------------+
| [logo]                       |
|                              |
| [EXACT 0.2deg] badge        |  <- strength badge
|                              |
| Saturn Return in Pisces      |  <- Instrument Serif, 26px
| Transit Saturn conj Natal    |  <- accent, 12px
|                              |
| +- aspect visual box ------+|
| | [TRANSIT] conj [NATAL]   ||  <- planet circles + connector
| |  Pisces 3d21  Pisces 3d08||  <- positions with zodiac symbols
| +---------------------------+|
|                              |
| Description text 3-4 lines   |  <- muted, 13px, line-height 1.65
|                              |
| [logo]              [2 / 5]  |  <- footer
+------------------------------+
```
**Planet Circle Component:**
```css
/* Transit planet (left) */
.transit {
  background: linear-gradient(135deg, rgba(167,139,250,0.2), rgba(167,139,250,0.05));
  border: 1.5px solid rgba(167,139,250,0.3);
  color: #a78bfa;
}
/* Natal planet (right) */
.natal {
  background: linear-gradient(135deg, rgba(244,114,182,0.2), rgba(244,114,182,0.05));
  border: 1.5px solid rgba(244,114,182,0.3);
  color: #f472b6;
}
```
**Aspect Symbols:**
| Aspect | Symbol | Meaning |
|--------|--------|---------|
| Conjunction | conj | 0deg |
| Opposition | opp | 180deg |
| Trine | tri | 120deg |
| Square | sq | 90deg |
| Sextile | sxt | 60deg |
**Rules:**
- Alternate dark/light between slides
- Aspect visual box: slightly lighter surface with subtle border
- Strength badge top-left, color-coded by orb
- Max 4 lines of description text
- Footer always has logo + page indicator
### Type 3: Natal Chart Data Slide
**Purpose:** Show planet positions table from big3.me.
**Rules:**
- Prefer light theme for data tables (better readability)
- Sign names in accent purple
- Degrees in muted gray
- Section labels: 9px, letter-spacing 2px, uppercase, 50% opacity
- Row separator: 1px line at 3-4% opacity
### Type 4: Cosmic Weather Slide
**Purpose:** Daily transit summary card.
**Transit Row Component:**
- Left: 36px circle with planet symbol, color-coded
- Center: transit name + short description
- Right: strength badge
**Rules:**
- Temperature number is the TII (Transit Intensity Index) from big3.me
- Always dark theme (matches app aesthetic)
- 4:5 format preferred for stories
### Type 5: CTA Slide
**Purpose:** Final carousel slide driving to big3.me.
**Button Gradient:**
```css
background: linear-gradient(135deg, #a78bfa, #8b5cf6);
border-radius: 50px;
padding: 14px 36px;
color: white;
font-weight: 600;
```
**Rules:**
- Always dark theme
- Decorative orbital rings centered (3 concentric, 3% opacity)
- CTA text varies: "Check Your Transits", "Create Your Chart", "See Your Cosmic Weather"
- 3 feature bullets with purple dots
---
## 4. Dark/Light Alternation Pattern
### Carousel Rhythm (5 slides)
| Slide | Type | Theme | Rationale |
|-------|------|-------|-----------|
| 1 | Hero | DARK | Premium first impression |
| 2 | Aspect | LIGHT | Contrast, data readability |
| 3 | Aspect | DARK | Rhythm |
| 4 | Natal Data | LIGHT | Tables read better on light |
| 5 | CTA | DARK | Brand impact, final impression |
### Carousel Rhythm (3 slides)
| Slide | Type | Theme |
|-------|------|-------|
| 1 | Hero | DARK |
| 2 | Aspect/Data | LIGHT |
| 3 | CTA | DARK |
### Light Theme Modifications
When building light slides, change ONLY the base colors:
```css
background: #faf9f7;           /* was #0a0a0b */
surface: #ffffff;               /* was #131316 */
surface-2: #f2f0ed;            /* was #1a1a1f */
border: rgba(0,0,0,0.06);     /* was rgba(255,255,255,0.06) */
text: #1a1a1f;                 /* was #e8e8ec */
text-muted: #6e6e76;           /* was #8e8e96 */
accent-purple: #7c3aed;        /* slightly deeper for contrast on light */
```
**Light theme glow effects:** Use same radial gradients but at 0.04-0.06 opacity (halved).
---
## 5. Data Integration Rules
### CRITICAL: Never Invent Transit Data
All planetary positions MUST come from big3.me API:
```
POST /api/v1/profiles/{id}/transits/report
```
Claude generates article text and visual descriptions. Claude does NOT generate:
- Planet positions (degrees, signs, houses)
- Aspect orbs
- Transit timing (start/peak/end dates)
- TII scores
These come ONLY from Swiss Ephemeris via big3.me API.
### Data Display Formatting
**Degrees:** Always show sign symbol + degree + minute
**Orbs:** Show to 1 decimal: 0.2deg, 1.4deg
**Aspect strength badges:** EXACT (0-1deg), STRONG (1-3deg), APPLYING (3-5deg)
---
## 6. Content Generation Workflow
### From Blog Post to Visual Cards
Input: big3.me/news article URL or content
Output: 5 HTML slides ready for screenshot
**Step 1:** Extract from article:
- Celebrity name, birth data, Big 3
- Key transits discussed (2-3 main aspects)
- Main narrative/angle
**Step 2:** Map to slides:
- Slide 1: Hero with celebrity + article title
- Slide 2: Strongest transit aspect (lowest orb)
- Slide 3: Second transit aspect
- Slide 4: Natal chart data table
- Slide 5: CTA
**Step 3:** Generate HTML using brand styles from this skill.
**Step 4:** Screenshot each slide at target resolution.
### Decorative Elements
- Max 3 orbital rings per slide
- Max 8 star dots per slide
- Max 2 glow effects per slide (opposite corners)
- Light theme: halve all opacity values
- Never use gradients on text (except logo in hero)
- No shadows, no blur, no noise textures
---
## 7. Zodiac Sign Reference
**Symbols and Unicode:**
| Sign | Symbol | Unicode |
|------|--------|---------|
| Aries | U+2648 |
| Taurus | U+2649 |
| Gemini | U+264A |
| Cancer | U+264B |
| Leo | U+264C |
| Virgo | U+264D |
| Libra | U+264E |
| Scorpio | U+264F |
| Sagittarius | U+2650 |
| Capricorn | U+2651 |
| Aquarius | U+2652 |
| Pisces | U+2653 |
**Planet Symbols:**
| Planet | Symbol |
|--------|--------|
| Sun | U+2609 |
| Moon | U+263D |
| Mercury | U+263F |
| Venus | U+2640 |
| Mars | U+2642 |
| Jupiter | U+2643 |
| Saturn | U+2644 |
| Uranus | U+2645 |
| Neptune | U+2646 |
| Pluto | U+2647 |
| Chiron | U+26B7 |
| North Node | U+260A |
| Lilith | U+26B8 |
---
## 8. Instagram Specific Rules
### Grid Aesthetic
- Alternate dark/light posts for visual rhythm on profile grid
- First slide (grid thumbnail) always has celebrity name or topic clearly visible
- Avoid text smaller than 24px on 1:1 grid thumbnails (illegible on mobile)
### Caption Template
```
[Celebrity]'s transits are telling a story right now.
[2-3 sentence hook from the article]
Swipe to see the full transit breakdown
Data from big3.me - create your free chart at the link in bio.
#astrology #transits #[celebrity]astrology #natalchart #[sign]season
```
### Hashtag Bank
Core: #astrology #transits #natalchart #birthchart #zodiac
Celebrity: #[name]astrology #[name]birthchart
Seasonal: #ariesseason #saturnreturn #plutointransit
Product: #big3me #cosmicweather #transitastrology
---
## 9. Quality Checklist
Before finalizing any visual:
- [ ] All transit data comes from big3.me API (not invented)
- [ ] Planet positions match actual current positions
- [ ] Aspect orbs are calculated correctly
- [ ] Sign symbols match sign names
- [ ] Logo "3" is purple (#a78bfa dark / #7c3aed light)
- [ ] Dark slides have transparent glow effects, not solid colors
- [ ] Light slides have reduced opacity on all decorative elements
- [ ] Text is readable at target resolution (min 24px for key text on mobile)
- [ ] Footer has logo + page indicator on every slide except hero
- [ ] CTA slide points to big3.me
- [ ] Carousel alternates dark/light themes
- [ ] Birth data is Astro-Databank verified (AA or A rating preferred)
