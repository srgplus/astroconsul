from __future__ import annotations

from typing import Any

from app.domain.astrology.charts import load_saved_chart, save_chart
from natal_profiles import (
    bootstrap_profiles,
    create_profile,
    delete_chart_if_unreferenced,
    list_profile_summaries,
    load_profile,
    resolve_profile_chart_id,
    save_profile_latest_transit,
    update_profile,
)


class FileChartRepository:
    def save_chart(self, chart: dict[str, object], chart_id: str | None = None) -> tuple[str, str]:
        saved_chart_id, output_path = save_chart(chart, chart_id=chart_id)
        return saved_chart_id, str(output_path)

    def load_chart(self, chart_id: str) -> tuple[str, dict[str, object]]:
        chart_path, chart = load_saved_chart(chart_id)
        return str(chart_path), chart


class FileProfileRepository:
    def list_summaries(self, *, user_id: str | None = None) -> list[dict[str, Any]]:
        bootstrap_profiles()
        summaries = list_profile_summaries()
        if user_id is not None:
            summaries = [s for s in summaries if s.get("user_id", "user_local_dev") == user_id]
        return summaries

    def load_profile(self, profile_id: str) -> dict[str, Any]:
        _, profile = load_profile(profile_id)
        return profile

    def create_profile(
        self,
        profile_name: str,
        username: str,
        chart_id: str,
        *,
        user_id: str | None = None,
        profile_input: dict[str, object] | None = None,
        profile_id: str | None = None,
        created_at: str | None = None,
        updated_at: str | None = None,
    ) -> dict[str, Any]:
        del profile_input
        payload = create_profile(
            profile_name,
            username,
            chart_id,
            created_at=created_at,
            updated_at=updated_at,
        )
        dirty = False
        if profile_id is not None:
            payload["profile_id"] = profile_id
            dirty = True
        if user_id is not None:
            payload["user_id"] = user_id
            dirty = True
        if dirty:
            from natal_profiles import write_json, profile_path
            write_json(profile_path(payload["profile_id"]), payload)
        return payload

    def update_profile(
        self,
        profile_id: str,
        profile_name: str,
        username: str,
        chart_id: str,
        *,
        profile_input: dict[str, object] | None = None,
    ) -> dict[str, Any]:
        del profile_input
        return update_profile(profile_id, profile_name, username, chart_id)

    def resolve_profile_chart_id(self, profile_id: str) -> str:
        return resolve_profile_chart_id(profile_id)

    def delete_chart_if_unreferenced(
        self,
        chart_id: str,
        *,
        exclude_profile_id: str | None = None,
    ) -> None:
        delete_chart_if_unreferenced(chart_id, exclude_profile_id=exclude_profile_id)

    def search_public(self, query: str, *, limit: int = 20) -> list[dict[str, Any]]:
        bootstrap_profiles()
        all_summaries = list_profile_summaries()
        query_lower = query.lower()
        results = [
            s for s in all_summaries
            if query_lower in s.get("username", "").lower()
        ]
        return results[:limit]

    def save_latest_transit(self, profile_id: str, latest_transit: dict[str, Any]) -> dict[str, Any]:
        return save_profile_latest_transit(profile_id, latest_transit)


class NullLocationCacheRepository:
    def get(self, query: str) -> dict[str, Any] | None:
        del query
        return None

    def put(self, query: str, payload: dict[str, Any]) -> dict[str, Any]:
        del query
        return payload
