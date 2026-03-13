from __future__ import annotations

from typing import Any, Protocol


class ChartRepository(Protocol):
    def save_chart(self, chart: dict[str, object], chart_id: str | None = None) -> tuple[str, str]: ...
    def load_chart(self, chart_id: str) -> tuple[str, dict[str, object]]: ...


class ProfileRepository(Protocol):
    def list_summaries(self) -> list[dict[str, Any]]: ...
    def load_profile(self, profile_id: str) -> dict[str, Any]: ...
    def create_profile(
        self,
        profile_name: str,
        username: str,
        chart_id: str,
        *,
        profile_input: dict[str, object] | None = None,
        profile_id: str | None = None,
        created_at: str | None = None,
        updated_at: str | None = None,
    ) -> dict[str, Any]: ...
    def update_profile(
        self,
        profile_id: str,
        profile_name: str,
        username: str,
        chart_id: str,
        *,
        profile_input: dict[str, object] | None = None,
    ) -> dict[str, Any]: ...
    def resolve_profile_chart_id(self, profile_id: str) -> str: ...
    def delete_chart_if_unreferenced(self, chart_id: str, *, exclude_profile_id: str | None = None) -> None: ...
    def save_latest_transit(self, profile_id: str, latest_transit: dict[str, Any]) -> dict[str, Any]: ...


class LocationCacheRepository(Protocol):
    def get(self, query: str) -> dict[str, Any] | None: ...
    def put(self, query: str, payload: dict[str, Any]) -> dict[str, Any]: ...
