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


_templates_cache: Jinja2Templates | None = None


def _get_templates() -> Jinja2Templates:
    global _templates_cache
    if _templates_cache is None:
        templates_dir = Path(__file__).resolve().parents[4] / "templates"
        if not templates_dir.exists():
            logger.error("Templates directory not found: %s", templates_dir)
        _templates_cache = Jinja2Templates(directory=str(templates_dir))
    return _templates_cache


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
    try:
        offset = (page - 1) * 20
        posts = _get_published_posts(tag=tag, limit=20, offset=offset)

        return _get_templates().TemplateResponse(
            request=request,
            name="news/feed.html",
            context={"posts": posts, "tag": tag, "page": page},
        )
    except Exception:
        logger.exception("Error rendering news feed")
        raise


@router.get("/feed.xml", response_class=Response)
def news_rss_feed():
    """Generate RSS 2.0 feed for news posts."""
    posts = _get_published_posts(limit=20)

    xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
    xml += '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">\n'
    xml += "<channel>\n"
    xml += "  <title>big3.me Astrology News</title>\n"
    xml += "  <link>https://big3.me/news/</link>\n"
    xml += "  <description>Daily astrology transit analysis and cosmic weather updates.</description>\n"
    xml += "  <language>en</language>\n"
    xml += '  <atom:link href="https://big3.me/news/feed.xml" rel="self" type="application/rss+xml"/>\n'

    for post in posts:
        xml += "  <item>\n"
        xml += f"    <title>{_xml_escape(post['title'])}</title>\n"
        xml += f"    <link>https://big3.me/news/{post['slug']}</link>\n"
        xml += f"    <guid isPermaLink=\"true\">https://big3.me/news/{post['slug']}</guid>\n"
        if post.get("subtitle"):
            xml += f"    <description>{_xml_escape(post['subtitle'])}</description>\n"
        xml += f"    <pubDate>{_rfc822_date(post['date'])}</pubDate>\n"
        if post.get("tags"):
            for tag in post["tags"]:
                xml += f"    <category>{_xml_escape(tag)}</category>\n"
        xml += "  </item>\n"

    xml += "</channel>\n</rss>"
    return Response(content=xml, media_type="application/rss+xml; charset=utf-8")


def _xml_escape(text: str) -> str:
    """Escape XML special characters."""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def _rfc822_date(date_str: str) -> str:
    """Convert YYYY-MM-DD to RFC 822 date format for RSS."""
    from datetime import datetime
    try:
        dt = datetime.strptime(str(date_str), "%Y-%m-%d")
        return dt.strftime("%a, %d %b %Y 00:00:00 +0000")
    except (ValueError, TypeError):
        return str(date_str)


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
    try:
        post = _get_post_by_slug(slug)
        if post is None:
            raise HTTPException(status_code=404, detail="Post not found")

        return _get_templates().TemplateResponse(
            request=request,
            name="news/post.html",
            context={"post": post},
        )
    except HTTPException:
        raise
    except Exception:
        logger.exception("Error rendering news post: %s", slug)
        raise
