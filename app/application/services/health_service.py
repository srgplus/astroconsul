from __future__ import annotations

from pathlib import Path

from app.core.config import Settings
from app.infrastructure.persistence.session import database_healthcheck


class HealthService:
    def __init__(self, settings: Settings):
        self.settings = settings

    def live(self) -> dict[str, object]:
        return {
            "status": "ok",
            "app": self.settings.app_name,
            "environment": self.settings.environment,
        }

    def ready(self) -> dict[str, object]:
        ephemeris_exists = Path(self.settings.ephemeris_path).exists()
        frontend_status = "ready" if self.settings.frontend_index_path.exists() else "not-built"
        database_status = database_healthcheck(self.settings)
        overall = "ok" if ephemeris_exists and database_status["status"] != "error" else "error"

        return {
            "status": overall,
            "checks": {
                "database": database_status,
                "ephemeris": {
                    "status": "ok" if ephemeris_exists else "error",
                    "detail": str(self.settings.ephemeris_path),
                },
                "frontend": {
                    "status": frontend_status,
                    "detail": str(self.settings.frontend_index_path),
                },
            },
        }
