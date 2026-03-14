from __future__ import annotations

import unittest

from fastapi.testclient import TestClient

from app.main import create_app


class HealthEndpointTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(create_app())

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


if __name__ == "__main__":
    unittest.main()
