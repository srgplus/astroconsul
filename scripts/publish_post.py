#!/usr/bin/env python3
"""Publish a news post directly to Supabase via REST API.

Usage:
  1. Define your post in a Python file (see example at bottom)
  2. Run: SUPABASE_URL=https://xxx.supabase.co SUPABASE_KEY=your_service_role_key python scripts/publish_post.py post_file.py

Or set env vars in .env.local and run:
  python scripts/publish_post.py post_file.py

Environment variables:
  SUPABASE_URL   - Your Supabase project URL
  SUPABASE_KEY   - service_role key (NOT anon key) for write access
"""

import json
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError


def load_env_file():
    """Load .env.local from project root if it exists."""
    env_file = Path(__file__).resolve().parents[1] / ".env.local"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())


def supabase_insert(table: str, data: dict) -> dict:
    """Insert a row into Supabase via REST API."""
    url = os.environ["SUPABASE_URL"]
    key = os.environ["SUPABASE_KEY"]

    req = Request(
        f"{url}/rest/v1/{table}",
        data=json.dumps(data, ensure_ascii=False, default=str).encode("utf-8"),
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
        method="POST",
    )
    try:
        with urlopen(req) as resp:
            return json.loads(resp.read())
    except HTTPError as e:
        body = e.read().decode()
        print(f"ERROR {e.code}: {body}")
        sys.exit(1)


def supabase_upsert(table: str, data: dict) -> dict:
    """Upsert a row (insert or update on conflict)."""
    url = os.environ["SUPABASE_URL"]
    key = os.environ["SUPABASE_KEY"]

    req = Request(
        f"{url}/rest/v1/{table}",
        data=json.dumps(data, ensure_ascii=False, default=str).encode("utf-8"),
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation,resolution=merge-duplicates",
        },
        method="POST",
    )
    try:
        with urlopen(req) as resp:
            return json.loads(resp.read())
    except HTTPError as e:
        body = e.read().decode()
        print(f"ERROR {e.code}: {body}")
        sys.exit(1)


def prompt_block(text: str) -> str:
    """Wrap text in a styled code block with copy button."""
    return (
        '<div class="prompt-block">'
        '<button type="button" class="copy-btn" onclick="copyPrompt(this)">Copy</button>'
        f"<pre>{text}</pre>"
        "</div>"
    )


def publish(post: dict, upsert: bool = False):
    """Publish a post dict to Supabase."""
    load_env_file()

    if not os.environ.get("SUPABASE_URL") or not os.environ.get("SUPABASE_KEY"):
        print("Set SUPABASE_URL and SUPABASE_KEY env vars (or create .env.local)")
        print("SUPABASE_KEY should be the service_role key for write access")
        sys.exit(1)

    now = datetime.now(timezone.utc).isoformat()

    row = {
        "id": post.get("id", str(uuid.uuid4())),
        "slug": post["slug"],
        "title": post["title"],
        "subtitle": post.get("subtitle", ""),
        "date": str(post["date"]),
        "author": post.get("author", "Victoria"),
        "status": post.get("status", "published"),
        "intro": post["intro"],
        "sections": post.get("sections", []),
        "conclusion": post.get("conclusion", ""),
        "meta_title": post.get("meta_title", f"{post['title']} | big3.me"),
        "meta_description": post.get("meta_description", post["intro"][:160]),
        "keywords": post.get("keywords", ""),
        "tags": post.get("tags", ""),
        "published_at": post.get("published_at", now),
        "created_at": now,
        "updated_at": now,
    }

    if upsert:
        result = supabase_upsert("news_posts", row)
    else:
        result = supabase_insert("news_posts", row)

    print(f"Published: https://big3.me/news/{post['slug']}")
    return result


# ── Run from command line ──
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python scripts/publish_post.py <post_file.py>")
        print("")
        print("The post file should define a POST dict. Example:")
        print("  See scripts/posts/example_post.py")
        sys.exit(1)

    post_file = sys.argv[1]

    # Load post definition from file
    import importlib.util
    spec = importlib.util.spec_from_file_location("post_module", post_file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    if not hasattr(module, "POST"):
        print(f"ERROR: {post_file} must define a POST dict")
        sys.exit(1)

    upsert = "--upsert" in sys.argv
    publish(module.POST, upsert=upsert)
