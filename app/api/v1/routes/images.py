"""Image upload endpoint for blog post visuals.

Claude Code renders HTML → PNG via Playwright, then sends PNG here.
This endpoint uploads to Supabase Storage and optionally updates the post.

POST /api/v1/images/upload
  - file: PNG binary (multipart)
  - slug: post slug
  - filename: e.g. "cover.png" or "section_0_name.png"

POST /api/v1/images/upload-base64
  - JSON body: {slug, filename, data (base64 PNG)}

Both return: {url: "https://...supabase.co/storage/v1/object/public/news-images/..."}
"""

from __future__ import annotations

import base64
import logging
import os
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException

from app.core.config import get_settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/images", tags=["images"])

BUCKET = "news-images"


def _get_supabase_creds() -> tuple[str, str]:
    settings = get_settings()
    url = settings.supabase_url or os.environ.get("SUPABASE_URL", "")
    key = (
        os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        or os.environ.get("SUPABASE_KEY")
        or settings.supabase_anon_key
        or ""
    )
    if not url or not key:
        raise HTTPException(status_code=500, detail="Supabase credentials not configured")
    return url, key


def _ensure_bucket(url: str, key: str):
    """Create storage bucket if it doesn't exist."""
    try:
        resp = httpx.post(
            f"{url}/storage/v1/bucket",
            json={"id": BUCKET, "name": BUCKET, "public": True},
            headers={"apikey": key, "Authorization": f"Bearer {key}"},
            timeout=10,
        )
        if resp.status_code in (200, 201):
            logger.info("Created storage bucket: %s", BUCKET)
        # 409 = already exists, that's fine
    except Exception:
        logger.exception("Failed to create bucket")


def _upload_to_storage(data: bytes, slug: str, filename: str) -> str:
    """Upload PNG to Supabase Storage, return public URL."""
    url, key = _get_supabase_creds()
    storage_path = f"{slug}/{filename}"

    resp = httpx.post(
        f"{url}/storage/v1/object/{BUCKET}/{storage_path}",
        content=data,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "image/png",
            "x-upsert": "true",
        },
        timeout=30,
    )

    if resp.status_code == 400 and "Bucket not found" in resp.text:
        _ensure_bucket(url, key)
        resp = httpx.post(
            f"{url}/storage/v1/object/{BUCKET}/{storage_path}",
            content=data,
            headers={
                "apikey": key,
                "Authorization": f"Bearer {key}",
                "Content-Type": "image/png",
                "x-upsert": "true",
            },
            timeout=30,
        )

    if resp.status_code not in (200, 201):
        logger.error("Storage upload failed: %s %s", resp.status_code, resp.text)
        raise HTTPException(status_code=502, detail=f"Storage upload failed: {resp.text}")

    return f"{url}/storage/v1/object/public/{BUCKET}/{storage_path}"


def _update_post_image(slug: str, filename: str, image_url: str):
    """Update news post with image URL."""
    from app.infrastructure.persistence.models import NewsPostModel
    from app.infrastructure.persistence.session import database_is_enabled, session_scope

    settings = get_settings()
    if not database_is_enabled(settings):
        return

    with session_scope(settings) as session:
        from sqlalchemy import select
        post = session.execute(
            select(NewsPostModel).where(NewsPostModel.slug == slug)
        ).scalar_one_or_none()

        if not post:
            logger.warning("Post not found for image update: %s", slug)
            return

        if filename == "cover.png":
            post.hero_image_url = image_url
            post.og_image_url = image_url
        elif filename.startswith("section_"):
            # Extract index: "section_0_name.png" → 0
            parts = filename.replace(".png", "").split("_")
            if len(parts) >= 2 and parts[1].isdigit():
                idx = int(parts[1])
                sections = list(post.sections or [])
                if idx < len(sections):
                    sections[idx]["image_url"] = image_url
                    sections[idx]["image_alt"] = sections[idx].get("heading", "")
                    post.sections = sections

        logger.info("Updated post %s with image %s", slug, filename)



@router.post("/upload-base64")
async def upload_image_base64(body: dict[str, Any]) -> dict[str, str]:
    """Upload a base64-encoded PNG for a blog post."""
    slug = body.get("slug")
    filename = body.get("filename", "image.png")
    b64_data = body.get("data")

    if not slug or not b64_data:
        raise HTTPException(status_code=400, detail="slug and data (base64) required")

    try:
        data = base64.b64decode(b64_data)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid base64 data")

    if len(data) > 5 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="File too large (max 5MB)")

    url = _upload_to_storage(data, slug, filename)
    _update_post_image(slug, filename, url)

    return {"url": url, "slug": slug, "filename": filename}
