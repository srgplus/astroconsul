from __future__ import annotations

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
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
        engine = get_engine(normalize_database_url(database_url))
        Base.metadata.create_all(engine, checkfirst=True)
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

    @app.get("/", response_class=HTMLResponse)
    def home() -> HTMLResponse:
        index_path = settings.frontend_index_path
        if not index_path.exists():
            raise HTTPException(
                status_code=404,
                detail="Frontend has not been built yet. Run: cd frontend && npm run build",
            )
        return HTMLResponse(index_path.read_text(encoding="utf-8"))

    @app.get("/api/debug/db")
    def debug_db() -> dict[str, object]:
        """Temporary diagnostic endpoint for database connectivity."""
        import traceback
        from app.infrastructure.persistence.session import (
            database_url_for_settings,
            normalize_database_url,
        )
        info: dict[str, object] = {
            "persistence_backend": settings.persistence_backend,
            "use_database": settings.use_database,
        }
        raw_url = database_url_for_settings(settings)
        if raw_url:
            # Mask password in output
            import re
            masked = re.sub(r"://([^:]+):([^@]+)@", r"://\1:****@", raw_url)
            info["raw_url"] = masked
            normalized = normalize_database_url(raw_url)
            masked_norm = re.sub(r"://([^:]+):([^@]+)@", r"://\1:****@", normalized)
            info["normalized_url"] = masked_norm
            try:
                from app.infrastructure.persistence.session import get_engine
                from sqlalchemy import text
                engine = get_engine(normalized)
                with engine.connect() as conn:
                    conn.execute(text("SELECT 1"))
                info["connection"] = "ok"
            except Exception as exc:
                info["connection"] = "error"
                info["error"] = str(exc)
                info["traceback"] = traceback.format_exc()
        else:
            info["raw_url"] = None
        return info

    app.include_router(api_v1_router, prefix=settings.api_v1_prefix)
    app.include_router(legacy_router)
    return app


app = create_app()
