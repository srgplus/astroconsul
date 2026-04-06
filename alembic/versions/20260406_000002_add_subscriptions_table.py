"""Add subscriptions table for Pro paywall

Revision ID: 20260406_000002
Revises: 20260406_000001
Create Date: 2026-04-06
"""

from alembic import op
import sqlalchemy as sa

revision = "20260406_000002"
down_revision = "20260406_000001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "subscriptions",
        sa.Column("id", sa.String(128), primary_key=True),
        sa.Column("user_id", sa.String(128), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("plan", sa.String(20), nullable=False, server_default="free"),
        sa.Column("payment_provider", sa.String(20), nullable=True),
        sa.Column("transaction_id", sa.String(255), nullable=True),
        sa.Column("amount", sa.Integer, nullable=True),
        sa.Column("currency", sa.String(3), server_default="USD"),
        sa.Column("started_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_active", sa.Boolean, server_default="true"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("idx_subscriptions_user_active", "subscriptions", ["user_id", "is_active"])


def downgrade() -> None:
    op.drop_index("idx_subscriptions_user_active")
    op.drop_table("subscriptions")
