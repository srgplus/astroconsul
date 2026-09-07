"""The free/Pro split on interpretation prose is enforced by the API, not the client.

``require_pro`` in ``app/api/dependencies.py`` was wired to no route, so every
authenticated caller received the written interpretations and a free account
could read the whole paid report off the browser's network tab. The routes now
trim the response instead — free keeps the allowance it is shown, and nothing
past it.
"""

from __future__ import annotations

import unittest
from typing import Any
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.api.auth import get_current_user
from app.api.dependencies import get_repositories
from app.api.paywall import FREE_LIMIT, PAID_ASPECT_FIELDS, caller_is_pro
from app.core.config import get_settings
from app.infrastructure.repositories.factory import RepositoryBundle, get_repository_bundle
from app.main import create_app
from chart_builder import build_chart, save_chart

USER_ID = "user_paywall_test"
PROFILE_ID = "profile_paywall_test"

REPORT_BODY = {
    "transit_date": "2026-03-09",
    "transit_time": "06:06:01",
    "timezone": "Europe/Warsaw",
    "include_timing": False,
    "lang": "en",
}


class FakeProfileRepository:
    """In-memory stand-in holding one profile pointed at a real saved chart."""

    def __init__(self, chart_filename: str) -> None:
        self.chart_filename = chart_filename
        self.saved_transits: list[dict[str, Any]] = []

    def load_profile(self, profile_id: str) -> dict[str, Any]:
        if profile_id != PROFILE_ID:
            raise FileNotFoundError(f"Natal profile not found: {profile_id}")
        return {
            "profile_id": PROFILE_ID,
            "user_id": USER_ID,
            "chart_id": self.chart_filename,
            "profile_name": "Paywall Test",
            "username": "paywall_test",
            "created_at": "2026-01-01T00:00:00+00:00",
            "updated_at": "2026-01-01T00:00:00+00:00",
        }

    def load_profile_with_social(self, profile_id: str, viewer_user_id: str) -> dict[str, Any]:
        return {
            **self.load_profile(profile_id),
            "followers_count": 0,
            "following_count": 0,
            "is_following": False,
            "is_own": viewer_user_id == USER_ID,
        }

    def resolve_profile_chart_id(self, profile_id: str) -> str:
        return self.load_profile(profile_id)["chart_id"]

    def save_latest_transit(self, profile_id: str, snapshot: dict[str, Any]) -> None:
        self.saved_transits.append({"profile_id": profile_id, **snapshot})


class PaywallRouteTestCase(unittest.TestCase):
    """Wires the profile routes to one real chart and a caller of a chosen plan."""

    @classmethod
    def setUpClass(cls) -> None:
        # A real chart, so the report carries real aspects to gate.
        chart = build_chart(1991, 7, 28, 22.1, 52.13472, 23.65694)
        _, chart_path = save_chart(chart, chart_id="chart_paywall_test")
        cls.chart_filename = chart_path.name

    def setUp(self) -> None:
        self.repo = FakeProfileRepository(self.chart_filename)
        self.app = create_app()
        self.app.dependency_overrides[get_repositories] = lambda: RepositoryBundle(
            charts=get_repository_bundle(get_settings()).charts,
            profiles=self.repo,  # type: ignore[arg-type]
            locations=None,  # type: ignore[arg-type]
        )
        self.app.dependency_overrides[get_current_user] = lambda: {
            "user_id": USER_ID,
            "email": "free@example.test",
        }
        self.client = TestClient(self.app)

    def tearDown(self) -> None:
        self.app.dependency_overrides.clear()

    def _report_as(self, is_pro: bool) -> dict[str, Any]:
        self.app.dependency_overrides[caller_is_pro] = lambda: is_pro
        response = self.client.post(f"/api/v1/profiles/{PROFILE_ID}/transits/report", json=REPORT_BODY)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def _detail_as(self, is_pro: bool) -> dict[str, Any]:
        self.app.dependency_overrides[caller_is_pro] = lambda: is_pro
        response = self.client.get(f"/api/v1/profiles/{PROFILE_ID}", params={"lang": "en"})
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()


class TransitReportPaywallTests(PaywallRouteTestCase):
    # ── the free account ─────────────────────────────────────────────

    def test_free_report_carries_no_meaning_beyond_the_free_allowance(self) -> None:
        aspects = self._report_as(is_pro=False)["active_aspects"]

        # There is something to gate in the first place.
        self.assertGreater(len(aspects), FREE_LIMIT)

        # Two client surfaces order this list differently and each gets its
        # own FREE_LIMIT, so the allowance cannot be wider than the two
        # together — and every aspect outside it is blank.
        with_prose = [aspect for aspect in aspects if aspect.get("meaning")]
        self.assertLessEqual(len(with_prose), 2 * FREE_LIMIT)

        for aspect in aspects:
            if aspect.get("meaning"):
                continue
            label = f"{aspect['transit_object']} {aspect['aspect']} {aspect['natal_object']}"
            with self.subTest(aspect=label):
                for field in PAID_ASPECT_FIELDS:
                    self.assertIsNone(aspect.get(field))

    def test_free_report_still_carries_the_free_allowance(self) -> None:
        aspects = self._report_as(is_pro=False)["active_aspects"]

        # The client draws FREE_LIMIT unlocked rows and each of them has to
        # have text behind it, or the gate has taken the free tier away too.
        with_prose = [aspect for aspect in aspects if aspect.get("meaning")]
        self.assertGreaterEqual(len(with_prose), FREE_LIMIT)

    def test_free_report_keeps_the_free_astrology(self) -> None:
        report = self._report_as(is_pro=False)

        self.assertIn("tii", report)
        self.assertIn("feels_like", report)
        for aspect in report["active_aspects"]:
            # Blanked prose, not a dropped record: the orb and strength a free
            # account is entitled to are still there.
            self.assertIn("orb", aspect)
            self.assertIn("strength", aspect)

    def test_free_report_carries_no_cosmic_climate_prose(self) -> None:
        report = self._report_as(is_pro=False)

        # CosmicClimateWidget draws no text at all for a free account.
        for entry in report.get("cosmic_climate") or []:
            with self.subTest(entry=f"{entry['transit_object']} {entry['aspect']} {entry['natal_object']}"):
                self.assertIsNone(entry.get("meaning"))
                self.assertIsNone(entry.get("insight"))

    def test_free_report_carries_no_top_transit_prose(self) -> None:
        report = self._report_as(is_pro=False)

        # top_transits is a copy of whole aspect records; no screen reads its
        # prose, so none of it is sent.
        for entry in report.get("top_transits") or []:
            with self.subTest(entry=entry.get("transit_object")):
                for field in PAID_ASPECT_FIELDS:
                    self.assertIsNone(entry.get(field))

    # ── the Pro account, i.e. proof the gate is what makes the difference ──

    def test_pro_report_carries_prose_on_every_aspect(self) -> None:
        aspects = self._report_as(is_pro=True)["active_aspects"]

        self.assertGreater(len(aspects), FREE_LIMIT)
        self.assertTrue(all(aspect.get("meaning") for aspect in aspects))

    def test_gate_removes_prose_the_pro_response_had(self) -> None:
        pro = self._report_as(is_pro=True)["active_aspects"]
        free = self._report_as(is_pro=False)["active_aspects"]

        self.assertEqual(len(pro), len(free))
        self.assertGreater(
            sum(1 for aspect in pro if aspect.get("meaning")),
            sum(1 for aspect in free if aspect.get("meaning")),
        )


class ChartPaywallTests(PaywallRouteTestCase):
    """GET /profiles/{id} carried the whole natal_interpretations block."""

    def _counts(self, interpretations: dict[str, Any]) -> dict[str, int]:
        return {key: len(value) for key, value in interpretations.items()}

    def test_free_chart_keeps_only_the_free_allowance(self) -> None:
        interpretations = self._detail_as(is_pro=False)["chart"]["natal_interpretations"]
        counts = self._counts(interpretations)

        # Bodies are counted once however many entries they have — a planet
        # with both a sign and a house reading spends one of the three.
        bodies = set(interpretations["planets_in_signs"]) | set(interpretations["planets_in_houses"])
        self.assertLessEqual(len(bodies), FREE_LIMIT)
        self.assertLessEqual(counts["aspects"], FREE_LIMIT)
        self.assertLessEqual(counts["house_cusps_in_signs"], FREE_LIMIT)

    def test_free_chart_still_carries_something_to_read(self) -> None:
        interpretations = self._detail_as(is_pro=False)["chart"]["natal_interpretations"]

        self.assertTrue(interpretations["planets_in_signs"] or interpretations["planets_in_houses"])
        for entry in interpretations["planets_in_signs"].values():
            self.assertTrue(entry.get("meaning"))

    def test_gate_removes_interpretations_the_pro_response_had(self) -> None:
        pro = self._counts(self._detail_as(is_pro=True)["chart"]["natal_interpretations"])
        free = self._counts(self._detail_as(is_pro=False)["chart"]["natal_interpretations"])

        self.assertGreater(pro["planets_in_signs"], free["planets_in_signs"])
        self.assertGreater(pro["planets_in_houses"], free["planets_in_houses"])
        self.assertGreater(pro["aspects"], free["aspects"])

    def test_free_chart_keeps_the_free_astrology(self) -> None:
        chart = self._detail_as(is_pro=False)["chart"]

        # Only the prose is gated: the positions and aspects it was keyed on
        # are what the tables draw their rows from.
        self.assertTrue(chart["natal_positions"])
        self.assertTrue(chart["natal_aspects"])

    def test_public_route_never_serves_interpretations(self) -> None:
        # Anonymous is never Pro, and this route reads any profile by id — it
        # would otherwise be a way straight around the gate above.
        response = self.client.get(f"/api/v1/public/profiles/{PROFILE_ID}", params={"lang": "en"})

        self.assertEqual(response.status_code, 200, response.text)
        interpretations = response.json()["chart"]["natal_interpretations"]
        bodies = set(interpretations["planets_in_signs"]) | set(interpretations["planets_in_houses"])
        self.assertLessEqual(len(bodies), FREE_LIMIT)
        self.assertLessEqual(len(interpretations["aspects"]), FREE_LIMIT)


class CallerIsProTests(unittest.TestCase):
    """The one place the plan is decided, so the one place worth pinning down."""

    def test_auth_disabled_reads_as_pro(self) -> None:
        # Local development is one synthetic user with no subscription table
        # to read, and it has to keep seeing the whole report.
        with patch("app.api.paywall.get_settings") as settings:
            settings.return_value.auth_enabled = False
            self.assertTrue(caller_is_pro({"user_id": "user_local_dev"}))

    def test_auth_enabled_follows_the_subscription(self) -> None:
        with patch("app.api.paywall.get_settings") as settings:
            settings.return_value.auth_enabled = True
            with patch("app.api.v1.routes.subscriptions.get_user_subscription") as lookup:
                lookup.return_value = {"plan": "lifetime", "is_pro": True, "expires_at": None}
                self.assertTrue(caller_is_pro({"user_id": "u1"}))

                lookup.return_value = {"plan": "free", "is_pro": False, "expires_at": None}
                self.assertFalse(caller_is_pro({"user_id": "u1"}))

                lookup.assert_called_with("u1")


class ForecastPaywallTests(PaywallRouteTestCase):
    """The forecast embeds three whole aspect records per day."""

    def _forecast_as(self, is_pro: bool) -> dict[str, Any]:
        self.app.dependency_overrides[caller_is_pro] = lambda: is_pro
        response = self.client.get(
            f"/api/v1/profiles/{PROFILE_ID}/transits/forecast",
            params={"timezone": "Europe/Warsaw", "days": 2, "start_date": "2026-03-09", "lang": "en"},
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def test_free_forecast_carries_no_prose(self) -> None:
        days = self._forecast_as(is_pro=False)["days"]

        self.assertTrue(days)
        for day in days:
            for entry in day["top_transits"]:
                with self.subTest(date=day["date"], entry=entry.get("transit_object")):
                    for field in PAID_ASPECT_FIELDS:
                        self.assertIsNone(entry.get(field))

    def test_pro_forecast_keeps_prose(self) -> None:
        days = self._forecast_as(is_pro=True)["days"]

        self.assertTrue(any(entry.get("meaning") for day in days for entry in day["top_transits"]))


if __name__ == "__main__":
    unittest.main()
