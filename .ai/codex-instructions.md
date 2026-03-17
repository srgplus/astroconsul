# Codex Instructions — Big3.me (Astro Consul)

Read `SKILL.md` in this directory for full project context.
Read `CHANGELOG.ai.md` for recent changes before starting work.

## Quick Rules
- Backend: FastAPI, Python 3.11, Swiss Ephemeris
- Frontend: React 18 + TypeScript + Vite
- Database: Supabase PostgreSQL (prod), file-based (local)
- Always run `cd frontend && npm run build` before considering work done
- Use native `<button>` for clickable elements in scroll containers (iOS)
- Grey spinner (#8e8e93), not purple
- Natal aspects sort by planet priority, not orb
- i18n: support EN + RU
- Don't add unnecessary abstractions or over-engineer
