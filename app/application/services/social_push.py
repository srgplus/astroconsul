"""Pushes for the social layer: a like, or a new follower, on the owner's phone.

Activity was the only place a chart's owner heard that anyone was there, and
only once they opened the app. This sends the same news to their phone as it
happens, in the words the Activity row uses, with the app icon's badge set to
the unread count.

What earns a push, and what does not:

* a like, the first one that person gives the chart that day — liking a
  second state of the same sky shows in Activity but does not buzz again;
* a new follow — unfollowing and following again within the hour of quiet
  below is not news twice;
* never your own action on your own chart, and never when the owner switched
  that kind off in Settings.

It runs after the response has gone (FastAPI background task), so a like is
as fast with a push as without, and it never raises: a failure is logged.
"""

from __future__ import annotations

import hashlib
import logging
import threading
import time
from typing import Any

from app.application.services.push_service import get_sender
from app.infrastructure.repositories.factory import RepositoryBundle

logger = logging.getLogger(__name__)

# The Activity rows' own words (Strings.swift), so the banner and the row
# read the same. "yours" is the owner's primary chart; "other" names one of
# the other charts they keep.
TEXTS: dict[str, dict[str, str]] = {
    "en": {
        "like.yours": "{actor} liked your chart",
        "like.other": "{actor} liked {chart}",
        "follow.yours": "{actor} started following you",
        "follow.other": "{actor} started following {chart}",
        "someone": "A big3.me member",
    },
    "ru": {
        "like.yours": "{actor} лайкнул(а) вашу карту",
        "like.other": "{actor} лайкнул(а) карту «{chart}»",
        "follow.yours": "{actor} подписался(-ась) на вас",
        "follow.other": "{actor} подписался(-ась) на карту «{chart}»",
        "someone": "Участник big3.me",
    },
}

# The feels-like words in Russian, as the app prints them.
FEELS_RU = {
    "Calm": "Спокойно",
    "Subtle pressure": "Лёгкое давление",
    "Grinding": "Тяжесть",
    "Flowing": "Поток",
    "Dynamic": "Динамично",
    "Pressured": "Под давлением",
    "Expansive": "Расширение",
    "Charged": "Заряжено",
    "Intense": "Интенсивно",
    "Powerful": "Мощно",
    "Volatile": "Нестабильно",
    "Explosive": "Взрывоопасно",
}

# How long a follow from one person to one chart stays told. Kept in memory:
# a redeploy forgets it, which at worst lets one repeat through.
FOLLOW_QUIET_SECONDS = 60 * 60

_recent_follows: dict[tuple[str, str], float] = {}
_recent_lock = threading.Lock()


def notify_like(repos: RepositoryBundle, actor_id: str, profile: dict[str, Any], feels_like: str | None) -> None:
    _notify(repos, "like", actor_id, profile, feels_like)


def notify_follow(repos: RepositoryBundle, actor_id: str, profile: dict[str, Any]) -> None:
    key = (actor_id, str(profile.get("profile_id")))
    now = time.monotonic()
    with _recent_lock:
        told = _recent_follows.get(key)
        if told is not None and now - told < FOLLOW_QUIET_SECONDS:
            logger.info("Follow push to %s skipped: told within the hour", key[1])
            return
        _recent_follows[key] = now
        # Kept small: anything past its quiet hour can go.
        for stale in [k for k, at in _recent_follows.items() if now - at >= FOLLOW_QUIET_SECONDS]:
            del _recent_follows[stale]
    _notify(repos, "follow", actor_id, profile, None)


def compose(
    kind: str,
    lang: str,
    *,
    actor_name: str | None,
    chart_name: str | None,
    is_primary: bool,
    feels_like: str | None,
) -> str:
    """The banner's text for one event in one language."""
    texts = TEXTS.get(lang, TEXTS["en"])
    actor = (actor_name or "").strip() or texts["someone"]
    template = texts[f"{kind}.yours" if is_primary or not chart_name else f"{kind}.other"]
    body = template.format(actor=actor, chart=chart_name or "")
    if kind == "like" and feels_like:
        word = FEELS_RU.get(feels_like, feels_like) if lang == "ru" else feels_like
        body = f"{body} · {word}"
    return body


def _notify(
    repos: RepositoryBundle,
    kind: str,
    actor_id: str,
    profile: dict[str, Any],
    feels_like: str | None,
) -> None:
    try:
        _deliver(repos, kind, actor_id, profile, feels_like)
    except Exception:
        logger.exception("%s push for profile %s failed", kind, profile.get("profile_id"))


def _deliver(
    repos: RepositoryBundle,
    kind: str,
    actor_id: str,
    profile: dict[str, Any],
    feels_like: str | None,
) -> None:
    owner_id = str(profile.get("user_id") or "")
    profile_id = str(profile.get("profile_id") or "")
    social = repos.social
    if not owner_id or owner_id == actor_id or social is None:
        return

    sender = get_sender()
    if sender is None:
        logger.info("%s push for profile %s not sent: APNs is not configured", kind, profile_id)
        return

    if not social.social_settings(owner_id).get(f"push_{kind}s", True):
        return
    devices = social.devices_for(owner_id)
    if not devices:
        return

    actor = social.card_for(actor_id)
    is_primary = repos.profiles.get_primary_profile_id(owner_id) == profile_id
    badge = social.unread_activity_count(owner_id)

    for device in devices:
        body = compose(
            kind,
            device.get("lang", "en"),
            actor_name=actor.get("profile_name"),
            chart_name=profile.get("profile_name"),
            is_primary=is_primary,
            feels_like=feels_like,
        )
        payload = {
            "aps": {
                "alert": {"body": body},
                "sound": "default",
                "badge": badge,
                # One stack in Notification Centre for everything social.
                "thread-id": "activity",
            },
            # Read by the app: a tap opens Activity.
            "kind": kind,
            "profile_id": profile_id,
        }
        result = sender.send(
            device["token"],
            device.get("environment", "production"),
            payload,
            # A repeat of the same event replaces its banner rather than
            # stacking a second one.
            collapse_id=hashlib.sha1(f"{kind}:{actor_id}:{profile_id}".encode()).hexdigest(),
        )
        if result.gone:
            social.drop_device(device["token"])
