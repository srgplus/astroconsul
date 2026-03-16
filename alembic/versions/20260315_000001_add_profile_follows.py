"""Add profile_follows table for follow/subscribe model.

Revision ID: 20260315_000001
Revises: 20260313_000001
Create Date: 2026-03-15 00:00:01
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260315_000001"
down_revision = "20260313_000001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "profile_follows",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("user_id", sa.String(length=128), nullable=False),
        sa.Column("profile_id", sa.String(length=128), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["profile_id"], ["profiles.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "profile_id", name="uq_user_profile_follow"),
    )


def downgrade() -> None:
    op.drop_table("profile_follows")
