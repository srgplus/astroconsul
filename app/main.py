from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from app.api.legacy import router as legacy_router
from app.api.v1.router import router as api_v1_router
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
    _static_root_files = [
        "og-image.png", "favicon.ico", "favicon-32x32.png", "favicon-16x16.png",
        "favicon.svg", "apple-touch-icon.png", "robots.txt", "sitemap.xml",
    ]
    for _fname in _static_root_files:
        _fpath = settings.frontend_dist_dir / _fname
        if _fpath.exists():
            def _make_handler(_p: Path = _fpath):
                @app.get(f"/{_p.name}", include_in_schema=False)
                def _serve():
                    return FileResponse(str(_p))
            _make_handler(_fpath)

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

    @app.get("/", response_class=HTMLResponse)
    def home() -> HTMLResponse:
        index_path = settings.frontend_index_path
        if not index_path.exists():
            raise HTTPException(
                status_code=404,
                detail="Frontend has not been built yet. Run: cd frontend && npm run build",
            )
        return HTMLResponse(index_path.read_text(encoding="utf-8"))

    app.include_router(api_v1_router, prefix=settings.api_v1_prefix)
    app.include_router(legacy_router)
    return app


app = create_app()
