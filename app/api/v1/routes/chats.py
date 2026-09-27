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
* past those, the owner's rule decides (`chat_rules.may_write`, today: you
  may write to someone who follows you), and whoever has been written to may
  always answer. A chat that already exists stays readable when the rule
  stops holding, but nothing more can be sent into it until it holds again.

What is sent goes through a word filter for slurs and sexual violence
(`moderation.message_is_objectionable`) and the anti-spam limits in
`chat_rules`: messages a minute and a day, new conversations a day.

The refusals are said in the language the app is read in: it sends it as
Accept-Language, and anything but Russian reads English.

The phone of the one written to hears about it through the pushes the social
layer set up (see `chat_push`).
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime, timedelta
from typing import Any

from fastapi import APIRouter, BackgroundTasks, Body, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from app.api.auth import get_current_user
from app.api.dependencies import get_repositories
from app.api.v1.routes.social import _load_profile, _owner, _social, guard_block
from app.application.services.chat_push import notify_message
from app.domain.chat_rules import MESSAGES_PER_DAY, MESSAGES_PER_MINUTE, NEW_CHATS_PER_DAY, may_write
from app.domain.moderation import message_is_objectionable
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

# Every sentence a chat route refuses with, in English and Russian. ASCII
# punctuation in the English, as in everything the app shows from here.
REFUSALS: dict[str, dict[str, str]] = {
    "empty": {"en": "A message needs some text.", "ru": "В сообщении нет текста."},
    "own_chart": {"en": "That is your own chart.", "ru": "Это ваша собственная карта."},
    "not_their_own": {
        "en": "Only a person's own chart can be written to, and this one is not its owner's own.",
        "ru": "Написать можно только через собственную карту человека, а эта карта не его.",
    },
    "no_primary": {
        "en": "Mark one of your charts as your own first: people write to you through it.",
        "ru": "Сначала отметьте одну из карт как свою: через неё вам пишут.",
    },
    "peer_no_chart": {
        "en": "This person has no chart of their own any more, so they can't be written to.",
        "ru": "У этого человека больше нет своей карты, поэтому ему нельзя написать.",
    },
    "you_blocked": {
        "en": "You blocked this person. Unblock them in Settings first.",
        "ru": "Вы заблокировали этого человека. Сначала разблокируйте его в Настройках.",
    },
    "not_following": {
        "en": "You can write to someone once they follow you.",
        "ru": "Написать можно тому, кто подписан на вас.",
    },
    "objectionable": {
        "en": "This message can't be sent: it has words that aren't allowed on big3.me. Please rephrase it.",
        "ru": "Это сообщение нельзя отправить: в нём есть слова, запрещённые на big3.me. Перефразируйте его.",
    },
    "per_minute": {
        "en": "You're sending messages too fast. Wait a minute and try again.",
        "ru": "Слишком много сообщений подряд. Подождите минуту и попробуйте снова.",
    },
    "per_day": {
        "en": "You've sent as many messages as a day allows. Try again tomorrow.",
        "ru": "Вы отправили столько сообщений, сколько можно за день. Попробуйте завтра.",
    },
    "new_chats": {
        "en": "You've started as many new chats as a day allows. Try again tomorrow.",
        "ru": "Вы начали столько новых чатов, сколько можно за день. Попробуйте завтра.",
    },
}


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


def _lang(request: Request) -> str:
    """The language the app is read in, from the first tag of its
    Accept-Language: "ru" for Russian, "en" for anything else."""
    first = request.headers.get("accept-language", "").split(",")[0].strip().lower()
    return "ru" if first.startswith("ru") else "en"


def _refusal(request: Request, status: int, key: str, headers: dict[str, str] | None = None) -> HTTPException:
    return HTTPException(status_code=status, detail=REFUSALS[key][_lang(request)], headers=headers)


def _require_own_primary(request: Request, chats: ChatRepository, user_id: str) -> None:
    if chats.primary_profile_of(user_id) is None:
        raise _refusal(request, NO_PRIMARY_STATUS, "no_primary")


def _require_may_write(request: Request, chats: ChatRepository, user_id: str, peer_id: str) -> None:
    """The owner's rule between the two, whatever it is today (`may_write`),
    and one thing no rule takes away: whoever has been written to may answer."""
    follows, followed_back = chats.follows_between(user_id, peer_id)
    if may_write(follows, followed_back) or chats.has_written(peer_id, user_id):
        return
    raise _refusal(request, 403, "not_following")


def _require_new_chat_allowed(request: Request, chats: ChatRepository, user_id: str, peer_id: str) -> None:
    """Starting a conversation counts against the day's new chats; writing
    into one that already has messages, whoever wrote first, does not."""
    if chats.has_conversation(user_id, peer_id):
        return
    since = datetime.now(UTC) - timedelta(days=1)
    if chats.chats_started_since(user_id, since) >= NEW_CHATS_PER_DAY:
        logger.warning("User %s reached the new chats limit (%s a day)", user_id, NEW_CHATS_PER_DAY)
        raise _refusal(request, 429, "new_chats", headers={"Retry-After": "3600"})


def _require_within_limits(request: Request, chats: ChatRepository, user_id: str, peer_id: str) -> None:
    """The anti-spam limits: messages a minute, messages a day, and a first
    message into a chat counting as a new conversation."""
    now = datetime.now(UTC)
    if chats.messages_sent_since(user_id, now - timedelta(minutes=1)) >= MESSAGES_PER_MINUTE:
        logger.warning("User %s reached the messages limit (%s a minute)", user_id, MESSAGES_PER_MINUTE)
        raise _refusal(request, 429, "per_minute", headers={"Retry-After": "60"})
    if chats.messages_sent_since(user_id, now - timedelta(days=1)) >= MESSAGES_PER_DAY:
        logger.warning("User %s reached the messages limit (%s a day)", user_id, MESSAGES_PER_DAY)
        raise _refusal(request, 429, "per_day", headers={"Retry-After": "3600"})
    _require_new_chat_allowed(request, chats, user_id, peer_id)


def _peer(request: Request, repos: RepositoryBundle, user_id: str, chat_id: int) -> str:
    """The other person in a chat the caller is in, stopped at a block.

    The blocker is told why and where to undo it; the blocked side gets the
    404 a chat that does not exist gets."""
    try:
        peer = _chats(repos).peer_of(user_id, chat_id)
    except ChatNotFound as exc:
        raise HTTPException(status_code=404, detail="Chat not found") from exc
    blocker = _social(repos).blocker_of(user_id, peer)
    if blocker == user_id:
        raise _refusal(request, 403, "you_blocked")
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
    """Who a new chat can be started with: the people the owner's rule lets
    the caller write to (they follow the caller), who have a chart of their
    own."""
    return {"people": _chats(repos).contacts(user["user_id"])}


@router.post("")
def open_chat(
    payload: OpenChatRequest,
    request: Request,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """The chat with the person whose own chart this is, made on first
    asking. It lists nowhere until a message is in it.

    The rule and the day's new chats are checked here as well as on
    sending, so a refusal comes before anything is typed."""
    chats = _chats(repos)
    user_id = user["user_id"]
    profile = _load_profile(repos, payload.profile_id)
    owner = _owner(profile)
    if owner == user_id:
        raise _refusal(request, 400, "own_chart")
    guard_block(_social(repos), user_id, profile)
    if chats.primary_profile_of(owner) != payload.profile_id:
        raise _refusal(request, 400, "not_their_own")
    _require_own_primary(request, chats, user_id)
    _require_may_write(request, chats, user_id, owner)
    _require_new_chat_allowed(request, chats, user_id, owner)
    return {"chat": chats.open_chat(user_id, owner)}


@router.get("/{chat_id}/messages")
def list_messages(
    chat_id: int,
    request: Request,
    before: int | None = Query(default=None, ge=1),
    after: int | None = Query(default=None, ge=0),
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """The newest page of a chat, the page before `before`, or whatever came
    after `after`: the screen polls with it while it is open. Reading marks
    nothing; the screen says what it showed.

    Readable whatever the follows between the two are now: the rule decides
    who may write, and what was written stays theirs to read."""
    _peer(request, repos, user["user_id"], chat_id)
    return _chats(repos).list_messages(user["user_id"], chat_id, before=before, after=after)


@router.post("/{chat_id}/messages")
def send_message(
    chat_id: int,
    payload: SendMessageRequest,
    background: BackgroundTasks,
    request: Request,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """Adds a message, once the two may still write to each other, the text
    passes the word filter and the sender is within the limits. Each refusal
    is a sentence the app shows under the message as it stands: 403 for the
    rule or a block, 422 for the words, 429 for the limits."""
    chats = _chats(repos)
    user_id = user["user_id"]
    body = payload.body.strip()
    if not body:
        raise _refusal(request, 422, "empty")
    peer = _peer(request, repos, user_id, chat_id)
    _require_own_primary(request, chats, user_id)
    if chats.primary_profile_of(peer) is None:
        raise _refusal(request, 400, "peer_no_chart")
    _require_may_write(request, chats, user_id, peer)
    if message_is_objectionable(body):
        logger.info("Message from %s into chat %s refused by the word filter", user_id, chat_id)
        raise _refusal(request, 422, "objectionable")
    _require_within_limits(request, chats, user_id, peer)
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
