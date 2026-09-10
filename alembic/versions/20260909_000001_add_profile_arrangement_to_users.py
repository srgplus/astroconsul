"""Add favourite profiles and manual profile order to users.

Both are the reader's arrangement of their own saved list — which profiles sit
in the Favourites group and what order the cards were dragged into — so they
belong on the user row next to `primary_profile_id` rather than on the
profiles, which are shared with everyone who follows them.

Revision ID: 20260909_000001
Revises: 20260406_000002
Create Date: 2026-09-09
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "20260909_000001"
down_revision = "20260406_000002"
branch_labels = None
depends_on = None

json_type = sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), "postgresql")


def upgrade() -> None:
    op.add_column("users", sa.Column("favorite_profile_ids", json_type, nullable=True))
    op.add_column("users", sa.Column("profile_order", json_type, nullable=True))


def downgrade() -> None:
    op.drop_column("users", "profile_order")
    op.drop_column("users", "favorite_profile_ids")
