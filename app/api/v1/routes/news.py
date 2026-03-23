from __future__ import annotations

import json
import logging
from datetime import date
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse, Response
from fastapi.templating import Jinja2Templates

from app.core.config import get_settings
from app.infrastructure.persistence.session import database_is_enabled, session_scope

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/news", tags=["news"])

_TEMPLATES_DIR = Path(__file__).resolve().parents[4] / "templates"
templates = Jinja2Templates(directory=str(_TEMPLATES_DIR))


def _parse_tags(tags_str: str | None) -> list[str]:
    if not tags_str:
        return []
    return [t.strip() for t in tags_str.split(",") if t.strip()]


def _parse_sections(sections_data) -> list[dict]:
    if sections_data is None:
        return []
    if isinstance(sections_data, str):
        try:
            return json.loads(sections_data)
        except (json.JSONDecodeError, TypeError):
            return []
    if isinstance(sections_data, list):
        return sections_data
    return []


def _get_published_posts(tag: str | None = None, limit: int = 20, offset: int = 0):
    """Fetch published posts from database."""
    from sqlalchemy import desc, select

    from app.infrastructure.persistence.models import NewsPostModel

    settings = get_settings()
    if not database_is_enabled(settings):
        return []

    with session_scope(settings) as session:
        query = select(NewsPostModel).where(NewsPostModel.status == "published")

        if tag:
            query = query.where(NewsPostModel.tags.contains(tag))

        query = query.order_by(desc(NewsPostModel.published_at)).limit(limit).offset(offset)

        result = session.execute(query)
        posts = result.scalars().all()

        # Convert to dicts while session is open
        post_dicts = []
        for p in posts:
            post_dicts.append({
                "slug": p.slug,
                "title": p.title,
                "subtitle": p.subtitle,
                "date": p.date,
                "author": p.author,
                "intro": p.intro,
                "tags": _parse_tags(p.tags),
                "hero_image_url": p.hero_image_url,
                "sections": _parse_sections(p.sections),
                "conclusion": p.conclusion,
                "celebrity_name": p.celebrity_name,
                "celebrity_event": p.celebrity_event,
                "meta_title": p.meta_title,
                "meta_description": p.meta_description,
                "og_image_url": p.og_image_url,
                "published_at": p.published_at,
            })
        return post_dicts


def _get_post_by_slug(slug: str):
    """Fetch a single published post by slug."""
    from sqlalchemy import select

    from app.infrastructure.persistence.models import NewsPostModel

    settings = get_settings()
    if not database_is_enabled(settings):
        return None

    with session_scope(settings) as session:
        result = session.execute(
            select(NewsPostModel).where(
                NewsPostModel.slug == slug,
                NewsPostModel.status == "published",
            )
        )
        p = result.scalar_one_or_none()
        if p is None:
            return None

        return {
            "slug": p.slug,
            "title": p.title,
            "subtitle": p.subtitle,
            "date": p.date,
            "author": p.author,
            "intro": p.intro,
            "tags": _parse_tags(p.tags),
            "hero_image_url": p.hero_image_url,
            "sections": _parse_sections(p.sections),
            "conclusion": p.conclusion,
            "celebrity_name": p.celebrity_name,
            "celebrity_event": p.celebrity_event,
            "meta_title": p.meta_title,
            "meta_description": p.meta_description,
            "og_image_url": p.og_image_url,
            "published_at": p.published_at,
        }


@router.get("/", response_class=HTMLResponse)
def news_feed(request: Request, tag: str | None = None, page: int = 1):
    """Render news feed with optional tag filter."""
    offset = (page - 1) * 20
    posts = _get_published_posts(tag=tag, limit=20, offset=offset)

    return templates.TemplateResponse("news/feed.html", {
        "request": request,
        "posts": posts,
        "tag": tag,
        "page": page,
    })


@router.get("/sitemap-news.xml", response_class=Response)
def news_sitemap():
    """Generate XML sitemap for news posts."""
    posts = _get_published_posts(limit=500)

    xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
    xml += '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    for post in posts:
        xml += "  <url>\n"
        xml += f"    <loc>https://big3.me/news/{post['slug']}</loc>\n"
        xml += f"    <lastmod>{post['date']}</lastmod>\n"
        xml += "    <changefreq>monthly</changefreq>\n"
        xml += "  </url>\n"
    xml += "</urlset>"

    return Response(content=xml, media_type="application/xml")


@router.get("/{slug}", response_class=HTMLResponse)
def news_post(request: Request, slug: str):
    """Render individual news post with full SEO meta tags."""
    post = _get_post_by_slug(slug)
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")

    return templates.TemplateResponse("news/post.html", {
        "request": request,
        "post": post,
    })
