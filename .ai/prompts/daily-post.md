# Daily Astrology Post — Prompt Template

Copy and paste this into a new Claude Code session to generate today's post.

---

Generate and publish today's astrology blog post for big3.me/news with branded images.

Skills to use:
- .claude/skills/astro-content-generator/SKILL.md — for content generation and publishing
- .claude/skills/big3me-content-design/SKILL.md — for visual design system reference

Steps:
1. Read .ai/SKILL.md and .ai/CHANGELOG.ai.md for context
2. Fetch real transit data via WebFetch: https://big3.me/api/v1/public/cosmic-weather?date=YYYY-MM-DD (use today's date)
3. Check existing posts: query Supabase news_posts table via migration files to avoid duplicates for today
4. Pick content type based on transit data (moon phase, retrogrades, notable aspects)
5. Cross-reference with professional astrology sources (cafeastrology.com, elsaelsa.com) via WebFetch
6. Create post file in scripts/posts/ following the skill's schema
7. Publish post: python scripts/publish_post.py scripts/posts/<slug>.py
   - If no internet (sandbox), generate SQL INSERT and create an alembic migration instead
8. Generate branded HTML cards in tmp/post-images/ (cover.html + section_*.html)
   - Format: 1080×1350 (4:5 portrait, Instagram-style cards)
   - Style: social media cards (bold text, gradients, cosmic theme) — NOT web pages
   - Use the big3.me design system from .claude/skills/big3me-content-design/SKILL.md
9. Create tmp/post-images/slug.txt containing ONLY the post slug (one line, no spaces)
10. Commit and push ALL files (post script + HTML cards + slug.txt) to your claude/* branch
11. GitHub Action will automatically: render HTML→PNG via Playwright, upload to Supabase Storage, update post record

Env vars available: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

Content rules:
- Author: Victoria
- Don't reference specific AI brands (use "AI chatbot" not "Claude/ChatGPT")
- All transit claims must be verified against Swiss Ephemeris
- Tags: comma-separated (e.g. "transit,weekly" or "celebrity,transit")
