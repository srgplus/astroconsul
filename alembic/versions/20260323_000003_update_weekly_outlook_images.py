"""Update weekly cosmic outlook post with image URLs

Revision ID: 20260323_000003
Revises: 20260323_000002
Create Date: 2026-03-23
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import json

revision: str = "20260323_000003"
down_revision: str = "20260323_000002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SLUG = "weekly-cosmic-outlook-march-23-29-2026"
BASE = "https://penhmylyqxzxvjxrbxen.supabase.co/storage/v1/object/public/news-images"
COVER = f"{BASE}/{SLUG}/cover.png"

SECTION_IMAGES = {
    0: f"{BASE}/{SLUG}/section_0_week_at_a_glance.png",
    1: f"{BASE}/{SLUG}/section_1_visions.png",
    2: f"{BASE}/{SLUG}/section_2_reality_test.png",
    3: f"{BASE}/{SLUG}/section_3_flow_expansion.png",
}


def upgrade() -> None:
    conn = op.get_bind()

    # Set cover/og image
    conn.execute(
        sa.text(
            "UPDATE news_posts SET hero_image_url = :url, og_image_url = :url "
            "WHERE slug = :slug"
        ),
        {"url": COVER, "slug": SLUG},
    )

    # Update section images
    result = conn.execute(
        sa.text("SELECT sections FROM news_posts WHERE slug = :slug"),
        {"slug": SLUG},
    ).fetchone()

    if result and result[0]:
        sections = result[0] if isinstance(result[0], list) else json.loads(result[0])
        for idx, img_url in SECTION_IMAGES.items():
            if idx < len(sections):
                sections[idx]["image_url"] = img_url
                sections[idx]["image_alt"] = sections[idx].get("heading", "")
        conn.execute(
            sa.text("UPDATE news_posts SET sections = :sections WHERE slug = :slug"),
            {"sections": json.dumps(sections), "slug": SLUG},
        )


def downgrade() -> None:
    conn = op.get_bind()
    conn.execute(
        sa.text(
            "UPDATE news_posts SET hero_image_url = NULL, og_image_url = NULL "
            "WHERE slug = :slug"
        ),
        {"slug": SLUG},
    )
