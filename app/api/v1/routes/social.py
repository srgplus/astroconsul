"""The social routes: like a profile, see who is there, Activity, block, report.

What makes big3.me a social network rather than a chart viewer with a follow
button. Following already existed and went one way; these are the parts that
come back — a like the owner hears about, the list of who follows and likes a
chart, and an Activity feed of both. Block and report are here too, because
App Review requires both of any app with social features (guideline 1.2), and
because they are what keeps the rest of it pleasant.

Who may do what:

* anyone signed in may like, block or report a profile that is not their own;
* only a profile's owner may see who follows or likes it;
* a block works in both directions and says nothing to the blocked account:
  to them, the other side's profiles simply are not there.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.api.auth import get_current_user
from app.api.dependencies import get_repositories
from app.application.services.email_service import send_report_email
from app.domain.moderation import REPORT_DETAILS_MAX, REPORT_REASONS
from app.infrastructure.repositories.factory import RepositoryBundle
from app.infrastructure.repositories.protocols import SocialRepository

logger = logging.getLogger(__name__)

router = APIRouter(tags=["social"])


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
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    social = _social(repos)
    profile = _load_profile(repos, profile_id)
    if _owner(profile) == user["user_id"]:
        raise HTTPException(status_code=400, detail="You can't like your own profile")
    guard_block(social, user["user_id"], profile)
    social.like_profile(user["user_id"], profile_id)
    return {"status": "ok", **social.social_counts([profile_id], user["user_id"])[profile_id]}


@router.delete("/profiles/{profile_id}/like")
def unlike_profile(
    profile_id: str,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    social = _social(repos)
    social.unlike_profile(user["user_id"], profile_id)
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


@router.post("/reports")
def report_profile(
    payload: ReportRequest,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """Files a report for a person to review, and blocks the owner too when
    asked. The report is stored first; the mail to the moderation inbox is a
    nudge on top and never fails the request."""
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
    send_report_email({**report, "details": details}, profile, user.get("email", ""))

    if payload.block:
        social.block_user(user["user_id"], owner)

    return {"status": "ok", "report_id": report.get("report_id"), "blocked": payload.block}
