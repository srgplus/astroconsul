"""Initial Astro Consul persistence schema.

Revision ID: 20260313_000001
Revises:
Create Date: 2026-03-13 00:00:01
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "20260313_000001"
down_revision = None
branch_labels = None
depends_on = None

json_type = sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), "postgresql")


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.String(length=128), nullable=False),
        sa.Column("auth_subject", sa.String(length=255), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("status", sa.String(length=64), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("auth_subject"),
    )

    op.create_table(
        "natal_charts",
        sa.Column("id", sa.String(length=128), nullable=False),
        sa.Column("chart_hash", sa.String(length=64), nullable=False),
        sa.Column("house_system", sa.String(length=64), nullable=False),
        sa.Column("julian_day", sa.Float(), nullable=False),
        sa.Column("birth_input_json", json_type, nullable=True),
        sa.Column("chart_payload_json", json_type, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("chart_hash"),
    )

    op.create_table(
        "profiles",
        sa.Column("id", sa.String(length=128), nullable=False),
        sa.Column("user_id", sa.String(length=128), nullable=False),
        sa.Column("handle", sa.String(length=255), nullable=False),
        sa.Column("display_name", sa.String(length=255), nullable=False),
        sa.Column("birth_date", sa.Date(), nullable=False),
        sa.Column("birth_time", sa.Time(), nullable=False),
        sa.Column("timezone", sa.String(length=255), nullable=False),
        sa.Column("location_name", sa.String(length=255), nullable=True),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column("chart_id", sa.String(length=128), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["chart_id"], ["natal_charts.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("handle"),
    )

    op.create_table(
        "latest_transits",
        sa.Column("profile_id", sa.String(length=128), nullable=False),
        sa.Column("transit_date", sa.Date(), nullable=False),
        sa.Column("transit_time", sa.Time(), nullable=False),
        sa.Column("timezone", sa.String(length=255), nullable=False),
        sa.Column("location_name", sa.String(length=255), nullable=True),
        sa.Column("latitude", sa.Float(), nullable=True),
        sa.Column("longitude", sa.Float(), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["profile_id"], ["profiles.id"]),
        sa.PrimaryKeyConstraint("profile_id"),
    )

    op.create_table(
        "location_cache",
        sa.Column("query", sa.String(length=255), nullable=False),
        sa.Column("resolved_name", sa.String(length=255), nullable=False),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column("timezone", sa.String(length=255), nullable=False),
        sa.Column("provider", sa.String(length=255), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("query"),
    )


def downgrade() -> None:
    op.drop_table("location_cache")
    op.drop_table("latest_transits")
    op.drop_table("profiles")
    op.drop_table("natal_charts")
    op.drop_table("users")
