#!/usr/bin/env python3
"""Update existing news posts with verified ephemeris data.

Run this once on production to replace the original posts that contained
incorrect/fabricated transit claims. The seed_news.py file has also been
updated, so fresh deployments will get the corrected content automatically.

Usage:
    python scripts/update_news_posts.py
"""

import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import get_settings
from app.infrastructure.persistence.models import NewsPostModel
from app.infrastructure.persistence.session import database_is_enabled, session_scope

# Import the corrected post data
from scripts.seed_news import SEED_POSTS


def main():
    settings = get_settings()
    if not database_is_enabled(settings):
        print("Database not enabled. Set ASTRO_CONSUL_PERSISTENCE_BACKEND=database")
        return

    now = datetime.now(timezone.utc)

    with session_scope(settings) as session:
        from sqlalchemy import select

        for post_data in SEED_POSTS:
            slug = post_data["slug"]
            existing = session.execute(
                select(NewsPostModel).where(NewsPostModel.slug == slug)
            ).scalar_one_or_none()

            if not existing:
                print(f"  NOT FOUND: {slug} (run seed_news.py first)")
                continue

            # Update all content fields
            existing.title = post_data["title"]
            existing.subtitle = post_data["subtitle"]
            existing.intro = post_data["intro"]
            existing.sections = post_data["sections"]
            existing.conclusion = post_data["conclusion"]
            existing.meta_title = post_data["meta_title"]
            existing.meta_description = post_data["meta_description"]
            existing.keywords = post_data["keywords"]
            existing.updated_at = now

            print(f"  UPDATED: {slug}")

    print("Done. All posts now contain verified ephemeris data.")


if __name__ == "__main__":
    main()
