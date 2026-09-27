"""Index the two columns every social read looks up by.

Activity, its unread badge, the followers list and each chart's followers
count all start from "the charts this account owns" (`profiles.user_id`) and
"the follows on these charts" (`profile_follows.profile_id`). Postgres does
not index a foreign key by itself, and neither column had one, so each of
those reads scanned both tables whole. Small tables today; the badge is asked
on every return to the app, so it grows with everyone at once.

`profile_follows` already has (user_id, profile_id) unique, which serves the
other direction — the charts an account follows.

Revision ID: 20260927_000003
Revises: 20260927_000002
Create Date: 2026-09-27
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260927_000003"
down_revision = "20260927_000002"
branch_labels = None
depends_on = None


INDEXES = (
    ("ix_profiles_user_id", "profiles", ["user_id"]),
    ("ix_profile_follows_profile_id", "profile_follows", ["profile_id"]),
)


def _existing_indexes(table: str) -> set[str]:
    return {index["name"] for index in sa.inspect(op.get_bind()).get_indexes(table)}


def upgrade() -> None:
    # Checks first, like the revisions before it: a replay must not be able to
    # block the chain on "already exists".
    for name, table, columns in INDEXES:
        if name not in _existing_indexes(table):
            op.create_index(name, table, columns)


def downgrade() -> None:
    for name, table, _ in INDEXES:
        if name in _existing_indexes(table):
            op.drop_index(name, table_name=table)
