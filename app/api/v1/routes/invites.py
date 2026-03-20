"""Profile invite endpoints — create, view, and accept profile transfer invites."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr

from app.api.auth import get_current_user
from app.api.dependencies import get_repositories
from app.application.services.email_service import send_invite_email
from app.core.config import get_settings
from app.infrastructure.repositories.factory import RepositoryBundle

router = APIRouter(tags=["invites"])

INVITE_EXPIRY_DAYS = 7


class CreateInviteRequest(BaseModel):
    email: EmailStr


@router.post("/profiles/{profile_id}/invite")
def create_invite(
    profile_id: str,
    payload: CreateInviteRequest,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """Create a profile transfer invite and send email notification."""
    profile = repos.profiles.load_profile(profile_id)
    owner_id = profile.get("user_id", "user_local_dev")
    if owner_id != user["user_id"]:
        raise HTTPException(status_code=403, detail="Not your profile")

    token = uuid.uuid4().hex
    expires_at = datetime.now(UTC) + timedelta(days=INVITE_EXPIRY_DAYS)

    invite = repos.profiles.create_invite(
        profile_id=profile_id,
        invited_email=payload.email,
        token=token,
        invited_by=user["user_id"],
        expires_at=expires_at,
    )

    settings = get_settings()
    host = settings.canonical_host or "big3.me"
    invite_url = f"https://{host}/invite/{token}"

    email_sent = send_invite_email(
        to_email=payload.email,
        profile_name=profile.get("profile_name", ""),
        inviter_email=user.get("email", ""),
        invite_url=invite_url,
    )

    if not email_sent:
        raise HTTPException(
            status_code=502,
            detail="Failed to send invite email. Please try again later.",
        )

    return {"status": "ok", "token": token, "invite_url": invite_url}


@router.get("/invites/{token}")
def get_invite(
    token: str,
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """Public endpoint: get invite info by token."""
    invite = repos.profiles.get_invite_by_token(token)
    if invite is None:
        raise HTTPException(status_code=404, detail="Invite not found")
    return {
        "token": invite["token"],
        "profile_name": invite["profile_name"],
        "invited_email": invite["invited_email"],
        "invited_by_email": invite["invited_by_email"],
        "status": invite["status"],
        "expires_at": invite["expires_at"],
    }


@router.post("/invites/{token}/accept")
def accept_invite(
    token: str,
    user: dict[str, Any] = Depends(get_current_user),
    repos: RepositoryBundle = Depends(get_repositories),
) -> dict[str, Any]:
    """Accept a profile transfer invite (authenticated)."""
    try:
        result = repos.profiles.accept_invite(token, user["user_id"])
        return {"status": "ok", **result}
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
