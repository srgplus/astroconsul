from __future__ import annotations

import os
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import create_app
from app.core.config import clear_settings_cache


class HealthEndpointTests(unittest.TestCase):
    def setUp(self) -> None:
        clear_settings_cache()
        self.client = TestClient(create_app())

    def tearDown(self) -> None:
        clear_settings_cache()

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
