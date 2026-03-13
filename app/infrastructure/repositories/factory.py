from __future__ import annotations

from dataclasses import dataclass

from app.core.config import Settings, get_settings
from app.infrastructure.persistence.session import database_url_for_settings, get_session_factory
from app.infrastructure.repositories.file_repositories import (
    FileChartRepository,
    FileProfileRepository,
    NullLocationCacheRepository,
)
from app.infrastructure.repositories.sqlalchemy_repositories import (
    SqlAlchemyChartRepository,
    SqlAlchemyLocationCacheRepository,
    SqlAlchemyProfileRepository,
)


@dataclass(frozen=True)
class RepositoryBundle:
    charts: object
    profiles: object
    locations: object


def get_repository_bundle(settings: Settings | None = None) -> RepositoryBundle:
    resolved_settings = settings or get_settings()
    database_url = database_url_for_settings(resolved_settings)
    if resolved_settings.use_database and database_url is not None:
        session_factory = get_session_factory(database_url)
        charts = SqlAlchemyChartRepository(session_factory)
        profiles = SqlAlchemyProfileRepository(session_factory, resolved_settings, charts)
        locations = SqlAlchemyLocationCacheRepository(session_factory)
        return RepositoryBundle(charts=charts, profiles=profiles, locations=locations)

    return RepositoryBundle(
        charts=FileChartRepository(),
        profiles=FileProfileRepository(),
        locations=NullLocationCacheRepository(),
    )
