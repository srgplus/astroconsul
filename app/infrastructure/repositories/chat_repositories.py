"""Chats: one account writing to another.

A chat is between two accounts, never between charts. A person can keep
several charts, and most of them are other people's: a mother's, a friend's,
a celebrity's the app keeps. Only one of them is the person: the chart they
marked as their own, the primary profile. So that chart is the only way to
anyone. A chart that is nobody's primary has no one behind it to answer, and
cannot be written to; an account without one cannot be written to at all,
and cannot write either, because nobody could write back. Each side is drawn
as their primary chart, the way every social list draws an account
(`account_cards`, where the primary wins).

What is kept is deliberately little: the text, who wrote it, when, and how
far each side has read. No attachments, no edits, no reactions. Unread is
counted from message ids rather than timestamps: ids only grow, while a clock
kept to the second would call a reply written in the same second as the visit
already read.

A block cuts a chat the way it cuts everything else. A chat across a block is
left out of the list and the badge, and nothing more can be sent into it. It
is not deleted: lifting the block brings it back as it was.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from sqlalchemy import and_, case, func, or_, select, union
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.sql.elements import ColumnElement

from app.infrastructure.persistence.models import (
    ChatMessageModel,
    ChatModel,
    ProfileFollowModel,
    ProfileModel,
    UserBlockModel,
    UserModel,
)
from app.infrastructure.repositories.social_repositories import (
    FileSocialRepository,
    account_cards,
    blocked_account_ids,
)
from app.infrastructure.repositories.sqlalchemy_repositories import _isoformat_z, _now_utc, ensure_user

# Messages per page: the screen opens on the newest page and asks for the one
# before it only when scrolled to the top.
PAGE_SIZE = 50

# Messages after a given one, for a screen catching up on what came in while
# it was looking. More than this and it asks again at once.
CATCH_UP_LIMIT = 200

# Chats in the list. It is a list of conversations, not an archive.
CHATS_LIMIT = 100


class ChatNotFound(LookupError):
    """No such chat, or the account asking is not one of its two people. The
    same answer either way: a chat is nobody else's business."""


def ordered_pair(first: str, second: str) -> tuple[str, str]:
    """The two accounts of a chat as stored: the smaller id first, so the
    pair has one chat whoever of them wrote first."""
    return (first, second) if first <= second else (second, first)


def _is_member(chat: ChatModel, user_id: str) -> bool:
    return user_id in (chat.user_a_id, chat.user_b_id)


def _peer(chat: ChatModel, user_id: str) -> str:
    """The other person, for a chat the account is known to be in."""
    return chat.user_b_id if chat.user_a_id == user_id else chat.user_a_id


def _read_marker(user_id: str) -> ColumnElement[Any]:
    """The last message this account has read in a chat, in SQL: whichever of
    the two columns is its side."""
    return case((ChatModel.user_a_id == user_id, ChatModel.a_read_id), else_=ChatModel.b_read_id)


def _stamp(value: datetime) -> str:
    """A stored timestamp as the API spells one. SQLite hands them back
    without a zone; everything here is UTC."""
    aware = value if value.tzinfo is not None else value.replace(tzinfo=UTC)
    return _isoformat_z(aware)


def _message(message: ChatMessageModel, viewer_id: str) -> dict[str, Any]:
    return {
        "id": message.id,
        "body": message.body,
        "is_mine": message.sender_id == viewer_id,
        "created_at": _stamp(message.created_at),
    }


class SqlAlchemyChatRepository:
    def __init__(self, session_factory: sessionmaker[Session]):
        self.session_factory = session_factory

    # MARK: - Chats

    def open_chat(self, user_id: str, peer_id: str) -> dict[str, Any]:
        """The chat between two accounts, made the first time either asks.
        Opening one shows nobody anything: it lists nowhere, on either side,
        until there is a message in it."""
        first, second = ordered_pair(user_id, peer_id)
        with self.session_factory() as session:
            chat = self._find(session, first, second)
            if chat is None:
                ensure_user(session, user_id)
                chat = ChatModel(user_a_id=first, user_b_id=second, created_at=_now_utc())
                session.add(chat)
                try:
                    session.commit()
                except IntegrityError:
                    # Both of them opened it in the same moment; the other
                    # request's row is the chat.
                    session.rollback()
                    chat = self._find(session, first, second)
                    if chat is None:
                        raise
            return self._summaries(session, user_id, [chat])[0]

    @staticmethod
    def _find(session: Session, first: str, second: str) -> ChatModel | None:
        return session.execute(
            select(ChatModel).where(ChatModel.user_a_id == first, ChatModel.user_b_id == second)
        ).scalar_one_or_none()

    @staticmethod
    def _member_chat(session: Session, user_id: str, chat_id: int) -> ChatModel:
        chat = session.get(ChatModel, chat_id)
        if chat is None or not _is_member(chat, user_id):
            raise ChatNotFound(chat_id)
        return chat

    def peer_of(self, user_id: str, chat_id: int) -> str:
        """Who is on the other side of a chat the account is in."""
        with self.session_factory() as session:
            return _peer(self._member_chat(session, user_id, chat_id), user_id)

    def primary_profile_of(self, user_id: str) -> str | None:
        """The chart this account marked as its own, while it still has it:
        the only way anyone writes to the account, and the face it writes
        with."""
        with self.session_factory() as session:
            return session.execute(
                select(ProfileModel.id)
                .join(UserModel, UserModel.primary_profile_id == ProfileModel.id)
                .where(UserModel.id == user_id, ProfileModel.user_id == user_id)
            ).scalar_one_or_none()

    def list_chats(self, user_id: str, *, limit: int = CHATS_LIMIT) -> dict[str, Any]:
        """Every chat with a message in it, the most recent first, less those
        across a block."""
        with self.session_factory() as session:
            blocked = blocked_account_ids(session, user_id)
            chats = (
                session.execute(
                    select(ChatModel)
                    .where(
                        or_(ChatModel.user_a_id == user_id, ChatModel.user_b_id == user_id),
                        ChatModel.last_message_id.is_not(None),
                    )
                    .order_by(ChatModel.last_message_id.desc())
                    .limit(limit)
                )
                .scalars()
                .all()
            )
            visible = [chat for chat in chats if _peer(chat, user_id) not in blocked]
            return {
                "chats": self._summaries(session, user_id, visible),
                "unread_count": self._unread_count(session, user_id),
            }

    def _summaries(self, session: Session, user_id: str, chats: list[ChatModel]) -> list[dict[str, Any]]:
        """A row of the list for each chat: the person, the last message, how
        many of theirs are unread, and how far they have read yours. A few
        queries for the whole list rather than a few per row."""
        if not chats:
            return []
        ids = [chat.id for chat in chats]

        newest = [chat.last_message_id for chat in chats if chat.last_message_id is not None]
        last = {
            message.chat_id: message
            for message in session.execute(select(ChatMessageModel).where(ChatMessageModel.id.in_(newest))).scalars()
        }

        unread = {
            chat_id: int(total)
            for chat_id, total in session.execute(
                select(ChatMessageModel.chat_id, func.count())
                .join(ChatModel, ChatModel.id == ChatMessageModel.chat_id)
                .where(
                    ChatMessageModel.chat_id.in_(ids),
                    ChatMessageModel.sender_id != user_id,
                    ChatMessageModel.id > func.coalesce(_read_marker(user_id), 0),
                )
                .group_by(ChatMessageModel.chat_id)
            ).all()
        }

        cards = account_cards(session, {_peer(chat, user_id) for chat in chats})
        rows = []
        for chat in chats:
            message = last.get(chat.id)
            rows.append(
                {
                    "chat_id": chat.id,
                    "peer": cards[_peer(chat, user_id)],
                    "last_message": _message(message, user_id) if message is not None else None,
                    "unread_count": unread.get(chat.id, 0),
                    # How far the other side has read, for the "Read" under
                    # the last message you sent.
                    "peer_read_id": chat.b_read_id if chat.user_a_id == user_id else chat.a_read_id,
                    "updated_at": _stamp(message.created_at if message is not None else chat.created_at),
                }
            )
        return rows

    # MARK: - Messages

    def list_messages(
        self,
        user_id: str,
        chat_id: int,
        *,
        before: int | None = None,
        after: int | None = None,
        limit: int = PAGE_SIZE,
    ) -> dict[str, Any]:
        """Messages of one chat, oldest first.

        Without `after`: the newest page, or the page before `before`, and
        `has_more` says whether there is older history still. With `after`:
        what came in after the newest message on screen, and `has_more` says
        whether even more came in than one answer holds."""
        with self.session_factory() as session:
            chat = self._member_chat(session, user_id, chat_id)
            query = select(ChatMessageModel).where(ChatMessageModel.chat_id == chat_id)
            if after is not None:
                rows = list(
                    session.execute(
                        query.where(ChatMessageModel.id > after).order_by(ChatMessageModel.id).limit(CATCH_UP_LIMIT + 1)
                    ).scalars()
                )
                has_more = len(rows) > CATCH_UP_LIMIT
                rows = rows[:CATCH_UP_LIMIT]
            else:
                if before is not None:
                    query = query.where(ChatMessageModel.id < before)
                rows = list(session.execute(query.order_by(ChatMessageModel.id.desc()).limit(limit + 1)).scalars())
                has_more = len(rows) > limit
                rows = list(reversed(rows[:limit]))
            return {
                "chat": self._summaries(session, user_id, [chat])[0],
                "messages": [_message(message, user_id) for message in rows],
                "has_more": has_more,
            }

    def send_message(self, user_id: str, chat_id: int, body: str) -> dict[str, Any]:
        """Adds a message and moves the chat to the top of both lists.

        Writing one also reads the chat up to it: whoever answers has seen
        what they are answering."""
        with self.session_factory() as session:
            chat = self._member_chat(session, user_id, chat_id)
            now = _now_utc()
            message = ChatMessageModel(chat_id=chat_id, sender_id=user_id, body=body, created_at=now)
            session.add(message)
            session.flush()
            chat.last_message_id = message.id
            if chat.user_a_id == user_id:
                chat.a_read_id = message.id
            else:
                chat.b_read_id = message.id
            session.commit()
            return _message(message, user_id)

    def mark_read(self, user_id: str, chat_id: int, up_to: int | None = None) -> int:
        """Reads the chat up to `up_to`, the newest message the screen shows,
        or to its newest message without one. Never backwards. Answers the
        unread count that is left across every chat, for the badge."""
        with self.session_factory() as session:
            chat = self._member_chat(session, user_id, chat_id)
            newest = chat.last_message_id
            if newest is not None:
                target = newest if up_to is None else min(up_to, newest)
                if chat.user_a_id == user_id:
                    if chat.a_read_id is None or target > chat.a_read_id:
                        chat.a_read_id = target
                elif chat.b_read_id is None or target > chat.b_read_id:
                    chat.b_read_id = target
                session.commit()
            return self._unread_count(session, user_id)

    def _unread_count(self, session: Session, user_id: str) -> int:
        """Messages to this account it has not read yet, in every chat, less
        anyone across a block. One query: the badge asks on every return to
        the app."""
        blocked = union(
            select(UserBlockModel.blocked_id).where(UserBlockModel.blocker_id == user_id),
            select(UserBlockModel.blocker_id).where(UserBlockModel.blocked_id == user_id),
        )
        return int(
            session.execute(
                select(func.count())
                .select_from(ChatMessageModel)
                .join(ChatModel, ChatModel.id == ChatMessageModel.chat_id)
                .where(
                    or_(ChatModel.user_a_id == user_id, ChatModel.user_b_id == user_id),
                    ChatMessageModel.sender_id != user_id,
                    ChatMessageModel.sender_id.not_in(blocked),
                    ChatMessageModel.id > func.coalesce(_read_marker(user_id), 0),
                )
            ).scalar_one()
        )

    def unread_count(self, user_id: str) -> int:
        with self.session_factory() as session:
            return self._unread_count(session, user_id)

    # MARK: - People

    def contacts(self, user_id: str) -> list[dict[str, Any]]:
        """Who a new chat can be started with from the list, as cards: the
        people whose own chart the account follows, and the people following
        any of its charts. Only those with a chart of their own, which is
        what they are written to through, and less anyone across a block.

        Following a chart kept for somebody else, a celebrity's or a
        mother's, puts nobody here: the person to write to is their own
        chart."""
        with self.session_factory() as session:
            followed_owners = (
                select(ProfileModel.user_id)
                .join(ProfileFollowModel, ProfileFollowModel.profile_id == ProfileModel.id)
                .join(UserModel, UserModel.id == ProfileModel.user_id)
                .where(ProfileFollowModel.user_id == user_id, UserModel.primary_profile_id == ProfileModel.id)
            )
            followers = (
                select(ProfileFollowModel.user_id)
                .join(ProfileModel, ProfileModel.id == ProfileFollowModel.profile_id)
                .where(ProfileModel.user_id == user_id)
            )
            ids = set(session.execute(union(followed_owners, followers)).scalars())
            ids.discard(user_id)
            ids -= blocked_account_ids(session, user_id)
            if not ids:
                return []
            with_primary = set(
                session.execute(
                    select(UserModel.id)
                    .join(
                        ProfileModel,
                        and_(ProfileModel.id == UserModel.primary_profile_id, ProfileModel.user_id == UserModel.id),
                    )
                    .where(UserModel.id.in_(ids))
                ).scalars()
            )
            people = list(account_cards(session, with_primary).values())
            people.sort(key=lambda card: str(card.get("profile_name") or "").casefold())
            return people


class FileChatRepository:
    """The same chats for file persistence, which is local development only.

    One JSON file holds chats and messages. Contacts come from the charts the
    account follows alone: the follows file has no reverse index, so the
    people following yours are not found here.
    """

    def __init__(self, profiles: Any, social: FileSocialRepository, path: Path | None = None):
        self.profiles = profiles
        self.social = social
        self.path = path or Path("profiles/_chats.json")

    def _load(self) -> dict[str, Any]:
        if self.path.exists():
            try:
                data: dict[str, Any] = json.loads(self.path.read_text(encoding="utf-8"))
                return data
            except (json.JSONDecodeError, OSError):
                pass
        return {"chats": [], "messages": [], "next_id": 1}

    def _save(self, data: dict[str, Any]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(data, indent=2), encoding="utf-8")

    def _next_id(self, data: dict[str, Any]) -> int:
        value = int(data.get("next_id", 1))
        data["next_id"] = value + 1
        return value

    @staticmethod
    def _member_chat(data: dict[str, Any], user_id: str, chat_id: int) -> dict[str, Any]:
        chat: dict[str, Any]
        for chat in data["chats"]:
            if chat["id"] == chat_id and user_id in (chat["a"], chat["b"]):
                return chat
        raise ChatNotFound(chat_id)

    @staticmethod
    def _peer(chat: dict[str, Any], user_id: str) -> str:
        return str(chat["b"] if chat["a"] == user_id else chat["a"])

    @staticmethod
    def _read(chat: dict[str, Any], user_id: str) -> int:
        return int(chat.get("a_read" if chat["a"] == user_id else "b_read") or 0)

    @staticmethod
    def _message(message: dict[str, Any], viewer_id: str) -> dict[str, Any]:
        return {
            "id": message["id"],
            "body": message["body"],
            "is_mine": message["sender_id"] == viewer_id,
            "created_at": message["created_at"],
        }

    def _summary(self, data: dict[str, Any], chat: dict[str, Any], user_id: str) -> dict[str, Any]:
        messages = [m for m in data["messages"] if m["chat_id"] == chat["id"]]
        read = self._read(chat, user_id)
        peer = self._peer(chat, user_id)
        return {
            "chat_id": chat["id"],
            "peer": self.social.card_for(peer),
            "last_message": self._message(messages[-1], user_id) if messages else None,
            "unread_count": sum(1 for m in messages if m["sender_id"] != user_id and m["id"] > read),
            "peer_read_id": chat.get("b_read" if chat["a"] == user_id else "a_read"),
            "updated_at": messages[-1]["created_at"] if messages else chat["created_at"],
        }

    def open_chat(self, user_id: str, peer_id: str) -> dict[str, Any]:
        first, second = ordered_pair(user_id, peer_id)
        data = self._load()
        chat = next((c for c in data["chats"] if c["a"] == first and c["b"] == second), None)
        if chat is None:
            chat = {
                "id": self._next_id(data),
                "a": first,
                "b": second,
                "a_read": None,
                "b_read": None,
                "last_message_id": None,
                "created_at": _isoformat_z(_now_utc()),
            }
            data["chats"].append(chat)
            self._save(data)
        return self._summary(data, chat, user_id)

    def peer_of(self, user_id: str, chat_id: int) -> str:
        return self._peer(self._member_chat(self._load(), user_id, chat_id), user_id)

    def primary_profile_of(self, user_id: str) -> str | None:
        # Local development keeps no primary; the first chart stands in, the
        # same one the file card draws the account as.
        profile_id = self.social.card_for(user_id)["profile_id"]
        return str(profile_id) if profile_id else None

    def list_chats(self, user_id: str, *, limit: int = CHATS_LIMIT) -> dict[str, Any]:
        data = self._load()
        blocked = self.social.blocked_user_ids(user_id)
        chats = [
            chat
            for chat in data["chats"]
            if user_id in (chat["a"], chat["b"])
            and chat.get("last_message_id")
            and self._peer(chat, user_id) not in blocked
        ]
        chats.sort(key=lambda chat: int(chat["last_message_id"]), reverse=True)
        return {
            "chats": [self._summary(data, chat, user_id) for chat in chats[:limit]],
            "unread_count": self.unread_count(user_id),
        }

    def list_messages(
        self,
        user_id: str,
        chat_id: int,
        *,
        before: int | None = None,
        after: int | None = None,
        limit: int = PAGE_SIZE,
    ) -> dict[str, Any]:
        data = self._load()
        chat = self._member_chat(data, user_id, chat_id)
        messages = [m for m in data["messages"] if m["chat_id"] == chat_id]
        if after is not None:
            newer = [m for m in messages if m["id"] > after]
            page, has_more = newer[:CATCH_UP_LIMIT], len(newer) > CATCH_UP_LIMIT
        else:
            older = [m for m in messages if before is None or m["id"] < before]
            page, has_more = older[-limit:], len(older) > limit
        return {
            "chat": self._summary(data, chat, user_id),
            "messages": [self._message(m, user_id) for m in page],
            "has_more": has_more,
        }

    def send_message(self, user_id: str, chat_id: int, body: str) -> dict[str, Any]:
        data = self._load()
        chat = self._member_chat(data, user_id, chat_id)
        now = _isoformat_z(_now_utc())
        message = {"id": self._next_id(data), "chat_id": chat_id, "sender_id": user_id, "body": body, "created_at": now}
        data["messages"].append(message)
        chat["last_message_id"] = message["id"]
        chat["a_read" if chat["a"] == user_id else "b_read"] = message["id"]
        self._save(data)
        return self._message(message, user_id)

    def mark_read(self, user_id: str, chat_id: int, up_to: int | None = None) -> int:
        data = self._load()
        chat = self._member_chat(data, user_id, chat_id)
        ids = [m["id"] for m in data["messages"] if m["chat_id"] == chat_id]
        if ids:
            target = max(ids) if up_to is None else min(up_to, max(ids))
            key = "a_read" if chat["a"] == user_id else "b_read"
            if target > int(chat.get(key) or 0):
                chat[key] = target
                self._save(data)
        return self.unread_count(user_id)

    def unread_count(self, user_id: str) -> int:
        data = self._load()
        blocked = self.social.blocked_user_ids(user_id)
        total = 0
        for chat in data["chats"]:
            if user_id not in (chat["a"], chat["b"]) or self._peer(chat, user_id) in blocked:
                continue
            read = self._read(chat, user_id)
            total += sum(
                1
                for m in data["messages"]
                if m["chat_id"] == chat["id"] and m["sender_id"] != user_id and m["id"] > read
            )
        return total

    def contacts(self, user_id: str) -> list[dict[str, Any]]:
        blocked = self.social.blocked_user_ids(user_id)
        owners = {
            owner
            for summary in self.profiles.list_followed(user_id)
            if (owner := self.profiles.get_owner_user_id(summary["profile_id"]))
            and owner != user_id
            and self.primary_profile_of(owner) == summary["profile_id"]
        }
        people = [self.social.card_for(owner) for owner in owners - blocked]
        people.sort(key=lambda card: str(card.get("profile_name") or "").casefold())
        return people
