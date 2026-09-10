from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from functools import lru_cache

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings, get_settings


def normalize_database_url(database_url: str) -> str:
    if database_url.startswith("postgres://"):
        return database_url.replace("postgres://", "postgresql+psycopg://", 1)
    if database_url.startswith("postgresql://"):
        return database_url.replace("postgresql://", "postgresql+psycopg://", 1)
    return database_url


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


def describe_database_url(database_url: str) -> str:
    """The connection's shape with its password masked.

    `GET /api/v1/health/ready` is unauthenticated and prints this, and it used
    to print the whole normalized URL — which put the production Postgres user,
    host and *password* on a public endpoint for anyone who asked. SQLAlchemy
    renders the password as `***` and leaves the rest legible, which is all a
    readiness probe ever needed.
    """
    try:
        return make_url(normalize_database_url(database_url)).render_as_string(hide_password=True)
    except Exception:
        # An unparseable URL is not worth echoing back: whatever is wrong with
        # it, the raw string is the one thing that must not be returned.
        return "unparseable database url"


def _scrub_password(text_: str, database_url: str) -> str:
    """Whatever the driver said, minus the password if it said that too."""
    try:
        password = make_url(normalize_database_url(database_url)).password
    except Exception:
        password = None
    if not password:
        return text_
    return text_.replace(password, "***")


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
        # Driver errors quote the URL they failed to connect with, password
        # and all, so the message goes out scrubbed rather than raw.
        return {"status": "error", "detail": _scrub_password(str(exc), database_url)}

    return {"status": "ok", "detail": describe_database_url(database_url)}
