# Astro Consul — Project Skill File

> Complete knowledge base for AI assistants working on this project.
> Read this file before making any changes to understand architecture, formulas, and decisions.

---

## 1. Project Overview

### What Is Astro Consul?
An astrology app positioned as **"Apple Weather for astrology"** — turning complex transit data into intuitive, personalized cosmic weather reports.

### MVP Goal
Launch in 2-3 weeks. Get first 100-250 users. Start monetization with Pro tier ($4.99/mo).

### MVP Scope
- **Daily Cosmic Weather** — TII (Transit Intensity Index) 0-100°, Feels Like label, AI headline, Moon phase, top 3 transits
- **10-Day Forecast** — scrollable day strip with TII, emoji, headline per day
- **Natal Chart** — SVG zodiac wheel with natal/transit toggle, positions table, aspects table
- **Profile Sidebar** — profile list with search, TII badge per profile
- **Monetization** — Free/Pro tiers via Stripe

### Tech Stack
| Layer | Technology |
|-------|-----------|
| Backend | Python 3.11+, FastAPI, Uvicorn |
| Ephemeris | PySwissEph (Swiss Ephemeris C wrapper) |
| Database | SQLAlchemy 2.0 (PostgreSQL prod / SQLite dev / file-based JSON default) |
| Migrations | Alembic |
| Frontend | React 18.3, TypeScript 5.7, Vite 6.1 |
| Styling | Vanilla CSS with custom properties (no UI library) |
| Fonts | Noto Sans Symbols 2 (Unicode glyphs for planets/signs) |
| AI | Claude API (Haiku for headlines) |
| Auth | Supabase Auth (Google OAuth, Apple Sign-In, email/password) |
| Payments | Stripe Checkout (planned) |
| Mobile | Capacitor (iOS + Android wrapper), WidgetKit + WatchOS (Swift/SwiftUI) |

### Repo Structure
```
astro-consul/
├── app/                          # Modular monolith backend (production code)
│   ├── main.py                   # FastAPI app factory
│   ├── core/                     # Config (Pydantic Settings), logging
│   ├── api/v1/routes/            # API endpoints (health, charts, profiles, locations)
│   ├── api/legacy.py             # Backward-compat root-level routes
│   ├── api/handlers.py           # Request handler orchestration
│   ├── api/dependencies.py       # DI factories (LRU-cached services)
│   ├── application/services/     # Business logic (Chart, Profile, Transit, Location, Health)
│   ├── domain/astrology/         # Domain wrappers re-exporting root modules
│   ├── infrastructure/           # Persistence (models, repositories, sessions)
│   └── schemas/                  # Pydantic request/response DTOs
├── chart_builder.py              # Swiss Ephemeris natal chart calculation
├── transit_builder.py            # Transit report generation
├── transit_timing_engine.py      # Precise aspect timing (start/peak/exact/end)
├── transit_timeline.py           # Multi-day timeline builder
├── transit_aspect_engine.py      # Transit-to-natal aspect detection
├── aspect_engine.py              # Natal aspect detection + constants
├── astro_utils.py                # Zodiac math utilities
├── location_service.py           # Geocoding (Nominatim) + timezone lookup
├── natal_profiles.py             # File-based profile/chart persistence
├── frontend/                     # React SPA
│   ├── src/App.tsx               # Main app shell, state, layout (~637 lines)
│   ├── src/components/           # UI components
│   │   ├── NatalZodiacRing.tsx   # SVG zodiac wheel (~1129 lines)
│   │   ├── TransitsTab.tsx       # Transit report UI (~560 lines)
│   │   ├── ProfileDetail.tsx     # Natal data display (~329 lines)
│   │   ├── ProfileEditForm.tsx   # Profile edit modal (~159 lines)
│   │   └── ProfileList.tsx       # Sidebar profile list (~35 lines)
│   ├── src/api.ts                # API client functions
│   ├── src/types.ts              # TypeScript type definitions
│   ├── src/styles.css            # All styling (~2300+ lines)
│   └── src/main.tsx              # React entry point
├── charts/                       # Persisted natal chart JSON files
├── profiles/                     # Persisted profile JSON files
├── ephe/                         # Swiss Ephemeris data files (.se1)
├── alembic/                      # Database migrations
├── tests/                        # Test suite
├── templates/                    # Legacy Jinja2 templates (fallback)
└── scripts/                      # Utility scripts
```

---

## 2. Architecture

### 5-Layer Pipeline
```
Astronomy → Aspects → Metrics → Interpretation → Presentation
```

| Layer | What It Does | Key Files |
|-------|-------------|-----------|
| **Astronomy** | Swiss Ephemeris: planet longitudes, house cusps, angles | `chart_builder.py`, `transit_builder.py` |
| **Aspects** | Detect aspects, compute orbs, determine strength | `aspect_engine.py`, `transit_aspect_engine.py` |
| **Metrics** | TII, Tension Ratio, Velocity, OPE, Moon phase | `app/domain/astrology/tii.py` (planned) |
| **Interpretation** | Feels Like labels, AI headlines, compound flags | `app/application/services/headline_service.py` (planned) |
| **Presentation** | React UI: widgets, charts, forecasts | `frontend/src/components/*` |

### Backend Architecture
```
FastAPI Routes (app/api/v1/routes/)
    ↓
Handlers (app/api/handlers.py)
    ↓
Services (app/application/services/)
    ↓
Domain Logic (app/domain/astrology/ → root modules)
    ↓
Swiss Ephemeris (pyswisseph)
    ↓
Repositories (app/infrastructure/repositories/)
    ↓
Persistence (file JSON or PostgreSQL)
```

**Key Services:**
- `ChartService` — build + save natal charts
- `ProfileService` — CRUD profiles, link charts
- `TransitService` — transit reports + timelines
- `HealthService` — liveness/readiness probes
- `LocationLookupService` — geocoding with cache

**Repository Pattern:**
- `ChartRepository` (Protocol) → `FileChartRepository` | `SqlAlchemyChartRepository`
- `ProfileRepository` (Protocol) → `FileProfileRepository` | `SqlAlchemyProfileRepository`
- `LocationCacheRepository` (Protocol) → `NullLocationCacheRepository` | `SqlAlchemyLocationCacheRepository`

### Frontend Architecture
```
App.tsx (state orchestration, layout, routing)
    ├── ProfileList (sidebar)
    ├── DailyWeather (main screen — planned)
    ├── ForecastView (10-day forecast — planned)
    ├── NatalZodiacRing (SVG wheel)
    ├── TransitsTab (transit report)
    ├── ProfileDetail (natal data: summary, positions, aspects)
    └── ProfileEditForm (modal)
```

**State Management:** React hooks only (`useState`, `useEffect`, `useCallback`, `useRef`). No external state library. Props drilling for data flow. `localStorage` for theme and transit params persistence.

**API Layer:** `api.ts` wraps `fetch()` calls with typed responses. Vite dev server proxies `/api/*` to `http://localhost:8001`.

### Backend ↔ Frontend Connection
| Frontend Function | HTTP | Backend Endpoint |
|-------------------|------|-----------------|
| `fetchHealth()` | GET | `/api/v1/health/ready` |
| `fetchProfiles()` | GET | `/api/v1/profiles` |
| `fetchProfileDetail(id)` | GET | `/api/v1/profiles/{id}` |
| `updateProfile(id, data)` | PATCH | `/api/v1/profiles/{id}` |
| `fetchTransitReport(id, body)` | POST | `/api/v1/profiles/{id}/transits/report` |
| `fetchTransitTimeline(id, params)` | GET | `/api/v1/profiles/{id}/transits/timeline` |
| `resolveLocation(name)` | POST | `/api/v1/locations/resolve` |
| `fetchForecast(id, params)` (planned) | GET | `/api/v1/profiles/{id}/transits/forecast` |

---

## 3. Key Formulas (CRITICAL — preserve exactly)

### TII (Transit Intensity Index)
```
TII = normalize(Σ (aspect_weight × orb_score × planet_factor × exactness_bonus))

orb_score = min(10, 1/(orb + 0.1))     ← NOT 1/orb! Prevents explosion at small orbs
normalization = min(100, raw_TII / 500 × 100)    ← caps at 100
```

### Aspect Weights
```
conjunction = 10
opposition  = 8
square      = 7
trine       = 6
sextile     = 5
```

### Planet Factors
```
Moon                        = 0.5
Sun, Mercury, Venus, Mars   = 1.0
Jupiter, Saturn             = 1.3
Uranus, Neptune, Pluto      = 1.5
```

### Exactness Bonus
```
exact   (orb < 0.1°)  = +3
applying               = +2
separating             = +1
```

### Tension Ratio
```
T/H = Σ weight(squares + oppositions) / Σ weight(all aspects)

0.0–0.3 = Low tension
0.3–0.6 = Mixed tension
0.6–1.0 = High tension
```

### Feels Like Matrix
```
              Low Tension    Mixed Tension    High Tension
Low TII       Calm           —                Grinding
Mid TII       Flowing        Dynamic          Pressured
High TII      Expansive      Charged          Intense
Extreme TII   —              —                Explosive
```

### Velocity
```
V_planetary = count(non-lunar aspects changing exactness within 24h)
V_lunar     = count(lunar aspects) × 0.25    ← shown separately to prevent noise
```

### OPE (Outer Planet Energy)
```
OPE = Σ (aspect_weight × orb_score)    for Pluto, Uranus, Neptune ONLY
```

### Retrograde Index
```
R_index = count(retrograde planets) + personal_bonuses
Personal bonus: +2 if Mercury Rx, +1.5 if Venus Rx, +1.5 if Mars Rx
Outer retrogrades: +0.5 each (Jupiter through Pluto)
```

### Moon Phase (from Swiss Ephemeris)
```
elongation = moon_longitude - sun_longitude (mod 360)
illumination_pct = (1 - cos(elongation_radians)) / 2 × 100

Phase names by elongation:
  0°        = New Moon
  0–90°     = Waxing Crescent
  90°       = First Quarter
  90–180°   = Waxing Gibbous
  180°      = Full Moon
  180–270°  = Waning Gibbous
  270°      = Third Quarter
  270–360°  = Waning Crescent
```

---

## 4. Planetary Weather Hierarchy

### Layer 1: Cosmic Climate (5-20 years)
- **Planets:** Pluto, Neptune, Uranus
- **Metric:** OPE (Outer Planet Energy)
- **Pace:** Generational shifts, societal themes
- **Update frequency:** Monthly

### Layer 2: Planetary Season (3-12 months)
- **Planets:** Jupiter, Saturn
- **Metric:** Cycle phases (ingress, station, aspect patterns)
- **Pace:** Major life themes, career/growth cycles
- **Update frequency:** Weekly

### Layer 3: Cosmic Weather (days to weeks)
- **Planets:** Sun, Mercury, Venus, Mars
- **Metrics:** TII, Tension Ratio, Velocity
- **Pace:** Day-to-day energy shifts, communication patterns
- **Update frequency:** Daily (core of MVP)

### Layer 4: Hourly Flow
- **Bodies:** Moon, ASC (Ascendant)
- **Metric:** Lunar velocity (V_lunar × 0.25)
- **Pace:** Mood shifts, emotional tides
- **Update frequency:** Hourly (post-MVP)

---

## 5. Data Models

### Backend Models (SQLAlchemy)

**UserModel**
```
id: String(128) PK
auth_subject: String(255) UNIQUE
email: String(255)
status: String(64) default "active"
created_at: DateTime(tz)
→ profiles: [ProfileModel]
```

**NatalChartModel**
```
id: String(128) PK
chart_hash: String(64) UNIQUE (SHA256)
house_system: String(64)
julian_day: Float
birth_input_json: JSON nullable
chart_payload_json: JSON
created_at: DateTime(tz)
→ profiles: [ProfileModel]
```

**ProfileModel**
```
id: String(128) PK
user_id: FK → users.id
handle: String(255) UNIQUE (username)
display_name: String(255)
birth_date: Date
birth_time: Time
timezone: String(255)
location_name: String(255) nullable
latitude: Float
longitude: Float
chart_id: FK → natal_charts.id
created_at, updated_at: DateTime(tz)
→ user, chart, latest_transit
```

**LatestTransitModel**
```
profile_id: FK → profiles.id (PK)
transit_date: Date
transit_time: Time
timezone: String(255)
location_name: String(255) nullable
latitude, longitude: Float nullable
updated_at: DateTime(tz)
```

**LocationCacheModel**
```
query: String(255) PK
resolved_name: String(255)
latitude, longitude: Float
timezone: String(255)
provider: String(255)
updated_at: DateTime(tz)
```

### Frontend Types (TypeScript)

**ProfileSummary**
```typescript
{ profile_id, profile_name, username, location_name?, local_birth_datetime?, latest_transit? }
```

**NatalPosition**
```typescript
{ id, longitude, degree, minute, second, sign, formatted_position, house, retrograde, speed }
```

**ActiveAspect**
```typescript
{ transit_object, natal_object, aspect, exact_angle, delta, orb, is_within_orb, strength, timing }
```

**AspectTiming**
```typescript
{ start_utc, peak_utc, exact_utc, end_utc, peak_orb, status, will_perfect, duration_hours }
```

**TransitReportResponse**
```typescript
{ snapshot, natal_positions, angle_positions, transit_positions, active_aspects }
```

**DailyForecast** (planned)
```typescript
{ date, tii, tension_ratio, feels_like, headline, top_transits[], moon }
```

**MoonPhase** (planned)
```typescript
{ phase_name, phase_angle, illumination_pct, moon_sign, moon_degree }
```

---

## 6. API Endpoints

### Current (Implemented)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/health/live` | Liveness probe |
| GET | `/api/v1/health/ready` | Readiness probe (DB, ephemeris, frontend) |
| POST | `/api/v1/charts/natal` | Debug: raw chart calculation |
| POST | `/api/v1/locations/resolve` | Geocode location → lat/lon/timezone |
| GET | `/api/v1/profiles` | List all profiles |
| POST | `/api/v1/profiles` | Create profile + natal chart |
| GET | `/api/v1/profiles/{id}` | Profile detail with chart data |
| PATCH | `/api/v1/profiles/{id}` | Update profile + recalculate chart |
| POST | `/api/v1/profiles/{id}/transits/report` | Transit report for date/time |
| GET | `/api/v1/profiles/{id}/transits/timeline` | Transit timeline for date range |

### Transit Report Request Body
```json
{
  "transit_date": "2026-03-14",
  "transit_time": "12:00",
  "timezone": "Europe/Moscow",
  "location_name": "Moscow, Russia",
  "latitude": 55.7558,
  "longitude": 37.6173,
  "include_timing": true
}
```

### Transit Report Response (current)
```json
{
  "snapshot": { "chart_id", "profile_id", "transit_utc_datetime", "transit_timezone", ... },
  "natal_positions": [{ "id", "longitude", "sign", "house", "degree", "minute", ... }],
  "angle_positions": [{ "id", "longitude", "sign", ... }],
  "transit_positions": [{ "id", "longitude", "sign", "speed", "retrograde", "natal_house", ... }],
  "active_aspects": [{ "transit_object", "natal_object", "aspect", "orb", "strength", "timing", ... }]
}
```

### Planned Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/profiles/{id}/transits/forecast?days=10&timezone=...` | 10-day forecast with TII per day |

### Planned Forecast Response
```json
{
  "days": [
    {
      "date": "2026-03-14",
      "tii": 72.5,
      "tension_ratio": 0.45,
      "tension_level": "Mixed",
      "feels_like": "Dynamic",
      "headline": "Mars meets Mercury — sharp ideas, fast decisions",
      "top_transits": [
        { "transit_object": "Mars", "natal_object": "Mercury", "aspect": "conjunction", "orb": 0.06, "strength": "exact" }
      ],
      "moon": {
        "phase_name": "Waning Gibbous",
        "illumination_pct": 87.3,
        "moon_sign": "Scorpio",
        "moon_degree": 15
      }
    }
  ]
}
```

---

## 7. Frontend Components

### Component Map

| Component | File | Responsibility |
|-----------|------|---------------|
| **App** | `App.tsx` | Root shell: layout, state, routing, overlays |
| **ProfileList** | `ProfileList.tsx` | Sidebar: searchable profile buttons |
| **ProfileSummaryCard** | `ProfileDetail.tsx` | Sun/Moon/ASC signs, age, birth data |
| **NatalPositionsTable** | `ProfileDetail.tsx` | All planet positions grouped by category |
| **NatalAspectsTable** | `ProfileDetail.tsx` | Natal aspects with orbs and strength |
| **NatalZodiacRing** | `NatalZodiacRing.tsx` | SVG zodiac wheel: signs, houses, planets, aspects |
| **TransitsTab** | `TransitsTab.tsx` | Transit report: settings, aspect cards, timeline |
| **ProfileEditForm** | `ProfileEditForm.tsx` | Modal: edit profile name, birth data, location |
| **PlanetsPreview** | `App.tsx` (inline) | Compact widget: top 5 planets |
| **AspectsPreview** | `App.tsx` (inline) | Compact widget: top 4 aspects |
| **TransitAspectsPreview** | `App.tsx` (inline) | Compact widget: strong transit aspects |
| **DailyWeather** | *(planned)* | TII gauge, Feels Like, headline, Moon, top transits |
| **ForecastView** | *(planned)* | 10-day scrollable forecast strip |

### Design System

**CSS Custom Properties (Dark Mode):**
```css
--bg: #071019               /* Main background */
--surface: rgba(10,16,24,0.86)  /* Card backgrounds */
--ink: #f5f3ee              /* Primary text */
--muted: #a7b1c0            /* Secondary text */
--accent: #f4efe3           /* Accent color */
--accent-ink: #10141b       /* Text on accent */
--ok: #83e0ad               /* Success */
--error: #f1a9a9            /* Error */
--line: rgba(255,255,255,0.1)   /* Dividers */
```

**Light Mode:** Full inversion via `[data-theme="light"]` selector and `@media (prefers-color-scheme: light)`.

**Typography:** "Avenir Next", "Helvetica Neue", sans-serif. Noto Sans Symbols 2 for glyphs.

**Widget Pattern:** Rounded cards (20px radius), gradient backgrounds, subtle shadows, hover scale effect (1.008). Click → popup overlay with slide-up animation.

**Layout:** Two-column grid. Left: stacked Natal + Transits widgets. Right: zodiac wheel (transparent background). Sidebar: fixed-width profile list.

---

## 8. MVP Phases

### Phase 1: TII + Tension + Feels Like (Backend) — P0
- Create `app/domain/astrology/tii.py` with compute functions
- Wire into transit report response
- New forecast endpoint returning per-day TII
- **Effort: 1-2 days**

### Phase 2: Moon Phase (Backend) — P0
- Create `app/domain/astrology/moon.py` using Swiss Ephemeris Sun-Moon elongation
- Include in forecast response
- **Effort: 0.5 days**

### Phase 3: AI Headlines (Backend) — P0
- Add `anthropic` SDK, create headline service
- Claude Haiku for cost-efficient one-liner generation
- Template fallback if API fails
- Cache per (profile, date)
- **Effort: 0.5-1 day**

### Phase 4: Daily Cosmic Weather Screen (Frontend) — P0
- New `DailyWeather.tsx` component
- TII gauge (SVG arc), Feels Like, headline, Moon phase, top 3 transits
- View switching in App.tsx (`"weather" | "forecast" | "chart"`)
- **Effort: 2-3 days**

### Phase 5: 10-Day Forecast Screen (Frontend) — P0
- New `ForecastView.tsx` with horizontal scrollable day strip
- Per-day card: TII, emoji, headline. Tap → detail
- **Effort: 1.5-2 days**

### Phase 6: Sidebar TII Badges (Frontend) — P1
- Show TII number on active profile card
- **Effort: 0.5 days**

### Phase 7: Auth + Payments (Backend + Frontend) — P2
- Clerk/Auth0 for auth, Stripe for subscriptions
- Free tier: TII + Feels Like + headline + Moon + 3-day preview
- Pro ($4.99/mo): Full 10-day, all details, wheel, notifications
- Lifetime ($49.99): Launch promo
- **Effort: 3-5 days**

### Phase 8: Push Notifications — P3 (post-launch)
- Web Push via Service Worker + VAPID
- Daily morning: "Your cosmic weather: 72° Dynamic. Mars conjunct Mercury today."
- **Effort: 2-3 days**

### Timeline
| Week | Work | Deliverable |
|------|------|-------------|
| 1 | Phase 1+2+3 (backend) + Phase 4 start | TII API working |
| 2 | Phase 4+5+6 (frontend) | Full MVP UI |
| 3 | Phase 7 (auth+Stripe) + polish | Monetization live |

**P0 total: ~6-8 days. Full scope: ~12-16 days.**

---

## 9. Business Context

### Monetization
| Tier | Price | Features |
|------|-------|----------|
| Free | $0 | TII + Feels Like + headline + Moon phase + 3-day preview |
| Pro | $4.99/mo | Full 10-day forecast, all transit details, chart wheel, push notifications |
| Lifetime | $49.99 | Launch promo — all Pro features forever |

### Target
- **First month:** 100-250 users
- **Conversion target:** 5-10% free → Pro

### Distribution Strategy
- Product Hunt launch
- Reddit (r/astrology, r/AstrologySoftware)
- TikTok astrology community
- Twitter/X astrology accounts

### Positioning
**"Apple Weather for astrology"** — one number (TII), one feeling (Feels Like), one sentence (headline). No jargon overload.

### Competitive Landscape
| App | Price | Weakness |
|-----|-------|----------|
| Co-Star | $8.99/mo | Black box AI, no transparency in calculations |
| The Pattern | $14.99/mo | Vague, no real astrology depth |
| TimePassages | $9.99 one-time | Desktop-era UX, no daily weather concept |
| Astro Consul | $4.99/mo | Transparent formulas, weather metaphor, modern UI |

---

## 10. Key Decisions Log

### Formulas & Calculations
- **orb_score: `1/(orb+0.1)` NOT `1/orb`** — prevents infinity at 0° orb. At orb=0, score=10 (capped). At orb=1, score≈0.91.
- **Velocity: Lunar separated** — Moon changes signs every 2.5 days, would dominate V_planetary. Shown as separate V_lunar × 0.25.
- **Sector Focus: per-house NOT grouped by quadrants** — more granular and useful for personal transits.
- **No Decision Layer** — compound flags (Feels Like, velocity labels) computed directly in Metrics Engine. No separate AI interpretation layer for MVP.
- **TII normalization: raw/500×100** — simplified for MVP. 500 is empirical ceiling for "maxed out" day. Will calibrate with real data.
- **Exclude minor bodies from TII** — only 10 classical+modern planets (Sun through Pluto). Nodes, Lilith, Chiron excluded to keep score clean.

### Tech & Infrastructure
- **Stripe + Clerk for web payments, NOT RevenueCat** — app is web SPA, not native mobile. RevenueCat requires App Store/Google Play.
- **AI headlines: Claude Haiku, only today+tomorrow live, template for rest** — cost control (~$0.00025/call). 10 parallel calls for full forecast would be ~$0.0025/user/day.
- **PWA first, App Store via Capacitor later** — web launch is fastest path. iOS Web Push requires "Add to Home Screen" (iOS 16.4+).
- **File-based persistence default** — simplest for development. PostgreSQL for production via `ASTRO_CONSUL_PERSISTENCE_BACKEND=database`.
- **No react-router** — simple `View` state switch consistent with existing popup/overlay pattern. Router adds complexity without benefit for 3 views.
- **Skip `include_timing` for forecast** — timing engine does expensive boundary scans. For per-day TII, orb + aspect type is sufficient. Full timing only for today's detail view.

### Design
- **Apple Weather aesthetic** — widget cards with rounded corners, gradient backgrounds, subtle shadows, dark/light theme.
- **Natal/Transit toggle on wheel** — single shared `wheelMode` state. Natal mode: natal aspects only. Transit mode: transit aspects only. No mixing.
- **Unicode glyphs over icon fonts** — Noto Sans Symbols 2 provides all astrological symbols. No custom icon font needed.

---

## 11. Natal Chart Data Layer

### Overview
Static natal chart interpretations stored as JSON in `data/`. This is the content users read about their own birth chart — planets, houses, signs, aspects. All files bilingual EN + RU in single file.

### Files & Structure

| File | Content | Entries | Key Format |
|------|---------|---------|------------|
| `natal_planets_in_signs.json` | Planet in zodiac sign | 120 | `Sun_in_Aries` |
| `natal_planets_in_houses.json` | Planet in house | 120 | `Sun_in_house_1` |
| `natal_house_cusps_in_signs.json` | House cusp sign | 144 | `house_1_in_Aries` |
| `natal_reference.json` | Houses, planets, signs definitions | 34 | Nested: `houses.house_1`, `planets.Sun`, `signs.Aries` |
| `natal_aspects.json` | Planet-planet natal aspects | 216 | `Sun_conjunction_Moon` |

**Total: 634 entries, ~950 KB**

### Entry Format (planets_in_signs, planets_in_houses, house_cusps, aspects)
```json
"Sun_in_Aries": {
  "en": { "meaning": "...", "keywords": ["...", "...", "..."] },
  "ru": { "meaning": "...", "keywords": ["...", "...", "..."] }
}
```

### Entry Format (natal_reference.json)
```json
{
  "houses": {
    "house_1": {
      "en": { "name": "1st House", "domain": "...", "meaning": "...", "keywords": [...] },
      "ru": { "name": "1-й дом", "domain": "...", "meaning": "...", "keywords": [...] }
    }
  },
  "planets": {
    "Sun": {
      "en": { "name": "Sun", "glyph": "☉", "domain": "...", "meaning": "...", "keywords": [...] },
      "ru": { ... }
    }
  },
  "signs": {
    "Aries": {
      "en": { "name": "Aries", "glyph": "♈", "element": "Fire", "modality": "Cardinal", "ruler": "Mars", "dates": "Mar 21 – Apr 19", "meaning": "...", "keywords": [...] },
      "ru": { ... }
    }
  }
}
```

### Backend Lookup
```python
def get_natal_description(category, key, lang="en"):
    """
    category: "planets_in_signs" | "planets_in_houses" | "house_cusps" | "aspects" | "reference"
    key: "Sun_in_Aries" | "Sun_in_house_1" | "house_1_in_Aries" | "Sun_conjunction_Moon"
    """
    db = load_json(f"data/natal_{category}.json")
    entry = db.get(key)
    if entry:
        return entry[lang]
    return None
```

### Astronomical Limits (aspects)
Not all planet pairs can form all 5 aspects:
- **Sun-Mercury**: max 28 apart -> conjunction + sextile only
- **Sun-Venus**: max 48 apart -> conjunction + sextile only
- **Mercury-Venus**: max 76 apart -> conjunction + sextile only
- All other pairs: all 5 aspects (conjunction, opposition, square, trine, sextile)

Total: 216 entries (not 225, because 9 are astronomically impossible)

### Content Principles
- Modern, warm tone. No fatalism, no gender stereotypes
- Each entry: strength -> how it manifests -> shadow side -> growth challenge
- Planets_in_signs: 4-6 sentences. Keywords: 5 per entry
- Planets_in_houses: 4-6 sentences. Keywords: 5 per entry
- House_cusps: 2-3 sentences (shorter, more focused). Keywords: 5 per entry
- Aspects: 2-4 sentences. Keywords: 3 per entry
- Reference: full paragraph per entry with domain, meaning, keywords

### Difference from Transit Descriptions
| | Transit (`transit_aspects.json`) | Natal (`natal_aspects.json`) |
|---|---|---|
| Duration | Temporary, passing | Permanent, lifelong |
| Question | "What do I do now?" | "Who am I?" |
| Tone | Advice, action, timing | Character, pattern, potential |
| Example | "Period of pressure. Endure — passes in 2 months." | "Born with an inner critic. Authority and self-doubt are lifelong themes." |

**DO NOT reuse transit descriptions for natal. They are fundamentally different content.**

---

## 12. Mobile App Strategy

### Approach
**Capacitor** (by Ionic) wraps the existing React web app in a native iOS/Android shell. No UI rewrite needed — the frontend already has responsive design with 5 breakpoints (1200px, 960px, 1024px, 600px, 400px).

### Architecture
```
Xcode Workspace
├── App/                          ← Capacitor (web app in WKWebView)
│   └── frontend/dist/            ← Built React app
├── TiiWidget/                    ← WidgetKit (Swift/SwiftUI, separate target)
├── WatchApp/                     ← Apple Watch (SwiftUI, separate target)
└── Shared/                       ← App Group for token/data sharing
```

### Key Decisions
- **Capacitor over React Native/Swift** — web app already works on mobile, zero rewrite. Widgets and Watch require Swift regardless of main app technology.
- **Mobile-first optimization before wrapping** — polish responsive UI in browser DevTools first, then `npx cap add ios/android`.
- **Native extensions are separate targets** — WidgetKit and WatchOS are always Swift/SwiftUI, independent of main app tech. They communicate via App Groups (shared UserDefaults).

### Capacitor Config
```
App ID:     com.astroconsul.app
App Name:   Astro Consul
Web Dir:    dist (Vite build output)
Plugins:    @capacitor/splash-screen, @capacitor/status-bar, @capacitor/push-notifications
```

### Widget (WidgetKit)
- Shows TII score + top transit for today
- Calls `/api/v1/profiles/{id}/transits/report` via URLSession
- Auth token shared from main app via App Groups
- Updates hourly via TimelineProvider

### Apple Watch
- SwiftUI app showing TII + daily summary
- WatchConnectivity syncs with iPhone
- Complication shows TII on watch face

### Platforms
- iOS 16+ (WidgetKit requires iOS 14+, but interactive widgets need iOS 17)
- Android (via `npx cap add android`, same web app)

---

## Appendix: Aspect Engine Constants

### Natal Aspect Orbs (from `aspect_engine.py`)
```
Conjunction: 0°, orb 8°
Sextile:    60°, orb 4°
Square:     90°, orb 6°
Trine:     120°, orb 6°
Opposition: 180°, orb 8°
```

### Transit Strength Thresholds (from `transit_aspect_engine.py`)
```
exact:    orb ≤ 0.25°
strong:   orb ≤ 1.00°
moderate: orb ≤ 1.99°
wide:     orb > 1.99° (filtered out by MAX_TRANSIT_ORB = 1.99)
```

### Timing Engine Settings (from `transit_timing_engine.py`)
```
Resolution: 1 minute (binary search refinement)
Exact tolerance: 0.01°

Per-planet scan settings (step / horizon):
  Moon:              30 min / 7 days
  Sun, Mercury:       2 hr  / 60 days
  Venus, Mars:        2 hr  / 120 days
  Jupiter:           12 hr  / 730 days (2 yr)
  Saturn:            12 hr  / 1095 days (3 yr)
  Uranus, Neptune:    1 day / 2555 days (7 yr)
  Pluto:              1 day / 3650 days (10 yr)
```

### Swiss Ephemeris Object IDs (from `chart_builder.py`)
```python
TRANSIT_OBJECT_IDS = {
    "Sun": swe.SUN, "Moon": swe.MOON, "Mercury": swe.MERCURY,
    "Venus": swe.VENUS, "Mars": swe.MARS, "Jupiter": swe.JUPITER,
    "Saturn": swe.SATURN, "Uranus": swe.URANUS, "Neptune": swe.NEPTUNE,
    "Pluto": swe.PLUTO, "North Node": swe.TRUE_NODE, "Lilith": swe.MEAN_APOG
}

NATAL_SPECIAL_OBJECT_IDS = {
    "Chiron": swe.CHIRON, "Lilith": swe.MEAN_APOG,
    "Selena": swe.AST_OFFSET + 232, "North Node": swe.TRUE_NODE
}
```

### House System
```
Placidus (swe flag: 'P')
Houses numbered 1-12 from ASC
```

---

## 13. Time-Based Feels Like Modifiers

### Overview
The "Feels Like" description changes based on the time of day. The same TII × Tension combination produces different guidance depending on when the user views it.

### Time Windows
| Window | Hours | Theme |
|--------|-------|-------|
| Morning | 6:00–12:00 | Intentions, preparation, rising energy |
| Afternoon | 12:00–18:00 | Peak action, decisions, bold moves |
| Evening | 18:00–23:00 | Reflection, social connection, winding down |
| Night | 23:00–6:00 | Rest, recovery, subconscious processing |

### Data File
`data/feels_like_time_modifiers.json` — 12 feels_like labels × 4 time windows × 2 languages (EN + RU).

Each entry has:
- `headline` (3-5 words) — shown as mood line
- `description` (1-2 sentences) — shown as feels description

### Frontend Integration
- `frontend/src/time-modifiers.ts` — utility to determine time window from UTC datetime + timezone, and look up the appropriate modifier
- `DailyWeather.tsx` — uses time-based descriptions instead of static guide descriptions
- Time window indicator shown below the description (e.g. "MORNING 6:00–12:00")
- `TiiGuide.tsx` — "Time of Day Context" section added to How It Works popup

### Design Principles
- Night descriptions are restful, NOT action-oriented
- Morning descriptions focus on intentions and preparation
- Evening descriptions focus on reflection and social connection
- Afternoon descriptions are the original "peak day" descriptions
- Tone: warm, concrete, actionable (time-appropriate)

---

## 14. News & Blog Post Pipeline

### Publishing Posts
- Post files live in `scripts/posts/` (see `example_post.py` for template)
- Publish via: `python scripts/publish_post.py scripts/posts/<slug>.py`
- If in sandbox (no internet): create an Alembic migration with INSERT INTO news_posts
- Author is always "Victoria"
- All transit claims must be verified against Swiss Ephemeris

### Image Pipeline (Automated)
Blog post images are generated and uploaded via GitHub Action — no manual steps needed.

**Workflow:**
1. Generate branded HTML cards in `tmp/post-images/`:
   - `cover.html` → hero_image_url + og_image_url
   - `section_0_*.html` → sections[0].image_url
   - `section_1_*.html` → sections[1].image_url (etc.)
2. Create `tmp/post-images/slug.txt` with the post slug (one line, no spaces)
3. Commit and push to `claude/*` branch
4. GitHub Action (`.github/workflows/upload-post-images.yml`):
   - Renders HTML → PNG via Playwright (1080×1350, 4:5 portrait)
   - Uploads to Supabase Storage bucket `news-images`
   - Updates post record with image URLs via Supabase REST API

**Image style:** Instagram-style social media cards (bold text, gradients, cosmic theme). NOT web page screenshots. Reference: `.claude/skills/big3me-content-design/SKILL.md`

**Manual fallback:** `python scripts/render_and_upload_images.py <slug> tmp/post-images/`

### Daily Post Prompt
See `.ai/prompts/daily-post.md` for a ready-to-paste prompt template.

---

## Worklog

### 2026-03-16 — UI/UX Polish & Bug Fixes

**Locked preview redesign** — Replaced abstract shapes with real-looking blurred dummy content for Active Transits and Cosmic Climate widgets (non-followed profiles). Titles visible, content blurred with light overlay + lock icon.

**Mobile footer** — Removed full-width bottom bar, added unified floating footer with burger menu, search bar (Apple Weather style, `border-radius: 50px`), and add button. Footer stays in same position across list/detail views.

**Followers/Following widget** — Instagram-style follower counts + follow/unfollow button above Natal widget. Backend returns `followers_count`, `following_count`, `is_following`, `is_own`. Unfollow confirmation popup.

**Column swap** — Followers+Natal+Wheel moved to left column (desktop), Transits+Climate to right. Mobile keeps natal first via `order: -1`.

**Sidebar cards** — Username shown under profile name. Timezone format changed from `AMERICA / LOS ANGELES` to `Los Angeles GMT-7` (city + UTC offset). Removed emoji from feels label. Reduced card padding and font sizes.

**Create/Edit form** — Timezone field moved into Coordinates section. Latitude/Longitude fields made read-only (auto-filled from location).

**Bug fixes:**
- Primary profile no longer resets on page reload (bootstrap now depends on `userId` string, not `user` object reference that changed on every Supabase token refresh)
- Follow button loading fixed (manual re-fetch when following profile already being viewed)
- Transit descriptions now match UI language (fixed default fallback from `"ru"` to `"en"` in `api.ts`, added `lang` dependency to transit useEffect)
- Transit location params now persist latitude/longitude to localStorage (previously only saved timezone + locationName)

**Public landing page (WIP)** — Backend: added `is_featured` flag to ProfileModel, `list_featured()` repository method, public API endpoints (`GET /public/featured`, `GET /public/profiles/{id}`) with no auth required. Frontend landing page component pending.
