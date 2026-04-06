"""Subscription status and admin activation endpoints."""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.api.auth import get_current_user
from app.core.config import get_settings
from app.infrastructure.persistence.session import database_is_enabled, session_scope

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


# ── Schemas ──────────────────────────────────────────────────────────

class SubscriptionStatusResponse(BaseModel):
    plan: str  # "free", "pro_monthly", "pro_annual", "lifetime"
    is_pro: bool
    expires_at: str | None = None


class ActivateRequest(BaseModel):
    user_id: str
    plan: str = "pro_monthly"
    days: int = 30


# ── Helpers ──────────────────────────────────────────────────────────

def get_user_subscription(user_id: str) -> dict[str, Any]:
    """Get active subscription for user. Returns dict with plan info."""
    from sqlalchemy import select, desc

    from app.infrastructure.persistence.models import SubscriptionModel

    settings = get_settings()
    if not database_is_enabled(settings):
        return {"plan": "free", "is_pro": False, "expires_at": None}

    now = datetime.now(timezone.utc)

    with session_scope(settings) as session:
        result = session.execute(
            select(SubscriptionModel)
            .where(
                SubscriptionModel.user_id == user_id,
                SubscriptionModel.is_active == True,  # noqa: E712
            )
            .order_by(desc(SubscriptionModel.created_at))
            .limit(1)
        )
        sub = result.scalar_one_or_none()

        if sub is None:
            return {"plan": "free", "is_pro": False, "expires_at": None}

        # Lifetime never expires
        if sub.plan == "lifetime":
            return {"plan": "lifetime", "is_pro": True, "expires_at": None}

        # Check if expired
        if sub.expires_at and sub.expires_at < now:
            # Mark as inactive
            sub.is_active = False
            sub.updated_at = now
            return {"plan": "free", "is_pro": False, "expires_at": None}

        return {
            "plan": sub.plan,
            "is_pro": True,
            "expires_at": sub.expires_at.isoformat() if sub.expires_at else None,
        }


# ── Routes ───────────────────────────────────────────────────────────

@router.get("/status", response_model=SubscriptionStatusResponse)
def subscription_status(user: dict[str, Any] = Depends(get_current_user)):
    """Get current subscription status for logged-in user."""
    return get_user_subscription(user["user_id"])


@router.post("/activate", response_model=SubscriptionStatusResponse)
def admin_activate(
    body: ActivateRequest,
    user: dict[str, Any] = Depends(get_current_user),
):
    """Admin-only: manually activate Pro for a user."""
    from app.infrastructure.persistence.models import SubscriptionModel

    # Simple admin check — TODO: proper role-based access
    admin_emails = ["hi@srgplus.com", "cheretovich@gmail.com"]
    if user.get("email") not in admin_emails:
        raise HTTPException(status_code=403, detail="Admin access required")

    settings = get_settings()
    if not database_is_enabled(settings):
        raise HTTPException(status_code=500, detail="Database not enabled")

    now = datetime.now(timezone.utc)
    expires = now + timedelta(days=body.days) if body.plan != "lifetime" else None

    with session_scope(settings) as session:
        sub = SubscriptionModel(
            id=str(uuid.uuid4()),
            user_id=body.user_id,
            plan=body.plan,
            payment_provider="manual",
            amount=0,
            currency="USD",
            started_at=now,
            expires_at=expires,
            is_active=True,
            created_at=now,
            updated_at=now,
        )
        session.add(sub)

    logger.info("Admin activated %s for user %s (%d days)", body.plan, body.user_id, body.days)
    return get_user_subscription(body.user_id)
