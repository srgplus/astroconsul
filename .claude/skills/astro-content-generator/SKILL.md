# Astro Content Generator Skill

Generate and publish astrology blog posts for big3.me/news.

## Model Recommendation
- **Content writing** (post text, analysis, Victoria's voice): **Opus** preferred for nuance and quality
- **Image generation** (HTML/CSS, Playwright screenshots): **Sonnet** is sufficient — delegate to big3me-content-design skill
- **Data operations** (publish, upload, Supabase queries): **Sonnet** is sufficient

## Agent Delegation
When creating a post WITH images, use a subagent for image generation:
- **Main agent**: writes post content → publishes via publish_post.py
- **Subagent** (launch via Agent tool, model: sonnet): generates HTML files using big3me-content-design skill → runs render_and_upload_images.py

This runs in parallel, keeps the main context clean (HTML/CSS is hundreds of lines), and is faster.

Example delegation prompt for the subagent:
"Generate branded HTML images for the blog post '<slug>' using .claude/skills/big3me-content-design/SKILL.md. Post title: '<title>', sections: [list headings]. Save HTML files to tmp/post-images/ with naming: cover.html, section_0_name.html, section_1_name.html. Then run: python scripts/render_and_upload_images.py <slug> tmp/post-images/"

## Voice & Style
- Author: **Victoria** — warm, knowledgeable astrologer who makes complex transits accessible
- Tone: confident but not preachy, practical, grounded
- Never vague horoscope language — always reference specific transits with degrees and orbs
- Use "AI chatbot" not specific brands (not "Claude" or "ChatGPT")

## Content Types (pick based on date)

| Type | When | Tags |
|------|------|------|
| Daily cosmic weather | Any day | transit,daily |
| Weekly forecast | Monday | transit,weekly |
| New/Full Moon report | Moon phase day | transit,lunar |
| Retrograde guide | Planet stations Rx/direct | transit,retrograde,educational |
| Celebrity transit analysis | Trending celebrity news | celebrity,transit |
| Educational guide | Anytime (1-2x/month) | educational,guide |

## Step-by-Step Workflow

### 1. Fetch today's transit data
```bash
curl -s "https://big3.me/api/v1/public/cosmic-weather?date=$(date +%Y-%m-%d)"
```
This returns: planet positions, moon phase, retrograde index, sky aspects (planet-to-planet aspects with orbs ≤ 3°).

### 2. Check for existing post today
```bash
python3 -c "
import json, os
from urllib.request import Request, urlopen
url = os.environ['SUPABASE_URL']
key = os.environ.get('SUPABASE_SERVICE_ROLE_KEY', os.environ.get('SUPABASE_KEY', ''))
req = Request(f'{url}/rest/v1/news_posts?select=slug,title&date=eq.$(date +%Y-%m-%d)&limit=1',
    headers={'apikey': key, 'Authorization': f'Bearer {key}'})
print(json.loads(urlopen(req).read()))
"
```
If a post already exists for today, SKIP — do not create duplicates.

### 3. Generate the post

Create a file `scripts/posts/<slug>.py` with this structure:

```python
from datetime import date

POST = {
    "slug": "slug-with-date-2026",           # URL-safe, unique
    "title": "Post Title",                     # Under 80 chars
    "subtitle": "Subtitle",                    # One sentence
    "date": date(2026, 3, 23),                 # Today's date
    "author": "Victoria",
    "status": "published",
    "intro": "Opening paragraph (shown in feed, ~200 chars).",
    "sections": [
        {
            "heading": "Section Title",
            "body": "Plain text paragraph.",    # Use "body" for plain text
        },
        {
            "heading": "Section with HTML",
            "body_html": "<p>Rich HTML content</p>",  # Use "body_html" for HTML
        },
    ],
    "conclusion": "Closing paragraph.",
    "tags": "transit,daily",                   # Comma-separated
    "keywords": "seo,keywords,here",
    "meta_title": "SEO Title | big3.me",       # Under 60 chars
    "meta_description": "SEO description.",    # Under 160 chars
}
```

### 4. Publish to Supabase
```bash
python scripts/publish_post.py scripts/posts/<slug>.py
```

This inserts directly into the `news_posts` table via Supabase REST API.
Requires env vars: `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`.

### 5. Verify
Check that the post is live: `https://big3.me/news/<slug>`

## news_posts Table Schema

| Column | Type | Required | Notes |
|--------|------|----------|-------|
| id | uuid | auto | gen_random_uuid() |
| slug | text | yes | Unique, URL-safe |
| title | text | yes | |
| subtitle | text | no | |
| date | date | yes | Publication date |
| author | text | yes | Default: "Victoria" |
| status | text | yes | "published" or "draft" |
| intro | text | yes | Feed preview (~200 chars) |
| sections | jsonb | yes | Array of {heading, body/body_html} |
| conclusion | text | no | Closing paragraph |
| celebrity_name | text | no | For celebrity posts |
| celebrity_event | text | no | For celebrity posts |
| meta_title | text | no | SEO title |
| meta_description | text | no | SEO description |
| keywords | text | no | Comma-separated |
| tags | text | no | Comma-separated |
| og_image_url | text | no | Social preview image |
| hero_image_url | text | no | Post banner |
| published_at | timestamptz | yes | |
| created_at | timestamptz | yes | |
| updated_at | timestamptz | yes | |

## HTML Helpers

For sections with copyable code blocks, use `body_html` with this pattern:
```html
<div class="prompt-block">
  <button type="button" class="copy-btn" onclick="copyPrompt(this)">Copy</button>
  <pre>Your copyable text here</pre>
</div>
```

For bilingual posts, use lang badges and dividers:
```html
<hr class="lang-divider">
<p><span class="lang-badge">RU</span></p>
```

## Celebrity Transit Posts

Celebrity posts are high-engagement content. Follow this workflow:

### Finding celebrities
1. **Search trending news** — web search for celebrity events (weddings, awards, controversies, career milestones)
2. **Verify birth data** — search Astro-Databank (astro.com/astro-databank/) for the celebrity
   - ONLY use Rodden Rating **AA** (birth certificate) or **A** (from memory) data
   - Need: full birth date, birth time, birth place
   - SKIP if no verified birth time — transits to Moon/Ascendant won't be accurate
3. **Check if profile exists** — query Supabase: `GET /rest/v1/profiles?display_name=ilike.*Celebrity Name*`

### Adding celebrity to big3.me
Create a file `scripts/celebrities/<name>.py`:
```python
CELEBRITY = {
    "name": "Zendaya",
    "birth_date": "1996-09-01",
    "birth_time": "18:55",
    "timezone": "America/Los_Angeles",
    "location_name": "Oakland, CA",
    "latitude": 37.8044,
    "longitude": -122.2712,
    "rodden_rating": "AA",
    "astro_databank_url": "https://www.astro.com/astro-databank/Zendaya",
}
```
Then run:
```bash
python scripts/add_celebrity.py scripts/celebrities/<name>.py
```
This will:
- Compute natal chart via Swiss Ephemeris
- Insert into `natal_charts` + `profiles` tables via Supabase REST API
- Link to `hi@srgplus.com` user, set `is_featured: true`
- Print the profile ID and transits API URL

### Fetching celebrity transits
Once the profile exists, get their personal transits:
```bash
curl -s "https://big3.me/api/v1/profiles/<profile_id>/transits"
```
This returns transit-to-natal aspects with exact orbs and intensity scores.

### Writing the post
- Connect the trending event to specific transits (cause → cosmic correlation)
- Lead with the news hook, then explain the astrology
- Focus on 2-4 strongest transits (EXACT and STRONG)
- Include natal positions with degrees (e.g. "natal Saturn at 5° Aries")
- Set `celebrity_name` and `celebrity_event` fields in the post
- Tags: `celebrity,transit` + optional topic tags

### Example post structure
```python
POST = {
    "slug": "celebrity-name-event-transits-2026",
    "title": "Celebrity's Event: Transit Planet and the Theme",
    "subtitle": "One-line hook connecting event to key transit",
    "celebrity_name": "Celebrity Name",
    "celebrity_event": "Brief event description",
    "tags": "celebrity,transit",
    # ... sections analyzing 2-4 key transits
}
```

### Celebrity content rules
- NEVER fabricate birth data — only Astro-Databank AA/A ratings
- NEVER make health predictions or death predictions
- Frame challenging transits as growth opportunities
- Be respectful — analyze transits, don't judge the person
- Verify ALL transit claims against Swiss Ephemeris data
- Include a note if birth time is approximate (Rodden A vs AA)

## Content Rules
- All transit claims MUST match the cosmic-weather API data (real Swiss Ephemeris)
- Include degree positions and orbs when referencing transits
- Slug format: `topic-keyword-YYYY` or `topic-keyword-month-YYYY`
- No duplicate slugs — check before publishing
- Intro should be compelling — it shows as preview in the feed

## Data Verification Checklist

Before publishing ANY post, verify each of these:

### 1. Retrograde status (CRITICAL — common error source)
The cosmic-weather API returns retrograde data. ALWAYS check:
- Which planets are currently retrograde?
- Is any planet stationing (about to go Rx or direct)?
- NEVER say "no retrogrades" without confirming ALL planets are direct
- Mercury retrogrades ~3x/year — always double-check Mercury's status
- A stationing planet (speed near 0) is NOT the same as direct — call it "stationary"

### 2. Planet positions
- Cross-check ALL degree positions against the cosmic-weather API response
- Positions should match to within ~0.5° (planets move during the day)
- For slow planets (Jupiter–Pluto): positions change < 0.1°/day
- For fast planets (Moon): position changes ~13°/day — specify the date/time

### 3. Aspect claims
- Verify orbs by calculating: |planet1_longitude - planet2_longitude|
- Account for aspect angle (0° conjunction, 60° sextile, 90° square, 120° trine, 180° opposition)
- EXACT = orb < 1°, STRONG = 1-3°, APPLYING = 3-5°
- If you say "tightest aspect of the week" — confirm no other aspect has a smaller orb

### 4. Moon phase
- New Moon = Sun-Moon conjunction (0°)
- Waxing Crescent = 1-3 days after New Moon
- First Quarter = ~7 days after New Moon
- Full Moon = Sun-Moon opposition (180°)
- Moon sign changes every ~2.5 days — verify for the specific date

### 5. Timing claims
- "Building all week" — confirm the aspect is applying (orb decreasing) not separating
- "Exact on Friday" — verify the exact date from the API
- Station dates (Rx/direct) — use the `retrograde_index` data from the API

### 6. Completeness check (CRITICAL — common error: missing major aspects)
The cosmic-weather API returns ALL active sky aspects with orb ≤ 3°. Before writing:
- List ALL aspects from the API response, not just the 2-3 most obvious
- Cross-reference with what professional astrologers are highlighting this week
- Specifically check for these commonly missed aspects:
  - **Sun aspects to outer planets** (Pluto, Uranus) — always newsworthy
  - **Venus-Chiron conjunctions** — healing in relationships, highly discussed
  - **Mercury aspects** (especially trines/sextiles to Jupiter) — communication themes
  - **Saturn-Pluto aspects** (sextile, square, etc.) — generational power shifts
- You don't need to give every aspect a full section, but MENTION all major ones
- A weekly post should cover 5-7 aspects minimum, not just 3
- Ask: "What would a professional astrologer criticize as missing?"

### 7. Self-review before publish
Re-read the final post and ask:
- Did I make any blanket claims ("no retrogrades", "only trine this month") that need verification?
- Are all degree positions sourced from the API, not hallucinated?
- Would a professional astrologer find factual errors?
- Did I check ALL aspects from the API, or did I cherry-pick only the obvious ones?
- Compare against 2-3 astrology sites (cafeastrology.com, elsaelsa.com, Patrick Arundell) — am I missing something they all mention?
