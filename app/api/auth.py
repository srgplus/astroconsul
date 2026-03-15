"""Supabase JWT authentication dependency for FastAPI."""

from __future__ import annotations

import logging
from typing import Any

import jwt
from fastapi import HTTPException, Request

from app.core.config import get_settings

logger = logging.getLogger(__name__)


def get_current_user(request: Request) -> dict[str, Any]:
    """FastAPI dependency: extract and verify the authenticated user.

    When ``auth_enabled`` is *False* (default in dev), returns the local
    default user from settings — zero-friction development.

    When ``auth_enabled`` is *True*, expects a Supabase JWT in the
    ``Authorization: Bearer <token>`` header, verifies it with the
    project's JWT secret, and returns ``{user_id, email}``.
    """
    settings = get_settings()

    if not settings.auth_enabled:
        return {
            "user_id": settings.default_user_id,
            "email": settings.default_user_email,
        }

    # --- Auth enabled: verify Supabase JWT ---
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")

    token = auth_header.removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(status_code=401, detail="Empty token")

    if not settings.supabase_jwt_secret:
        logger.error("AUTH_ENABLED is true but SUPABASE_JWT_SECRET is not set")
        raise HTTPException(status_code=500, detail="Server auth misconfigured")

    try:
        payload = jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=["HS256"],
            audience="authenticated",
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError as exc:
        logger.warning("JWT verification failed: %s", exc)
        raise HTTPException(status_code=401, detail="Invalid token")

    user_id: str = payload.get("sub", "")
    email: str = payload.get("email", "")

    if not user_id:
        raise HTTPException(status_code=401, detail="Token missing subject")

    return {"user_id": user_id, "email": email}
