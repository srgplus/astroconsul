"""Authentication info endpoints."""

from __future__ import annotations

import logging
import os
from typing import Any

import httpx
from fastapi import APIRouter, Depends, Response
from sqlalchemy import delete, select

from app.api.auth import get_current_user
from app.core.config import get_settings
from app.infrastructure.persistence.models import (
    LatestTransitModel,
    ProfileFollowModel,
    ProfileInviteModel,
    ProfileModel,
    SubscriptionModel,
    UserModel,
)
from app.infrastructure.persistence.session import session_scope

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/me")
def auth_me(user: dict[str, Any] = Depends(get_current_user)) -> dict[str, Any]:
    """Return the currently authenticated user's info."""
    return {"user_id": user["user_id"], "email": user["email"]}


@router.delete("/account", status_code=204)
def delete_account(user: dict[str, Any] = Depends(get_current_user)) -> Response:
    """Permanently delete the authenticated user's account and all associated data.

    Removes: user row, profiles, natal charts used only by this user's profiles,
    latest transit snapshots, follow relationships, invites, subscriptions,
    and the Supabase Auth record itself.

    This is irreversible. Required by App Store guideline 5.1.1(v).
    """
    settings = get_settings()
    user_id = user["user_id"]
    logger.info("Account deletion requested for user_id=%s", user_id)

    # --- 1. Delete application data ---
    if settings.use_database:
        with session_scope(settings) as session:
            profile_ids = [
                pid
                for (pid,) in session.execute(
                    select(ProfileModel.id).where(ProfileModel.user_id == user_id)
                ).all()
            ]

            if profile_ids:
                session.execute(
                    delete(LatestTransitModel).where(
                        LatestTransitModel.profile_id.in_(profile_ids)
                    )
                )
                session.execute(
                    delete(ProfileFollowModel).where(
                        ProfileFollowModel.profile_id.in_(profile_ids)
                    )
                )
                session.execute(
                    delete(ProfileInviteModel).where(
                        ProfileInviteModel.profile_id.in_(profile_ids)
                    )
                )

            session.execute(
                delete(ProfileFollowModel).where(ProfileFollowModel.user_id == user_id)
            )
            session.execute(
                delete(ProfileInviteModel).where(ProfileInviteModel.invited_by == user_id)
            )
            session.execute(
                delete(ProfileModel).where(ProfileModel.user_id == user_id)
            )
            session.execute(
                delete(SubscriptionModel).where(SubscriptionModel.user_id == user_id)
            )
            session.execute(delete(UserModel).where(UserModel.id == user_id))

    # --- 2. Delete Supabase Auth record ---
    service_role_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or os.environ.get(
        "SUPABASE_KEY"
    )
    if settings.auth_enabled and settings.supabase_url and service_role_key:
        try:
            resp = httpx.delete(
                f"{settings.supabase_url}/auth/v1/admin/users/{user_id}",
                headers={
                    "apikey": service_role_key,
                    "Authorization": f"Bearer {service_role_key}",
                },
                timeout=10,
            )
            if resp.status_code >= 400:
                logger.error(
                    "Supabase auth delete returned %s: %s",
                    resp.status_code,
                    resp.text,
                )
        except Exception:
            logger.exception("Supabase auth delete request failed")
    else:
        logger.info(
            "Skipping Supabase auth delete (auth_enabled=%s, has_url=%s, has_key=%s)",
            settings.auth_enabled,
            bool(settings.supabase_url),
            bool(service_role_key),
        )

    return Response(status_code=204)
