"""Supabase JWT authentication dependency for FastAPI."""

from __future__ import annotations

import json
import logging
import urllib.request
from typing import Any

import jwt
from jwt import PyJWK
from fastapi import HTTPException, Request

from app.core.config import get_settings

logger = logging.getLogger(__name__)

# Cached ES256 public key
_es256_key: Any | None = None


def _get_es256_key() -> Any:
    """Fetch and cache the ES256 public key from Supabase JWKS endpoint."""
    global _es256_key
    if _es256_key is not None:
        return _es256_key

    settings = get_settings()
    if not settings.supabase_url:
        raise HTTPException(status_code=500, detail="SUPABASE_URL not configured")

    jwks_url = f"{settings.supabase_url}/auth/v1/.well-known/jwks.json"
    req = urllib.request.Request(jwks_url)
    if settings.supabase_anon_key:
        req.add_header("apikey", settings.supabase_anon_key)

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            jwks_data = json.loads(resp.read())
    except Exception as exc:
        logger.error("Failed to fetch JWKS: %s", exc)
        raise HTTPException(status_code=500, detail="Cannot fetch auth keys")

    keys = jwks_data.get("keys", [])
    if not keys:
        raise HTTPException(status_code=500, detail="No keys in JWKS response")

    # Use the first ES256 key
    for key_data in keys:
        if key_data.get("alg") == "ES256":
            jwk = PyJWK(key_data)
            _es256_key = jwk.key
            return _es256_key

    raise HTTPException(status_code=500, detail="No ES256 key found in JWKS")


def get_current_user(request: Request) -> dict[str, Any]:
    """FastAPI dependency: extract and verify the authenticated user.

    When ``auth_enabled`` is *False* (default in dev), returns the local
    default user from settings — zero-friction development.

    When ``auth_enabled`` is *True*, expects a Supabase JWT in the
    ``Authorization: Bearer <token>`` header, verifies it with ES256
    (JWKS) or HS256 (legacy secret), and returns ``{user_id, email}``.
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

    # Peek at the token header to determine algorithm
    try:
        unverified_header = jwt.get_unverified_header(token)
    except jwt.DecodeError:
        raise HTTPException(status_code=401, detail="Malformed token")

    alg = unverified_header.get("alg", "")

    try:
        if alg == "ES256":
            # New Supabase projects use ES256 — verify with JWKS public key
            key = _get_es256_key()
            payload = jwt.decode(
                token,
                key,
                algorithms=["ES256"],
                audience="authenticated",
            )
        elif alg == "HS256":
            # Legacy Supabase projects use HS256 — verify with shared secret
            if not settings.supabase_jwt_secret:
                logger.error("HS256 token but SUPABASE_JWT_SECRET is not set")
                raise HTTPException(status_code=500, detail="Server auth misconfigured")
            payload = jwt.decode(
                token,
                settings.supabase_jwt_secret,
                algorithms=["HS256"],
                audience="authenticated",
            )
        else:
            raise HTTPException(status_code=401, detail=f"Unsupported JWT algorithm: {alg}")
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
