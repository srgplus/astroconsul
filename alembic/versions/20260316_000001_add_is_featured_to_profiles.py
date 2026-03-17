"""Add is_featured column to profiles table.

Revision ID: 20260316_000001
Revises: 20260315_000001
Create Date: 2026-03-16 00:00:01
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260316_000001"
down_revision = "20260315_000001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "profiles",
        sa.Column("is_featured", sa.Boolean(), nullable=False, server_default=sa.text("false")),
    )


def downgrade() -> None:
    op.drop_column("profiles", "is_featured")
