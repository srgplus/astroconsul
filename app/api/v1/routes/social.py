"""The social routes: like a profile, see who is there, Activity, block, report.

What makes big3.me a social network rather than a chart viewer with a follow
button. Following already existed and went one way; these are the parts that
come back — a like the owner hears about, the list of who follows and likes a
chart, and an Activity feed of both. Block and report are here too, because
App Review requires both of any app with social features (guideline 1.2), and
because they are what keeps the rest of it pleasant.

Who may do what:

* anyone signed in may like any profile but their own: the number under
  a chart's heart is how many likes other people gave it, and an owner who
  could add to it would only be counting themselves. That holds for every
  chart the account owns, not only its primary, and ends when a chart is
  handed to someone else;
* anyone signed in may block or report a profile that is not their own;
* only a profile's owner may see who follows or likes it — anyone else sees
  how many, unless the owner hid the numbers in Settings;
* a block works in both directions and says nothing to the blocked account:
  to them, the other side's profiles simply are not there.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter, BackgroundTasks, Body, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.auth import get_current_user
from app.api.dependencies import get_repositories
from app.application.services.email_service import send_report_email
from app.application.services.social_push import notify_like
from app.domain.astrology.tii import FEELS_LIKE_LABELS
from app.domain.moderation import REPORT_DETAILS_MAX, REPORT_REASONS
from app.infrastructure.repositories.chat_repositories import ChatNotFound
from app.infrastructure.repositories.factory import RepositoryBundle
from app.infrastructure.repositories.protocols import SocialRepository

logger = logging.getLogger(__name__)

router = APIRouter(tags=["social"])


class LikeRequest(BaseModel):
    # What the liker was looking at when they tapped the heart: the day's
    # feels-like word and index, kept with the like so its owner reads
    # "liked your Expansive day" rather than a bare heart.
    feels_like: str | None = Field(default=None, max_length=64)
    tii: float | None = Field(default=None, ge=0, le=100)


class BlockRequest(BaseModel):
    # The profile the person was looking at: its owner is who gets blocked.
    # Account ids never leave the API, so a profile is the only handle the app
    # has on the person behind it.
    profile_id: str


class ReportRequest(BaseModel):
    profile_id: str
    reason: str
    details: str | None = Field(default=None, max_length=REPORT_DETAILS_MAX)
    # Reporting and blocking are one step in the app: the sheet offers to do
    # both, so the reporter does not have to find the second button after.
    block: bool = False
    # Reported from a conversation: the chat, whose latest messages go to the
    # moderation inbox with the report. Only a chat the reporter is in, with
    # the owner of the reported profile.
    chat_id: int | None = Field(default=None, ge=1)


class SocialSettingsRequest(BaseModel):
    # Each is optional: a client sends the one switch that was flipped.
    # Whether other people see how many follow this account's charts, how
    # many it follows and how many likes its charts have had. The owner sees
    # them either way.
    show_counts: bool | None = None
    # Whether a like, or a new follower, on this account's charts is pushed
    # to its phones, and a message somebody writes to it.
    push_likes: bool | None = None
    push_follows: bool | None = None
    push_messages: bool | None = None


class DeviceRequest(BaseModel):
    # The APNs device token, hex, as the phone handed it to the app.
    token: str = Field(min_length=16, max_length=200, pattern=r"^[0-9a-fA-F]+$")
    # Which APNs host the token belongs to: a debug build's tokens work only
    # against the sandbox, TestFlight and the App Store against production.
    environment: str = Field(default="production", pattern=r"^(production|sandbox)$")
    # The language the app is read in, for the text of the push.
    lang: str = Field(default="en", pattern=r"^(en|ru)$")


def _social(repos: RepositoryBundle) -> SocialRepository:
    if repos.social is None:
        raise HTTPException(status_code=503, detail="Social features are not available")
    return repos.social


def _load_profile(repos: RepositoryBundle, profile_id: str) -> dict[str, Any]:
    try:
        return repos.profiles.load_profile(profile_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


def _owner(profile: dict[str, Any]) -> str:
    return str(profile.get("user_id", "user_local_dev"))


def guard_block(social: SocialRepository, viewer_id: str, profile: dict[str, Any]) -> None:
    """Stops an account acting on a profile across a block.

    The blocker is told why and where to undo it. The blocked account gets the
    same 404 a profile that does not exist would — a block that announces
    itself invites the blocked person to go around it."""
    blocker = social.blocker_of(viewer_id, _owner(profile))
    if blocker is None:
        return
    if blocker == viewer_id:
        raise HTTPException(status_code=403, detail="You blocked this person. Unblock them in Settings first.")
    raise HTTPException(status_code=404, detail=f"Natal profile not found: {profile.get('profile_id')}")


def _require_owner(profile: dict[str, Any], user_id: str) -> None:
    if _owner(profile) != user_id:
        raise HTTPException(status_code=403, detail="Only the profile's owner can see this")


# MARK: - Likes


@router.post("/profiles/{profile_id}/like")
def like_profile(
    profile_id: str,
    background: BackgroundTasks,
    payload: LikeRequest | None = Body(default=None),
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """Likes the state of the chart's sky the liker has on screen: the
    feels-like word, today in the profile's own zone. When the word changes,
    or the day does, that is a new state and the heart is empty again.

    Not on a chart the caller owns, whichever of theirs it is: the app shows
    the owner the count without a heart to tap, and this stops a build that
    still offers one."""
    social = _social(repos)
    profile = _load_profile(repos, profile_id)
    if _owner(profile) == user["user_id"]:
        raise HTTPException(status_code=403, detail="You cannot like your own chart")
    guard_block(social, user["user_id"], profile)
    # A word the matrix never produces is dropped rather than stored: it is
    # shown to the chart's owner, so it has to be one of ours.
    feels_like = payload.feels_like if payload and payload.feels_like in FEELS_LIKE_LABELS else None
    first_today = social.like_profile(
        user["user_id"],
        profile_id,
        feels_like=feels_like,
        tii=payload.tii if payload else None,
    )
    if first_today:
        # After the response: the heart fills as fast as it did without it.
        background.add_task(notify_like, repos, user["user_id"], profile, feels_like)
    return {"status": "ok", **social.social_counts([profile_id], user["user_id"])[profile_id]}


@router.delete("/profiles/{profile_id}/like")
def unlike_profile(
    profile_id: str,
    feels_like: str | None = Query(default=None, max_length=64),
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """Takes back the like on one of today's states — the word in
    `feels_like` — or, without one, every like given to the chart today."""
    social = _social(repos)
    social.unlike_profile(user["user_id"], profile_id, feels_like=feels_like)
    return {"status": "ok", **social.social_counts([profile_id], user["user_id"])[profile_id]}


# MARK: - Who is there


@router.get("/profiles/{profile_id}/likes")
def list_likers(
    profile_id: str,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    social = _social(repos)
    _require_owner(_load_profile(repos, profile_id), user["user_id"])
    return {"people": social.list_likers(profile_id, user["user_id"])}


@router.get("/profiles/{profile_id}/followers")
def list_followers(
    profile_id: str,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    social = _social(repos)
    _require_owner(_load_profile(repos, profile_id), user["user_id"])
    return {"people": social.list_followers(profile_id, user["user_id"])}


# MARK: - Activity


@router.get("/activity")
def list_activity(
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """Likes and follows on the caller's profiles, newest first. Reading it
    does not mark it read: the app says when the screen was actually seen."""
    return _social(repos).list_activity(user["user_id"])


@router.get("/activity/unread")
def unread_activity(
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, int]:
    """Just the badge number, for the home screen to ask on every return."""
    return {"unread_count": _social(repos).unread_activity_count(user["user_id"])}


@router.post("/activity/seen")
def mark_activity_seen(
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, str]:
    _social(repos).mark_activity_seen(user["user_id"])
    return {"status": "ok"}


# MARK: - Settings


@router.get("/social/settings")
def get_social_settings(
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, bool]:
    return _social(repos).social_settings(user["user_id"])


@router.put("/social/settings")
def update_social_settings(
    payload: SocialSettingsRequest,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, bool]:
    """Shows or hides the account's followers and following counts from
    everyone else, on every chart it owns, and turns the pushes for likes,
    new followers and messages on or off. Answers with all of them as they
    stand."""
    return _social(repos).update_social_settings(
        user["user_id"],
        show_counts=payload.show_counts,
        push_likes=payload.push_likes,
        push_follows=payload.push_follows,
        push_messages=payload.push_messages,
    )


# MARK: - Devices


@router.post("/devices")
def register_device(
    payload: DeviceRequest,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, str]:
    """The phone the app runs on, for pushes. Sent on every launch, so a
    changed language or a token the phone rotated is picked up."""
    _social(repos).register_device(
        user["user_id"],
        payload.token.lower(),
        environment=payload.environment,
        lang=payload.lang,
    )
    return {"status": "ok"}


@router.delete("/devices/{token}")
def unregister_device(
    token: str,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, str]:
    """Sign-out: this phone stops hearing about the account."""
    _social(repos).unregister_device(user["user_id"], token.lower())
    return {"status": "ok"}


# MARK: - Blocks


@router.post("/blocks")
def block_user(
    payload: BlockRequest,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, str]:
    social = _social(repos)
    profile = _load_profile(repos, payload.profile_id)
    owner = _owner(profile)
    if owner == user["user_id"]:
        raise HTTPException(status_code=400, detail="You can't block yourself")
    social.block_user(user["user_id"], owner)
    logger.info("User %s blocked the owner of profile %s", user["user_id"], payload.profile_id)
    return {"status": "ok"}


@router.get("/blocks")
def list_blocks(
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    return {"blocks": _social(repos).list_blocks(user["user_id"])}


@router.delete("/blocks/{block_id}")
def unblock(
    block_id: int,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, str]:
    if not _social(repos).unblock(user["user_id"], block_id):
        raise HTTPException(status_code=404, detail="Block not found")
    return {"status": "ok"}


# MARK: - Reports


def _reported_conversation(
    repos: RepositoryBundle, reporter_id: str, chat_id: int, reported_id: str
) -> dict[str, Any] | None:
    """The latest messages of the chat a report came from, each marked as the
    reporter's or the reported person's. None, and the report goes without
    them, when the chat is not the reporter's or not with that person: a
    report is never refused over the conversation it names."""
    if repos.chats is None:
        logger.warning("Report names chat %s, but chats are not available here", chat_id)
        return None
    try:
        transcript = repos.chats.transcript(reporter_id, chat_id)
    except ChatNotFound:
        logger.warning("Report by %s names chat %s, which is not theirs: filed without it", reporter_id, chat_id)
        return None
    if transcript["peer_id"] != reported_id:
        logger.warning(
            "Report by %s names chat %s, which is not with the reported account: filed without it",
            reporter_id,
            chat_id,
        )
        return None
    for message in transcript["messages"]:
        message["role"] = "reporter" if message["sender_id"] == reporter_id else "reported"
    return transcript


@router.post("/reports")
def report_profile(
    payload: ReportRequest,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """Files a report for a person to review, and blocks the owner too when
    asked. The report is stored first; the mail to the moderation inbox is a
    nudge on top and never fails the request. Reported from a chat, the mail
    carries the chat's latest messages, read before any block."""
    social = _social(repos)
    reason = payload.reason.strip().lower()
    if reason not in REPORT_REASONS:
        raise HTTPException(status_code=422, detail=f"reason must be one of: {', '.join(REPORT_REASONS)}")

    profile = _load_profile(repos, payload.profile_id)
    owner = _owner(profile)
    if owner == user["user_id"]:
        raise HTTPException(status_code=400, detail="You can't report your own profile")

    details = (payload.details or "").strip() or None
    report = social.create_report(user["user_id"], profile, reason=reason, details=details)
    logger.warning(
        "Profile %s reported by %s for %s (report %s)",
        payload.profile_id,
        user["user_id"],
        reason,
        report.get("report_id"),
    )
    conversation = (
        _reported_conversation(repos, user["user_id"], payload.chat_id, owner) if payload.chat_id is not None else None
    )
    send_report_email(
        {**report, "details": details},
        profile,
        user.get("email", ""),
        conversation=conversation,
    )

    if payload.block:
        social.block_user(user["user_id"], owner)

    return {
        "status": "ok",
        "report_id": report.get("report_id"),
        "blocked": payload.block,
        "conversation_attached": conversation is not None,
    }
