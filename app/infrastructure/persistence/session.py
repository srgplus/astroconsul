from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from functools import lru_cache

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings, get_settings


def _convert_pooler_to_direct(database_url: str) -> str:
    """Convert Supabase pooler URL to direct connection URL.

    Pooler URLs (port 6543) can fail with 'Tenant or user not found'.
    Direct URLs (port 5432) are more reliable for long-lived server processes.
    """
    import re

    # Match: postgres[ql]://postgres.PROJECTREF:PASSWORD@*.pooler.supabase.com:6543/postgres
    match = re.match(
        r"postgres(?:ql)?://postgres\.([^:]+):([^@]+)@[^/]+\.pooler\.supabase\.com:\d+/(.+)",
        database_url,
    )
    if match:
        project_ref, password, dbname = match.groups()
        return f"postgresql://postgres:{password}@db.{project_ref}.supabase.co:5432/{dbname}"
    return database_url


def normalize_database_url(database_url: str) -> str:
    url = _convert_pooler_to_direct(database_url)
    if url.startswith("postgres://"):
        return url.replace("postgres://", "postgresql+psycopg://", 1)
    if url.startswith("postgresql://"):
        return url.replace("postgresql://", "postgresql+psycopg://", 1)
    return url


@lru_cache(maxsize=8)
def get_engine(database_url: str) -> Engine:
    normalized_url = normalize_database_url(database_url)
    connect_args: dict[str, object] = {}
    if normalized_url.startswith("sqlite"):
        connect_args["check_same_thread"] = False
    return create_engine(normalized_url, future=True, pool_pre_ping=True, connect_args=connect_args)


@lru_cache(maxsize=8)
def get_session_factory(database_url: str) -> sessionmaker[Session]:
    return sessionmaker(bind=get_engine(database_url), autoflush=False, autocommit=False, future=True)


def clear_engine_cache() -> None:
    get_session_factory.cache_clear()
    get_engine.cache_clear()


def database_url_for_settings(settings: Settings | None = None) -> str | None:
    resolved_settings = settings or get_settings()
    return resolved_settings.effective_database_url


def database_is_enabled(settings: Settings | None = None) -> bool:
    resolved_settings = settings or get_settings()
    return bool(resolved_settings.use_database and resolved_settings.effective_database_url)


@contextmanager
def session_scope(settings: Settings | None = None) -> Iterator[Session]:
    database_url = database_url_for_settings(settings)
    if database_url is None:
        raise RuntimeError("Database persistence is not enabled.")

    session = get_session_factory(database_url)()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def database_healthcheck(settings: Settings | None = None) -> dict[str, object]:
    resolved_settings = settings or get_settings()
    if not database_is_enabled(resolved_settings):
        return {"status": "skipped", "detail": "file persistence backend"}

    database_url = resolved_settings.effective_database_url
    assert database_url is not None
    try:
        with get_engine(database_url).connect() as connection:
            connection.execute(text("SELECT 1"))
    except Exception as exc:  # pragma: no cover - exercised in integration environments
        return {"status": "error", "detail": str(exc)}

    return {"status": "ok", "detail": normalize_database_url(database_url)}
