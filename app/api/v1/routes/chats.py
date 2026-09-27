"""The chat routes: the list, one chat, its messages, and who can be written to.

A plain messenger: text between two people and nothing else. Who may write to
whom follows from what a person is in this app, the chart they marked as
their own:

* a chat is started from somebody's primary profile and from nothing else.
  A chart kept for another person, a mother's or a celebrity's, has nobody
  behind it who would answer;
* whoever writes needs a primary profile too: without one the other side
  could neither see who wrote nor write back;
* a block closes the chat both ways and says nothing to the blocked side. To
  them the chat is simply not there, the way the blocker's charts are not;
* a message goes through the same word filter as a profile's name. One that
  fails it is not stored, and only its sender hears why.

The phone of the one written to hears about it through the pushes the social
layer set up (see `chat_push`).
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter, BackgroundTasks, Body, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.auth import get_current_user
from app.api.dependencies import get_repositories
from app.api.v1.routes.social import _load_profile, _owner, _social, guard_block
from app.application.services.chat_push import notify_message
from app.domain.moderation import check_message_text
from app.infrastructure.repositories.chat_repositories import ChatNotFound
from app.infrastructure.repositories.factory import RepositoryBundle
from app.infrastructure.repositories.protocols import ChatRepository

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/chats", tags=["chats"])

# Long enough for a letter, short enough that nobody pastes a book.
MESSAGE_MAX_LENGTH = 2000

# What the app is told when the account itself has no chart marked as its
# own. A status of its own, so the app can offer to pick one rather than
# print the sentence.
NO_PRIMARY_STATUS = 409

# What the app is told when a message has a word that may not be sent. The
# app draws it as "not sent" without offering to try again: the same words
# would fail the same way.
OBJECTIONABLE_STATUS = 422


class OpenChatRequest(BaseModel):
    # The chart the person was looking at, or picked among the people they
    # can write to. It has to be its owner's own.
    profile_id: str


class SendMessageRequest(BaseModel):
    body: str = Field(max_length=MESSAGE_MAX_LENGTH)


class ReadRequest(BaseModel):
    # The newest message on screen. Without one, everything so far.
    message_id: int | None = None


def _chats(repos: RepositoryBundle) -> ChatRepository:
    if repos.chats is None:
        raise HTTPException(status_code=503, detail="Chats are not available")
    return repos.chats


def _require_own_primary(chats: ChatRepository, user_id: str) -> None:
    if chats.primary_profile_of(user_id) is None:
        raise HTTPException(
            status_code=NO_PRIMARY_STATUS,
            detail="Mark one of your charts as your own first: people write to you through it.",
        )


def _peer(repos: RepositoryBundle, user_id: str, chat_id: int) -> str:
    """The other person in a chat the caller is in, stopped at a block.

    The blocker is told why and where to undo it; the blocked side gets the
    404 a chat that does not exist gets."""
    try:
        peer = _chats(repos).peer_of(user_id, chat_id)
    except ChatNotFound as exc:
        raise HTTPException(status_code=404, detail="Chat not found") from exc
    blocker = _social(repos).blocker_of(user_id, peer)
    if blocker == user_id:
        raise HTTPException(status_code=403, detail="You blocked this person. Unblock them in Settings first.")
    if blocker is not None:
        raise HTTPException(status_code=404, detail="Chat not found")
    return peer


@router.get("")
def list_chats(
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """Every chat with a message in it, the latest first, with how many of
    the other side's messages are unread in each and in all."""
    return _chats(repos).list_chats(user["user_id"])


@router.get("/unread")
def unread_chats(
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, int]:
    """Just the number on the chats button, for the home screen to ask on
    every return."""
    return {"unread_count": _chats(repos).unread_count(user["user_id"])}


@router.get("/contacts")
def chat_contacts(
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """Who a new chat can be started with: the people on the other side of a
    follow, either way, who have a chart of their own."""
    return {"people": _chats(repos).contacts(user["user_id"])}


@router.post("")
def open_chat(
    payload: OpenChatRequest,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """The chat with the person whose own chart this is, made on first
    asking. It lists nowhere until a message is in it."""
    chats = _chats(repos)
    user_id = user["user_id"]
    profile = _load_profile(repos, payload.profile_id)
    owner = _owner(profile)
    if owner == user_id:
        raise HTTPException(status_code=400, detail="That is your own chart.")
    guard_block(_social(repos), user_id, profile)
    if chats.primary_profile_of(owner) != payload.profile_id:
        raise HTTPException(
            status_code=400,
            detail="Only a person's own chart can be written to, and this one is not its owner's own.",
        )
    _require_own_primary(chats, user_id)
    return {"chat": chats.open_chat(user_id, owner)}


@router.get("/{chat_id}/messages")
def list_messages(
    chat_id: int,
    before: int | None = Query(default=None, ge=1),
    after: int | None = Query(default=None, ge=0),
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """The newest page of a chat, the page before `before`, or whatever came
    after `after`: the screen polls with it while it is open. Reading marks
    nothing; the screen says what it showed."""
    _peer(repos, user["user_id"], chat_id)
    return _chats(repos).list_messages(user["user_id"], chat_id, before=before, after=after)


@router.post("/{chat_id}/messages")
def send_message(
    chat_id: int,
    payload: SendMessageRequest,
    background: BackgroundTasks,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    chats = _chats(repos)
    user_id = user["user_id"]
    body = payload.body.strip()
    if not body:
        raise HTTPException(status_code=422, detail="A message needs some text.")
    peer = _peer(repos, user_id, chat_id)
    _require_own_primary(chats, user_id)
    if chats.primary_profile_of(peer) is None:
        raise HTTPException(
            status_code=400,
            detail="This person has no chart of their own any more, so they can't be written to.",
        )
    try:
        check_message_text(body)
    except ValueError as exc:
        # Who and where, never the words: the log is not a place to keep them.
        logger.info("Chat message refused by the word filter: user=%s chat=%s", user_id, chat_id)
        raise HTTPException(status_code=OBJECTIONABLE_STATUS, detail=str(exc)) from exc
    message = chats.send_message(user_id, chat_id, body)
    # After the response: the push is a nudge, and sending waits for nothing.
    background.add_task(notify_message, repos, user_id, peer, chat_id, message)
    return {"message": message}


@router.post("/{chat_id}/read")
def mark_read(
    chat_id: int,
    payload: ReadRequest | None = Body(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, int]:
    """The screen showed the chat up to `message_id`. Answers what is left
    unread across every chat, for the button's number."""
    try:
        unread = _chats(repos).mark_read(user["user_id"], chat_id, payload.message_id if payload else None)
    except ChatNotFound as exc:
        raise HTTPException(status_code=404, detail="Chat not found") from exc
    return {"unread_count": unread}
