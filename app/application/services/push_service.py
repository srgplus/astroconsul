"""Apple Push Notification service: how the server reaches a phone.

Token-based authentication: one .p8 key signs a short JWT (the provider
token) that rides on every request, so there is no certificate to renew each
year. APNs speaks HTTP/2 only, which is what `httpx` with `h2` gives.

Nothing here raises into a request. A push is a nudge on top of Activity, and
a like must never fail because Apple was slow or the key was wrong: every
outcome comes back as a `PushResult` and every failure is logged.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from dataclasses import dataclass
from functools import lru_cache
from typing import Any, Protocol

import httpx
import jwt

from app.core.config import get_settings

logger = logging.getLogger(__name__)

HOSTS = {
    "production": "https://api.push.apple.com",
    "sandbox": "https://api.sandbox.push.apple.com",
}

# APNs refuses a provider token older than an hour and throttles one renewed
# more often than every twenty minutes, so one is minted and kept for fifty.
TOKEN_LIFETIME_SECONDS = 50 * 60

# What APNs answers for a token that is no longer this app's to reach: the
# app was deleted, or reinstalled and given a new one. Such a token is
# forgotten rather than tried again on every like.
GONE_REASONS = frozenset({"BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"})


@dataclass(frozen=True)
class PushResult:
    ok: bool
    status: int = 0
    reason: str | None = None
    # True when the token should be dropped.
    gone: bool = False


class PushSender(Protocol):
    def send(
        self,
        token: str,
        environment: str,
        payload: dict[str, Any],
        *,
        collapse_id: str | None = None,
    ) -> PushResult: ...


class ApnsClient:
    def __init__(
        self,
        *,
        key_id: str,
        private_key: str,
        team_id: str,
        topic: str,
        transport: httpx.BaseTransport | None = None,
    ):
        self.key_id = key_id
        self.private_key = private_key
        self.team_id = team_id
        self.topic = topic
        # One client for the life of the process: APNs wants a connection
        # kept open and reused, not a handshake per push.
        self._http = httpx.Client(http2=True, timeout=10.0, transport=transport)
        self._lock = threading.Lock()
        self._token: str | None = None
        self._minted_at = 0.0

    def _provider_token(self) -> str:
        with self._lock:
            now = time.time()
            if self._token is None or now - self._minted_at > TOKEN_LIFETIME_SECONDS:
                self._token = jwt.encode(
                    {"iss": self.team_id, "iat": int(now)},
                    self.private_key,
                    algorithm="ES256",
                    headers={"kid": self.key_id},
                )
                self._minted_at = now
            return self._token

    def send(
        self,
        token: str,
        environment: str,
        payload: dict[str, Any],
        *,
        collapse_id: str | None = None,
    ) -> PushResult:
        try:
            authorization = self._provider_token()
        except Exception:
            # A key that does not parse: every push would fail the same way.
            logger.exception("APNs provider token could not be signed; check ASTRO_CONSUL_APNS_PRIVATE_KEY")
            return PushResult(ok=False, reason="InvalidKey")

        headers = {
            "authorization": f"bearer {authorization}",
            "apns-topic": self.topic,
            "apns-push-type": "alert",
            "apns-priority": "10",
        }
        if collapse_id:
            # APNs caps the collapse id at 64 bytes.
            headers["apns-collapse-id"] = collapse_id[:64]

        url = f"{HOSTS.get(environment, HOSTS['production'])}/3/device/{token}"
        try:
            response = self._http.post(url, headers=headers, content=json.dumps(payload).encode("utf-8"))
        except httpx.HTTPError as exc:
            logger.error("APNs request failed for token %s…: %s", token[:8], exc)
            return PushResult(ok=False, reason=type(exc).__name__)

        if response.status_code == 200:
            return PushResult(ok=True, status=200)

        reason = _reason(response)
        gone = response.status_code == 410 or reason in GONE_REASONS
        if gone:
            logger.info("APNs dropped token %s… (%s %s)", token[:8], response.status_code, reason)
        else:
            # 403 is the key: wrong Key ID or team, or a key without APNs.
            logger.error("APNs refused a push to %s…: %s %s", token[:8], response.status_code, reason)
        return PushResult(ok=False, status=response.status_code, reason=reason, gone=gone)


def _reason(response: httpx.Response) -> str | None:
    try:
        body = response.json()
    except ValueError:
        return None
    reason = body.get("reason") if isinstance(body, dict) else None
    return str(reason) if reason else None


@lru_cache(maxsize=1)
def get_sender() -> PushSender | None:
    """The APNs client, or None while no key is configured."""
    settings = get_settings()
    if not settings.apns_enabled:
        return None
    assert settings.apns_key_id is not None and settings.apns_private_key is not None
    return ApnsClient(
        key_id=settings.apns_key_id,
        private_key=settings.apns_private_key,
        team_id=settings.apns_team_id,
        topic=settings.apns_topic,
    )
