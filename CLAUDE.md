# Astro Consul — Big3.me

Read `.ai/SKILL.md` before any task for full project context.

## Quick Reference
- **Stack:** FastAPI + React/Vite + Supabase PostgreSQL + Swiss Ephemeris
- **Domain:** big3.me (Cloudflare DNS → Railway)
- **Deploy:** Push to `claude/*` branch → GitHub Action auto-merges to main → Railway auto-deploys (see `.github/workflows/auto-merge-claude.yml`). Do NOT try to push directly to main — the proxy blocks it with 403.
- **Local backend:** `uvicorn app.main:app --port 8001`
- **Local frontend:** `cd frontend && npm run dev` (port 5173)
- **Build check:** `cd frontend && npm run build` (must pass before push)
- **Persistence:** `file` locally, `database` on Railway (env var `ASTRO_CONSUL_PERSISTENCE_BACKEND`)
- **Auth:** Disabled locally, Supabase Auth on prod

## Rules
- Always push to your `claude/*` branch after implementing — don't ask, just push (auto-merges to main via GitHub Action)
- Run `npm run build` before pushing
- Respond in Russian when user writes in Russian
- Use native `<button>` elements for clickable items in scroll containers (iOS fix)
- Grey spinner (#8e8e93), never purple
- Never silent-catch errors — always log
- Check `.ai/CHANGELOG.ai.md` for recent changes before starting work

## Publishing News Posts

To create and publish a blog post directly to big3.me/news (no deploy needed):

1. Create a post file in `scripts/posts/` (see `example_post.py` for template)
2. Use `body_html` in sections for rich content (code blocks, HTML formatting)
3. Use `prompt_block()` helper for copyable code blocks
4. Run: `python scripts/publish_post.py scripts/posts/my_post.py`
5. Use `--upsert` flag to update an existing post by slug

**If running in sandbox (no internet):** Create an Alembic migration instead of running publish_post.py. The migration will execute on Railway deploy.

**Requires env vars:** `SUPABASE_URL` and `SUPABASE_KEY` (service_role key).
See `.env.local.example` for values. If env vars are not set, generate SQL for manual paste into Supabase SQL Editor.

**Content rules:**
- Author: Victoria
- Don't reference specific AI brands (use "AI chatbot" not "Claude/ChatGPT")
- Use `prompt_block()` for copyable prompts
- Tags: comma-separated (e.g. "educational,guide" or "celebrity,transit")
- All transit claims must be verified against Swiss Ephemeris

## Post Images (Automated Pipeline)

Images for blog posts are generated and uploaded automatically via GitHub Action.

**How it works:**
1. Generate branded HTML cards in `tmp/post-images/` (cover.html + section_*.html)
2. Create `tmp/post-images/slug.txt` with the post slug (one line, no spaces)
3. Commit and push to your `claude/*` branch
4. GitHub Action (`.github/workflows/upload-post-images.yml`) automatically:
   - Renders HTML → PNG via Playwright
   - Uploads PNGs to Supabase Storage (bucket: `news-images`)
   - Updates the post record with image URLs

**Image format:**
- Size: 1080×1350 (4:5 portrait, Instagram-style)
- Style: social media cards (bold text, gradients, cosmic theme) — NOT web pages
- Reference: `.claude/skills/big3me-content-design/SKILL.md`

**Manual upload (fallback):** `python scripts/render_and_upload_images.py <slug> tmp/post-images/`

**Daily post prompt template:** See `.ai/prompts/daily-post.md`
