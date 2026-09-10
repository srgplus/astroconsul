from __future__ import annotations

import os
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.api.dependencies import get_health_service
from app.core.config import clear_settings_cache, get_settings
from app.infrastructure.persistence.session import database_healthcheck
from app.main import create_app


class HealthEndpointTests(unittest.TestCase):
    def setUp(self) -> None:
        self._reset_caches()
        self.client = TestClient(create_app())

    def tearDown(self) -> None:
        self._reset_caches()

    @staticmethod
    def _reset_caches() -> None:
        """`get_health_service` is `lru_cache`d and keeps the `Settings` it was
        first built with, so clearing the settings cache alone leaves a service
        answering from the previous test's environment."""
        clear_settings_cache()
        get_health_service.cache_clear()

    def test_live_endpoint_reports_basic_app_status(self) -> None:
        response = self.client.get("/api/v1/health/live")

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["status"], "ok")
        self.assertEqual(payload["app"], "Astro Consul")

    def test_ready_endpoint_reports_database_ephemeris_and_frontend_checks(self) -> None:
        response = self.client.get("/api/v1/health/ready")

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertIn(payload["status"], {"ok", "error"})
        self.assertEqual(payload["checks"]["database"]["status"], "skipped")
        self.assertEqual(payload["checks"]["ephemeris"]["status"], "ok")
        self.assertIn(payload["checks"]["frontend"]["status"], {"ready", "not-built"})

    def test_www_host_redirects_to_configured_canonical_host(self) -> None:
        with patch.dict(os.environ, {"ASTRO_CONSUL_CANONICAL_HOST": "big3.me"}, clear=False):
            clear_settings_cache()
            client = TestClient(create_app())

            response = client.get(
                "/api/v1/health/live?from=test",
                headers={"host": "www.big3.me", "x-forwarded-proto": "https"},
                follow_redirects=False,
            )

        self.assertEqual(response.status_code, 308)
        self.assertEqual(response.headers["location"], "https://big3.me/api/v1/health/live?from=test")


if __name__ == "__main__":
    unittest.main()


class _StubConnection:
    def __enter__(self) -> _StubConnection:
        return self

    def __exit__(self, *exc: object) -> bool:
        return False

    def execute(self, statement: object) -> None:
        return None


class _StubEngine:
    """An engine whose SELECT 1 succeeds, so the check takes its ok branch."""

    def connect(self) -> _StubConnection:
        return _StubConnection()


class DatabaseHealthDetailTests(unittest.TestCase):
    """The readiness check names the database it reached, and must not name the
    password with it: `GET /api/v1/health/ready` needs no authentication, and
    this field used to carry the entire production connection string."""

    PASSWORD = "sup3rs3cret"  # noqa: S105 - fake, and the point of the assertions
    URL = f"postgresql://postgres.abc:{PASSWORD}@db.example.test:5432/postgres"

    def setUp(self) -> None:
        clear_settings_cache()

    def tearDown(self) -> None:
        clear_settings_cache()

    def _database_settings(self) -> object:
        with patch.dict(
            os.environ,
            {
                "ASTRO_CONSUL_DATABASE_URL": self.URL,
                "ASTRO_CONSUL_PERSISTENCE_BACKEND": "database",
            },
            clear=False,
        ):
            clear_settings_cache()
            return get_settings()

    def test_a_reached_database_is_named_without_its_password(self) -> None:
        settings = self._database_settings()

        with patch(
            "app.infrastructure.persistence.session.get_engine",
            return_value=_StubEngine(),
        ):
            result = database_healthcheck(settings)  # type: ignore[arg-type]

        self.assertEqual(result["status"], "ok")
        self.assertNotIn(self.PASSWORD, str(result))
        # Still useful as a probe: the host and database are legible.
        self.assertIn("db.example.test", str(result["detail"]))
        self.assertIn("postgres", str(result["detail"]))

    def test_a_driver_error_quoting_the_url_is_scrubbed(self) -> None:
        settings = self._database_settings()

        with patch(
            "app.infrastructure.persistence.session.get_engine",
            side_effect=RuntimeError(f"could not connect using {self.URL}"),
        ):
            result = database_healthcheck(settings)  # type: ignore[arg-type]

        self.assertEqual(result["status"], "error")
        self.assertNotIn(self.PASSWORD, str(result))
