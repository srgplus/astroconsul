"""Push a like or a new follower to the chart owner's phone.

Until now a like or a follow only waited in Activity for the owner to open the
app. This is what a push needs on the server: the phones each account is
signed in on (their APNs tokens), and a switch per kind of event behind
Settings > Community, both on by default.

Revision ID: 20260927_000004
Revises: 20260927_000003
Create Date: 2026-09-27
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260927_000004"
down_revision = "20260927_000003"
branch_labels = None
depends_on = None


def _existing_tables() -> set[str]:
    return set(sa.inspect(op.get_bind()).get_table_names())


def _existing_columns(table: str) -> set[str]:
    return {column["name"] for column in sa.inspect(op.get_bind()).get_columns(table)}


def upgrade() -> None:
    # Checks first, like the revisions before it: a replay must not be able to
    # block the chain on "already exists".
    columns = _existing_columns("users")
    for name in ("push_likes", "push_follows"):
        if name not in columns:
            # Not null with a server default: every existing account starts
            # with pushes on, the way a new one does.
            op.add_column("users", sa.Column(name, sa.Boolean(), nullable=False, server_default=sa.true()))

    if "device_tokens" not in _existing_tables():
        op.create_table(
            "device_tokens",
            sa.Column("token", sa.String(length=200), primary_key=True),
            sa.Column("user_id", sa.String(length=128), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("environment", sa.String(length=16), nullable=False, server_default="production"),
            sa.Column("lang", sa.String(length=8), nullable=False, server_default="en"),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        )
        op.create_index("ix_device_tokens_user_id", "device_tokens", ["user_id"])


def downgrade() -> None:
    if "device_tokens" in _existing_tables():
        op.drop_index("ix_device_tokens_user_id", table_name="device_tokens")
        op.drop_table("device_tokens")
    columns = _existing_columns("users")
    for name in ("push_follows", "push_likes"):
        if name in columns:
            op.drop_column("users", name)
