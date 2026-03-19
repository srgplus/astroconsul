"""Add primary_profile_id column to users table.

Revision ID: 20260319_000001
Revises: 20260316_000001
Create Date: 2026-03-19 00:00:01
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260319_000001"
down_revision = "20260316_000001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("primary_profile_id", sa.String(128), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "primary_profile_id")
