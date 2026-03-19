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
