"""Let an account keep its followers and following counts to itself.

Every chart now shows how many follow it and how many its owner follows, on
other people's pages too, the way a social app shows them. This is the switch
behind Settings > Community that hides both numbers from everyone but the
owner.

A revision of its own rather than a line in 20260927_000001: that one shipped
first and ran on production before this code existed.

Revision ID: 20260927_000002
Revises: 20260927_000001
Create Date: 2026-09-27
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260927_000002"
down_revision = "20260927_000001"
branch_labels = None
depends_on = None


def _existing_columns(table: str) -> set[str]:
    return {column["name"] for column in sa.inspect(op.get_bind()).get_columns(table)}


def upgrade() -> None:
    # Checks first, like the revisions before it: a replay must not be able to
    # block the chain on "already exists".
    if "hide_social_counts" not in _existing_columns("users"):
        # Not null with a server default: every existing account keeps showing
        # its counts, which is what it did before the switch existed.
        op.add_column(
            "users",
            sa.Column("hide_social_counts", sa.Boolean(), nullable=False, server_default=sa.false()),
        )


def downgrade() -> None:
    if "hide_social_counts" in _existing_columns("users"):
        op.drop_column("users", "hide_social_counts")
