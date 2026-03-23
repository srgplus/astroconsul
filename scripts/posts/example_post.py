"""Example post definition.

Usage:
  SUPABASE_URL=https://penhmylyqxzxvjxrbxen.supabase.co \
  SUPABASE_KEY=your_service_role_key \
  python scripts/publish_post.py scripts/posts/example_post.py
"""

from datetime import date

# Import helper for code blocks with copy button
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from scripts.publish_post import prompt_block

POST = {
    "slug": "example-post-slug",
    "title": "Your Post Title Here",
    "subtitle": "A short subtitle",
    "date": date(2026, 3, 23),
    "author": "Victoria",
    "status": "published",  # or "draft"
    "intro": "Opening paragraph shown in the feed preview (first ~200 chars).",
    "sections": [
        {
            "heading": "Section with plain text",
            "body": "This is a plain text section. Use 'body' for simple paragraphs.",
        },
        {
            "heading": "Section with HTML",
            "body_html": (
                "<p>Use <strong>body_html</strong> for rich content.</p>"
                "<p>You can use any HTML here.</p>"
                + prompt_block("This is a copyable code block")
            ),
        },
    ],
    "conclusion": "Closing paragraph with CTA.",
    "tags": "educational,guide",
    "keywords": "keyword1,keyword2,keyword3",
    "meta_title": "SEO Title | big3.me",
    "meta_description": "SEO description for search results (under 160 chars).",
}
