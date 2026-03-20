from __future__ import annotations

import json
from pathlib import Path
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

_FOLLOWS_FILE = Path("profiles/_follows.json")


def _load_follows() -> dict[str, list[str]]:
    """Load follows mapping: { user_id: [profile_id, ...] }"""
    if _FOLLOWS_FILE.exists():
        try:
            return json.loads(_FOLLOWS_FILE.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def _save_follows(data: dict[str, list[str]]) -> None:
    _FOLLOWS_FILE.parent.mkdir(parents=True, exist_ok=True)
    _FOLLOWS_FILE.write_text(json.dumps(data, indent=2), encoding="utf-8")


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

    def load_profile_with_social(self, profile_id: str, viewer_user_id: str) -> dict[str, Any]:
        profile = self.load_profile(profile_id)
        profile["followers_count"] = self.count_followers(profile_id)
        profile["following_count"] = self.count_following(viewer_user_id)
        profile["is_following"] = self.is_following(viewer_user_id, profile_id)
        profile["is_own"] = (viewer_user_id == profile.get("user_id", "user_local_dev"))
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

    def delete_profile(self, profile_id: str) -> None:
        import os
        path = profile_path(profile_id)
        if os.path.exists(path):
            os.remove(path)
        else:
            raise FileNotFoundError(f"Natal profile not found: {profile_id}")

    def resolve_profile_chart_id(self, profile_id: str) -> str:
        return resolve_profile_chart_id(profile_id)

    def delete_chart_if_unreferenced(
        self,
        chart_id: str,
        *,
        exclude_profile_id: str | None = None,
    ) -> None:
        delete_chart_if_unreferenced(chart_id, exclude_profile_id=exclude_profile_id)

    def list_featured(self, limit: int = 20) -> list[dict[str, Any]]:
        return []

    def set_featured(self, profile_id: str, featured: bool) -> None:
        pass

    def search_public(self, query: str, *, limit: int = 20) -> list[dict[str, Any]]:
        bootstrap_profiles()
        all_summaries = list_profile_summaries()
        query_lower = query.lower()
        results = [
            s for s in all_summaries
            if query_lower in s.get("username", "").lower()
               or query_lower in s.get("profile_name", "").lower()
        ]
        return results[:limit]

    def follow_profile(self, user_id: str, profile_id: str) -> None:
        data = _load_follows()
        user_follows = data.get(user_id, [])
        if profile_id not in user_follows:
            user_follows.append(profile_id)
            data[user_id] = user_follows
            _save_follows(data)

    def unfollow_profile(self, user_id: str, profile_id: str) -> None:
        data = _load_follows()
        user_follows = data.get(user_id, [])
        if profile_id in user_follows:
            user_follows.remove(profile_id)
            data[user_id] = user_follows
            _save_follows(data)

    def list_followed(self, user_id: str) -> list[dict[str, Any]]:
        data = _load_follows()
        followed_ids = data.get(user_id, [])
        if not followed_ids:
            return []
        bootstrap_profiles()
        all_summaries = list_profile_summaries()
        results = []
        for s in all_summaries:
            if s.get("profile_id") in followed_ids:
                s["is_own"] = False
                s["is_following"] = True
                results.append(s)
        return results

    def is_following(self, user_id: str, profile_id: str) -> bool:
        data = _load_follows()
        return profile_id in data.get(user_id, [])

    def count_followers(self, profile_id: str) -> int:
        data = _load_follows()
        return sum(1 for follows in data.values() if profile_id in follows)

    def count_following(self, user_id: str) -> int:
        data = _load_follows()
        return len(data.get(user_id, []))

    def get_owner_user_id(self, profile_id: str) -> str | None:
        bootstrap_profiles()
        from natal_profiles import load_profile
        try:
            profile = load_profile(profile_id)
            return profile.get("user_id")
        except FileNotFoundError:
            return None

    def save_latest_transit(self, profile_id: str, latest_transit: dict[str, Any]) -> dict[str, Any]:
        return save_profile_latest_transit(profile_id, latest_transit)

    def get_primary_profile_id(self, user_id: str) -> str | None:
        del user_id
        return None

    def set_primary_profile_id(self, user_id: str, profile_id: str) -> None:
        del user_id, profile_id

    def create_invite(self, profile_id: str, invited_email: str, token: str, invited_by: str, expires_at: object) -> dict[str, Any]:
        raise NotImplementedError("Invites require database persistence")

    def get_invite_by_token(self, token: str) -> dict[str, Any] | None:
        raise NotImplementedError("Invites require database persistence")

    def accept_invite(self, token: str, new_user_id: str) -> dict[str, Any]:
        raise NotImplementedError("Invites require database persistence")


class NullLocationCacheRepository:
    def get(self, query: str) -> dict[str, Any] | None:
        del query
        return None

    def put(self, query: str, payload: dict[str, Any]) -> dict[str, Any]:
        del query
        return payload
