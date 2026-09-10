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


def _existing_columns() -> set[str]:
    inspector = sa.inspect(op.get_bind())
    return {column["name"] for column in inspector.get_columns("users")}


def upgrade() -> None:
    # Skips what is already there. These two columns were added by hand on
    # 2026-09-09 to end a live 500 — the chain in front of this revision was
    # blocked, so the code shipped without its schema — and a replay must not
    # fail on "column already exists" and block the chain all over again.
    existing = _existing_columns()
    if "favorite_profile_ids" not in existing:
        op.add_column("users", sa.Column("favorite_profile_ids", json_type, nullable=True))
    if "profile_order" not in existing:
        op.add_column("users", sa.Column("profile_order", json_type, nullable=True))


def downgrade() -> None:
    existing = _existing_columns()
    if "profile_order" in existing:
        op.drop_column("users", "profile_order")
    if "favorite_profile_ids" in existing:
        op.drop_column("users", "favorite_profile_ids")
