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
    # Where a report filed in the app is sent for a person to act on: the same
    # inbox the Terms and the support page publish, where all user mail lands.
    moderation_email: str = "big3meapp@gmail.com"
    # The sender on every mail the backend sends. big3.me is a verified
    # sending domain in Resend (DKIM on resend._domainkey, SPF and MX on the
    # `send` subdomain); the sandbox sender it replaces could only reach the
    # Resend account's own inbox, so invites and reports to anyone else failed.
    email_from: str = "big3.me <noreply@big3.me>"
    # Apple Push Notification service, token-based: a .p8 key with APNs
    # enabled (Apple Developer > Keys), its Key ID, the team, and the app's
    # bundle id as the topic. Without a key and its id no push is sent, and
    # likes and follows still land in Activity.
    apns_key_id: str | None = None
    apns_private_key: str | None = None
    apns_team_id: str = "85679N47YT"
    apns_topic: str = "me.big3.app"

    @property
    def apns_enabled(self) -> bool:
        return bool(self.apns_key_id and self.apns_private_key)

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
        moderation_email=os.getenv("ASTRO_CONSUL_MODERATION_EMAIL", "big3meapp@gmail.com"),
        email_from=os.getenv("ASTRO_CONSUL_EMAIL_FROM", "big3.me <noreply@big3.me>"),
        apns_key_id=os.getenv("ASTRO_CONSUL_APNS_KEY_ID"),
        # Railway keeps a pasted .p8 on one line with its newlines written
        # out as "\n"; the PEM parser wants them back.
        apns_private_key=(os.getenv("ASTRO_CONSUL_APNS_PRIVATE_KEY") or "").replace("\\n", "\n") or None,
        apns_team_id=os.getenv("ASTRO_CONSUL_APNS_TEAM_ID", "85679N47YT"),
        apns_topic=os.getenv("ASTRO_CONSUL_APNS_TOPIC", "me.big3.app"),
    )


def clear_settings_cache() -> None:
    get_settings.cache_clear()
