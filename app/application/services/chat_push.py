"""A push for a new message: who wrote, and what, on the recipient's phone.

It rides on what the likes and follows already use: the APNs client in
`push_service` and the phones the social repository keeps for each account.
The banner is the sender's name over the text, the way Messages draws one,
and each chat stacks on its own in Notification Centre. The icon's badge is
everything unread in the app, Activity and messages together.

Every message is news, so there is no quiet period and no collapsing: two
messages are two banners. The recipient can switch them off in Settings.

It runs after the response has gone (FastAPI background task), so sending is
as fast with a push as without, and it never raises: a failure is logged.
"""

from __future__ import annotations

import logging
from typing import Any

from app.application.services.push_service import get_sender
from app.application.services.social_push import app_badge
from app.infrastructure.repositories.factory import RepositoryBundle

logger = logging.getLogger(__name__)

# How much of the text rides in the banner. A banner shows a few lines, and
# the payload APNs takes is 4 KB; the rest is one tap away.
PREVIEW_LENGTH = 180

SOMEONE = {"en": "A big3.me member", "ru": "Участник big3.me"}


def preview(body: str) -> str:
    text = body.strip()
    return text if len(text) <= PREVIEW_LENGTH else text[: PREVIEW_LENGTH - 1].rstrip() + "…"


def notify_message(
    repos: RepositoryBundle,
    sender_id: str,
    recipient_id: str,
    chat_id: int,
    message: dict[str, Any],
) -> None:
    try:
        _deliver(repos, sender_id, recipient_id, chat_id, message)
    except Exception:
        logger.exception("Message push for chat %s failed", chat_id)


def _deliver(
    repos: RepositoryBundle,
    sender_id: str,
    recipient_id: str,
    chat_id: int,
    message: dict[str, Any],
) -> None:
    social = repos.social
    if social is None or sender_id == recipient_id:
        return

    sender = get_sender()
    if sender is None:
        logger.info("Message push for chat %s not sent: APNs is not configured", chat_id)
        return

    if not social.social_settings(recipient_id).get("push_messages", True):
        return
    devices = social.devices_for(recipient_id)
    if not devices:
        return

    name = str(social.card_for(sender_id).get("profile_name") or "").strip()
    badge = app_badge(repos, recipient_id)

    for device in devices:
        payload = {
            "aps": {
                "alert": {
                    "title": name or SOMEONE.get(device.get("lang", "en"), SOMEONE["en"]),
                    "body": preview(str(message.get("body") or "")),
                },
                "sound": "default",
                "badge": badge,
                # One stack per chat in Notification Centre, as Messages does.
                "thread-id": f"chat-{chat_id}",
            },
            # Read by the app: a tap opens this chat.
            "kind": "message",
            "chat_id": chat_id,
        }
        result = sender.send(device["token"], device.get("environment", "production"), payload)
        if result.gone:
            social.drop_device(device["token"])
