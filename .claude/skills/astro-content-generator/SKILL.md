# Astro Content Generator Skill

Generate and publish astrology blog posts for big3.me/news.

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

## Content Rules
- All transit claims MUST match the cosmic-weather API data (real Swiss Ephemeris)
- Include degree positions and orbs when referencing transits
- Slug format: `topic-keyword-YYYY` or `topic-keyword-month-YYYY`
- No duplicate slugs — check before publishing
- Intro should be compelling — it shows as preview in the feed
