"""Add chats: one person writing to another, text only.

Likes and follows let one account do something to another's chart, and the
owner hears about it; nothing let two people say anything to each other.
These are the two tables a plain messenger needs, a chat per pair of accounts
and its messages, and a third push switch behind Settings > Community,
on by default like the other two.

Revision ID: 20260927_000005
Revises: 20260927_000004
Create Date: 2026-09-27
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260927_000005"
down_revision = "20260927_000004"
branch_labels = None
depends_on = None


def _existing_tables() -> set[str]:
    return set(sa.inspect(op.get_bind()).get_table_names())


def _existing_columns(table: str) -> set[str]:
    return {column["name"] for column in sa.inspect(op.get_bind()).get_columns(table)}


def upgrade() -> None:
    # Checks first, like the revisions before it: a replay must not be able to
    # block the chain on "already exists".
    if "push_messages" not in _existing_columns("users"):
        op.add_column("users", sa.Column("push_messages", sa.Boolean(), nullable=False, server_default=sa.true()))

    tables = _existing_tables()
    if "chats" not in tables:
        # The pair is stored smaller id first, so two people have one chat
        # whoever wrote first. What each side has read is a message id, and so
        # is the newest message the list is ordered by.
        op.create_table(
            "chats",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("user_a_id", sa.String(length=128), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("user_b_id", sa.String(length=128), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("a_read_id", sa.Integer(), nullable=True),
            sa.Column("b_read_id", sa.Integer(), nullable=True),
            sa.Column("last_message_id", sa.Integer(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint("user_a_id", "user_b_id", name="uq_chat_pair"),
        )
        # The unique pair serves "chats where I am a"; this serves "where I am b".
        op.create_index("ix_chats_user_b_id", "chats", ["user_b_id"])

    if "chat_messages" not in tables:
        op.create_table(
            "chat_messages",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("chat_id", sa.Integer(), sa.ForeignKey("chats.id"), nullable=False),
            sa.Column("sender_id", sa.String(length=128), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("body", sa.Text(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        )
        # Every read is the messages of one chat by id: the newest page, the
        # ones after the newest on screen, the ones before the oldest.
        op.create_index("ix_chat_messages_chat_id_id", "chat_messages", ["chat_id", "id"])


def downgrade() -> None:
    tables = _existing_tables()
    if "chat_messages" in tables:
        op.drop_index("ix_chat_messages_chat_id_id", table_name="chat_messages")
        op.drop_table("chat_messages")
    if "chats" in tables:
        op.drop_index("ix_chats_user_b_id", table_name="chats")
        op.drop_table("chats")
    if "push_messages" in _existing_columns("users"):
        op.drop_column("users", "push_messages")
