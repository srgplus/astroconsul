from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv

# Load .env from project root (two levels up from this file)
load_dotenv(Path(__file__).resolve().parents[2] / ".env")


def _parse_csv(value: str | None) -> list[str]:
    if value is None:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


@dataclass(frozen=True)
class Settings:
    app_name: str
    environment: str
    api_v1_prefix: str
    persistence_backend: str
    database_url: str | None
    local_database_url: str
    cors_allowed_origins: list[str]
    sentry_dsn: str | None
    frontend_dist_dir: Path
    legacy_template_path: Path
    ephemeris_path: Path
    charts_dir: Path
    profiles_dir: Path
    default_user_id: str
    default_auth_subject: str
    default_user_email: str
    canonical_host: str | None
    auth_enabled: bool
    supabase_url: str | None
    supabase_anon_key: str | None
    supabase_jwt_secret: str | None
    resend_api_key: str | None

    @property
    def use_database(self) -> bool:
        return self.persistence_backend.lower() in ("database", "supabase")

    @property
    def effective_database_url(self) -> str | None:
        if not self.use_database:
            return None
        return self.database_url or self.local_database_url

    @property
    def frontend_index_path(self) -> Path:
        return self.frontend_dist_dir / "index.html"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    project_root = Path(__file__).resolve().parents[2]

    return Settings(
        app_name=os.getenv("ASTRO_CONSUL_APP_NAME", "Astro Consul"),
        environment=os.getenv("ASTRO_CONSUL_ENV", "development"),
        api_v1_prefix=os.getenv("ASTRO_CONSUL_API_V1_PREFIX", "/api/v1"),
        persistence_backend=os.getenv("ASTRO_CONSUL_PERSISTENCE_BACKEND", "file"),
        database_url=os.getenv("ASTRO_CONSUL_DATABASE_URL"),
        local_database_url=os.getenv(
            "ASTRO_CONSUL_LOCAL_DATABASE_URL",
            f"sqlite:///{project_root / 'astro_consul.db'}",
        ),
        cors_allowed_origins=_parse_csv(os.getenv("ASTRO_CONSUL_CORS_ORIGINS")),
        sentry_dsn=os.getenv("ASTRO_CONSUL_SENTRY_DSN"),
        frontend_dist_dir=project_root / "frontend" / "dist",
        legacy_template_path=project_root / "templates" / "index.html",
        ephemeris_path=project_root / "ephe",
        charts_dir=project_root / "charts",
        profiles_dir=project_root / "profiles",
        default_user_id=os.getenv("ASTRO_CONSUL_DEFAULT_USER_ID", "user_local_dev"),
        default_auth_subject=os.getenv("ASTRO_CONSUL_DEFAULT_AUTH_SUBJECT", "local-dev"),
        default_user_email=os.getenv("ASTRO_CONSUL_DEFAULT_USER_EMAIL", "local@example.com"),
        canonical_host=os.getenv("ASTRO_CONSUL_CANONICAL_HOST"),
        auth_enabled=os.getenv("ASTRO_CONSUL_AUTH_ENABLED", "false").lower() in ("true", "1", "yes"),
        supabase_url=os.getenv("ASTRO_CONSUL_SUPABASE_URL"),
        supabase_anon_key=os.getenv("ASTRO_CONSUL_SUPABASE_ANON_KEY"),
        supabase_jwt_secret=os.getenv("ASTRO_CONSUL_SUPABASE_JWT_SECRET"),
        resend_api_key=os.getenv("ASTRO_CONSUL_RESEND_API_KEY"),
    )


def clear_settings_cache() -> None:
    get_settings.cache_clear()
