from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles

from app.api.legacy import router as legacy_router
from app.api.v1.router import router as api_v1_router
from app.api.v1.routes.news import router as news_router
from app.core.config import get_settings
from app.core.logging import configure_logging

try:  # pragma: no cover - optional integration
    import sentry_sdk
except ImportError:  # pragma: no cover - optional integration
    sentry_sdk = None


def _ensure_tables(settings) -> None:
    """Create any missing tables (e.g. after adding new models)."""
    if not settings.use_database:
        return
    database_url = settings.effective_database_url
    if database_url is None:
        return
    try:
        from app.infrastructure.persistence.models import Base  # noqa: F811
        from app.infrastructure.persistence.session import get_engine, normalize_database_url
        from sqlalchemy import text
        engine = get_engine(normalize_database_url(database_url))
        Base.metadata.create_all(engine, checkfirst=True)
        # Migrate: add TII columns to latest_transits if missing
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE latest_transits ADD COLUMN IF NOT EXISTS tii FLOAT"))
            conn.execute(text("ALTER TABLE latest_transits ADD COLUMN IF NOT EXISTS tension_ratio FLOAT"))
            conn.execute(text("ALTER TABLE latest_transits ADD COLUMN IF NOT EXISTS feels_like VARCHAR(64)"))
    except Exception:
        pass  # non-fatal — tables may already exist


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(environment=settings.environment)

    _ensure_tables(settings)

    if settings.sentry_dsn and sentry_sdk is not None:
        sentry_sdk.init(dsn=settings.sentry_dsn, traces_sample_rate=0.0)

    app = FastAPI(title=settings.app_name)

    if settings.cors_allowed_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_allowed_origins,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    if (settings.frontend_dist_dir / "assets").exists():
        app.mount(
            "/assets",
            StaticFiles(directory=str(settings.frontend_dist_dir / "assets")),
            name="frontend-assets",
        )

    # Serve root-level static files (og-image.png, favicon.ico, robots.txt, etc.)
    _root_static = settings.frontend_dist_dir

    @app.get("/og-image.png", include_in_schema=False)
    @app.get("/favicon.ico", include_in_schema=False)
    @app.get("/favicon-32x32.png", include_in_schema=False)
    @app.get("/favicon-16x16.png", include_in_schema=False)
    @app.get("/favicon.svg", include_in_schema=False)
    @app.get("/apple-touch-icon.png", include_in_schema=False)
    @app.get("/robots.txt", include_in_schema=False)
    def serve_root_static(request: Request):
        fname = request.url.path.lstrip("/")
        fpath = _root_static / fname
        if fpath.exists():
            return FileResponse(str(fpath))
        raise HTTPException(status_code=404)

    @app.get("/sitemap.xml", include_in_schema=False)
    def dynamic_sitemap():
        """Sitemap index: static pages + news sitemap."""
        from app.api.v1.routes.news import _get_published_posts

        xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
        xml += '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'

        # Static pages
        xml += "  <url>\n"
        xml += "    <loc>https://big3.me/</loc>\n"
        xml += "    <changefreq>daily</changefreq>\n"
        xml += "    <priority>1.0</priority>\n"
        xml += "  </url>\n"
        xml += "  <url>\n"
        xml += "    <loc>https://big3.me/news/</loc>\n"
        xml += "    <changefreq>daily</changefreq>\n"
        xml += "    <priority>0.9</priority>\n"
        xml += "  </url>\n"

        # News posts
        try:
            posts = _get_published_posts(limit=500)
            for post in posts:
                xml += "  <url>\n"
                xml += f"    <loc>https://big3.me/news/{post['slug']}</loc>\n"
                xml += f"    <lastmod>{post['date']}</lastmod>\n"
                xml += "    <changefreq>monthly</changefreq>\n"
                xml += "    <priority>0.7</priority>\n"
                xml += "  </url>\n"
        except Exception:
            logging.getLogger(__name__).warning("Could not load news posts for sitemap")

        xml += "</urlset>"
        return Response(content=xml, media_type="application/xml")

    canonical_host = settings.canonical_host.strip().lower() if settings.canonical_host else None

    if canonical_host:
        www_host = f"www.{canonical_host}"

        @app.middleware("http")
        async def redirect_www_to_canonical(request: Request, call_next):
            incoming_host = (request.url.hostname or "").lower()
            if incoming_host == www_host:
                scheme = request.headers.get("x-forwarded-proto", request.url.scheme)
                path = request.url.path
                query = f"?{request.url.query}" if request.url.query else ""
                canonical_url = f"{scheme}://{canonical_host}{path}{query}"
                return RedirectResponse(url=canonical_url, status_code=308)
            return await call_next(request)

    def _serve_spa() -> HTMLResponse:
        index_path = settings.frontend_index_path
        if not index_path.exists():
            raise HTTPException(
                status_code=404,
                detail="Frontend has not been built yet. Run: cd frontend && npm run build",
            )
        return HTMLResponse(index_path.read_text(encoding="utf-8"))

    @app.get("/", response_class=HTMLResponse)
    def home() -> HTMLResponse:
        return _serve_spa()

    @app.get("/invite/{token}", response_class=HTMLResponse)
    def invite_page(token: str) -> HTMLResponse:
        return _serve_spa()

    # News routes: server-rendered Jinja2 HTML (SEO), mounted at /news
    app.include_router(news_router)

    app.include_router(api_v1_router, prefix=settings.api_v1_prefix)
    app.include_router(legacy_router)
    return app


app = create_app()
