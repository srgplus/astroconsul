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


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(environment=settings.environment)

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

    app.include_router(api_v1_router, prefix=settings.api_v1_prefix)
    app.include_router(legacy_router)
    return app


app = create_app()
