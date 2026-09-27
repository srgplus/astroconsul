"""Add the social layer: likes, blocks, reports, and when Activity was last read.

Following already existed, and it went one way with nothing coming back: a
profile's owner never learned who followed them, and nobody could do anything
to a chart but read it. These tables are the other half — a like the owner
hears about, a block that works in both directions, and a report a person can
file against a profile, which App Review requires of anything calling itself a
social network (guideline 1.2).

Revision ID: 20260927_000001
Revises: 20260909_000001
Create Date: 2026-09-27
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260927_000001"
down_revision = "20260909_000001"
branch_labels = None
depends_on = None


def _existing_tables() -> set[str]:
    return set(sa.inspect(op.get_bind()).get_table_names())


def _existing_columns(table: str) -> set[str]:
    return {column["name"] for column in sa.inspect(op.get_bind()).get_columns(table)}


def upgrade() -> None:
    # Every step checks first, the way 20260909_000001 does: on 2026-09-09 a
    # revision that failed on "already exists" blocked the whole chain behind
    # it for months, and a replay of this one must not be able to do that.
    tables = _existing_tables()

    if "activity_seen_at" not in _existing_columns("users"):
        op.add_column("users", sa.Column("activity_seen_at", sa.DateTime(timezone=True), nullable=True))

    if "profile_likes" not in tables:
        op.create_table(
            "profile_likes",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("user_id", sa.String(length=128), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("profile_id", sa.String(length=128), sa.ForeignKey("profiles.id"), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint("user_id", "profile_id", name="uq_user_profile_like"),
        )
        op.create_index("ix_profile_likes_profile_id", "profile_likes", ["profile_id"])

    if "user_blocks" not in tables:
        op.create_table(
            "user_blocks",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("blocker_id", sa.String(length=128), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("blocked_id", sa.String(length=128), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint("blocker_id", "blocked_id", name="uq_user_block"),
        )
        op.create_index("ix_user_blocks_blocked_id", "user_blocks", ["blocked_id"])

    if "profile_reports" not in tables:
        op.create_table(
            "profile_reports",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("reporter_id", sa.String(length=128), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("profile_id", sa.String(length=128), nullable=False),
            sa.Column("reported_user_id", sa.String(length=128), nullable=True),
            sa.Column("profile_name", sa.String(length=255), nullable=True),
            sa.Column("profile_handle", sa.String(length=255), nullable=True),
            sa.Column("reason", sa.String(length=32), nullable=False),
            sa.Column("details", sa.Text(), nullable=True),
            sa.Column("status", sa.String(length=32), nullable=False, server_default="open"),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        )
        op.create_index("ix_profile_reports_profile_id", "profile_reports", ["profile_id"])


def downgrade() -> None:
    tables = _existing_tables()
    if "profile_reports" in tables:
        op.drop_index("ix_profile_reports_profile_id", table_name="profile_reports")
        op.drop_table("profile_reports")
    if "user_blocks" in tables:
        op.drop_index("ix_user_blocks_blocked_id", table_name="user_blocks")
        op.drop_table("user_blocks")
    if "profile_likes" in tables:
        op.drop_index("ix_profile_likes_profile_id", table_name="profile_likes")
        op.drop_table("profile_likes")
    if "activity_seen_at" in _existing_columns("users"):
        op.drop_column("users", "activity_seen_at")
