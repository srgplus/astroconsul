from __future__ import annotations

import json
import re
from datetime import date, datetime, time, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from chart_builder import CHARTS_DIR

PROFILES_DIR = Path(__file__).resolve().parent / "profiles"
USERNAME_RE = re.compile(r"^[a-z0-9_]+$")


class UsernameConflictError(ValueError):
    pass


def current_utc_datetime() -> datetime:
    return datetime.now(timezone.utc)


def profile_timestamp(value: float) -> str:
    return datetime.fromtimestamp(value, tz=timezone.utc).isoformat().replace("+00:00", "Z")


def now_timestamp() -> str:
    return current_utc_datetime().isoformat().replace("+00:00", "Z")


def ensure_profiles_dir() -> Path:
    PROFILES_DIR.mkdir(parents=True, exist_ok=True)
    return PROFILES_DIR


def profile_path(profile_id: str) -> Path:
    return ensure_profiles_dir() / f"{profile_id}.json"


def chart_path(chart_id: str) -> Path:
    filename = chart_id if chart_id.endswith(".json") else f"{chart_id}.json"
    return CHARTS_DIR / filename


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def normalized_optional_string(value: object) -> str | None:
    text = str(value or "").strip()
    return text or None


def normalized_optional_float(value: object) -> float | None:
    if value in ("", None):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def resolve_transit_timezone(value: object) -> str:
    candidate = str(value or "").strip() or "UTC"
    try:
        ZoneInfo(candidate)
    except ZoneInfoNotFoundError:
        return "UTC"
    return candidate


def normalize_time_string(value: object) -> str | None:
    raw_value = str(value or "").strip()
    if not raw_value:
        return None

    for fmt in ("%H:%M:%S", "%H:%M"):
        try:
            parsed_time = datetime.strptime(raw_value, fmt).time()
        except ValueError:
            continue
        return parsed_time.replace(microsecond=0).isoformat()

    return None


def current_local_transit_fields(timezone_name: str) -> tuple[str, str]:
    tzinfo = ZoneInfo(resolve_transit_timezone(timezone_name))
    current_local = current_utc_datetime().astimezone(tzinfo).replace(microsecond=0)
    return current_local.date().isoformat(), current_local.time().isoformat()


def parse_latest_transit_datetime(latest_transit: dict[str, Any], timezone_name: str) -> datetime | None:
    transit_date_raw = normalized_optional_string(latest_transit.get("transit_date"))
    transit_time_raw = normalize_time_string(latest_transit.get("transit_time"))
    if transit_date_raw is None or transit_time_raw is None:
        return None

    try:
        parsed_date = date.fromisoformat(transit_date_raw)
        parsed_time = time.fromisoformat(transit_time_raw)
        tzinfo = ZoneInfo(resolve_transit_timezone(timezone_name))
    except (ValueError, ZoneInfoNotFoundError):
        return None

    return datetime.combine(parsed_date, parsed_time, tzinfo=tzinfo)


def normalize_latest_transit(latest_transit: object) -> dict[str, Any] | None:
    if not isinstance(latest_transit, dict):
        return None

    timezone_name = resolve_transit_timezone(latest_transit.get("timezone"))
    current_date, current_time = current_local_transit_fields(timezone_name)
    local_datetime = parse_latest_transit_datetime(latest_transit, timezone_name)
    is_stale = local_datetime is None or local_datetime.astimezone(timezone.utc) < current_utc_datetime()

    return {
        "transit_date": current_date if is_stale else local_datetime.date().isoformat(),
        "transit_time": current_time if is_stale else local_datetime.time().replace(microsecond=0).isoformat(),
        "timezone": timezone_name,
        "location_name": normalized_optional_string(latest_transit.get("location_name")),
        "latitude": normalized_optional_float(latest_transit.get("latitude")),
        "longitude": normalized_optional_float(latest_transit.get("longitude")),
        "updated_at": now_timestamp() if is_stale else normalized_optional_string(latest_transit.get("updated_at")) or now_timestamp(),
    }


def materialize_profile(path: Path, payload: dict[str, Any]) -> dict[str, Any]:
    normalized = dict(payload)
    latest_transit = normalize_latest_transit(payload.get("latest_transit"))

    if latest_transit is None:
        normalized.pop("latest_transit", None)
    else:
        normalized["latest_transit"] = latest_transit

    if normalized != payload:
        write_json(path, normalized)

    return normalized


def normalize_username(value: str) -> str:
    normalized = value.strip().lower()
    if normalized.startswith("@"):
        normalized = normalized[1:]
    return normalized


def validate_username(value: str) -> str:
    normalized = normalize_username(value)
    if not normalized:
        raise ValueError("username is required.")
    if not USERNAME_RE.fullmatch(normalized):
        raise ValueError("username must contain only lowercase letters, numbers, and underscores.")
    return normalized


def slugify_username(value: str) -> str:
    slug = re.sub(r"[^a-z0-9_]+", "_", value.strip().lower())
    slug = re.sub(r"_+", "_", slug).strip("_")
    return slug or "profile"


def iter_profile_paths() -> list[Path]:
    ensure_profiles_dir()
    return sorted(PROFILES_DIR.glob("profile_*.json"))


def load_profile(profile_id: str) -> tuple[Path, dict[str, Any]]:
    path = profile_path(profile_id)
    if not path.exists():
        raise FileNotFoundError(f"Natal profile not found: {profile_id}")
    return path, materialize_profile(path, load_json(path))


def load_all_profiles() -> list[dict[str, Any]]:
    return [
        materialize_profile(path, load_json(path))
        for path in iter_profile_paths()
    ]


def existing_usernames(*, exclude_profile_id: str | None = None) -> set[str]:
    usernames: set[str] = set()
    for profile in load_all_profiles():
        if exclude_profile_id and profile.get("profile_id") == exclude_profile_id:
            continue
        username = str(profile.get("username") or "").strip()
        if username:
            usernames.add(username)
    return usernames


def chart_is_linked(chart_id: str, *, exclude_profile_id: str | None = None) -> bool:
    for profile in load_all_profiles():
        if exclude_profile_id and profile.get("profile_id") == exclude_profile_id:
            continue
        if str(profile.get("chart_id")) == chart_id:
            return True
    return False


def ensure_username_available(username: str, *, exclude_profile_id: str | None = None) -> str:
    normalized = validate_username(username)
    if normalized in existing_usernames(exclude_profile_id=exclude_profile_id):
        raise UsernameConflictError("username is already taken.")
    return normalized


def next_unique_username(seed: str, used_usernames: set[str]) -> str:
    base = slugify_username(seed)
    candidate = base
    suffix = 2
    while candidate in used_usernames:
        candidate = f"{base}_{suffix}"
        suffix += 1
    used_usernames.add(candidate)
    return candidate


def derive_profile_name(chart_id: str, chart: dict[str, Any]) -> str:
    birth_input = chart.get("birth_input") or {}
    return str(
        birth_input.get("name")
        or birth_input.get("location_name")
        or chart_id
    )


def profile_summary(profile: dict[str, Any], chart: dict[str, Any]) -> dict[str, Any]:
    birth_input = chart.get("birth_input") or {}
    return {
        "profile_id": profile["profile_id"],
        "profile_name": profile["profile_name"],
        "username": profile["username"],
        "chart_id": profile["chart_id"],
        "created_at": profile["created_at"],
        "updated_at": profile["updated_at"],
        "name": birth_input.get("name"),
        "location_name": birth_input.get("location_name"),
        "timezone": birth_input.get("timezone"),
        "local_birth_datetime": birth_input.get("local_birth_datetime"),
        "natal_summary": chart.get("natal_summary"),
        "latest_transit": profile.get("latest_transit"),
    }


def bootstrap_profiles() -> None:
    ensure_profiles_dir()
    profiles = load_all_profiles()
    if profiles:
        return

    chart_ids_with_profiles = {str(profile.get("chart_id")) for profile in profiles}
    used_usernames = {
        str(profile.get("username"))
        for profile in profiles
        if str(profile.get("username") or "").strip()
    }

    for path in sorted(CHARTS_DIR.glob("*.json")):
        chart_id = path.stem
        if chart_id in chart_ids_with_profiles:
            continue

        chart = load_json(path)
        generated_at = profile_timestamp(path.stat().st_mtime)
        profile_name = derive_profile_name(chart_id, chart)
        username = next_unique_username(profile_name, used_usernames)
        payload = {
            "profile_id": f"profile_{uuid4().hex}",
            "profile_name": profile_name,
            "username": username,
            "chart_id": chart_id,
            "created_at": generated_at,
            "updated_at": generated_at,
        }
        write_json(profile_path(payload["profile_id"]), payload)
        chart_ids_with_profiles.add(chart_id)


def delete_chart_if_unreferenced(chart_id: str, *, exclude_profile_id: str | None = None) -> None:
    if chart_is_linked(chart_id, exclude_profile_id=exclude_profile_id):
        return

    linked_chart_path = chart_path(chart_id)
    if linked_chart_path.exists():
        linked_chart_path.unlink()


def save_profile_latest_transit(profile_id: str, latest_transit: dict[str, Any]) -> dict[str, Any]:
    path, existing = load_profile(profile_id)
    updated = {
        **existing,
        "latest_transit": normalize_latest_transit(latest_transit),
    }
    write_json(path, updated)
    return updated


def list_profile_summaries() -> list[dict[str, Any]]:
    bootstrap_profiles()
    summaries: list[dict[str, Any]] = []
    for profile in load_all_profiles():
        linked_chart_id = str(profile["chart_id"])
        linked_chart_path = chart_path(linked_chart_id)
        if not linked_chart_path.exists():
            continue
        summaries.append(profile_summary(profile, load_json(linked_chart_path)))
    return sorted(summaries, key=lambda item: str(item["updated_at"]), reverse=True)


def create_profile(profile_name: str, username: str, chart_id: str, *, created_at: str | None = None, updated_at: str | None = None) -> dict[str, Any]:
    ensure_profiles_dir()
    normalized_username = ensure_username_available(username)
    timestamp = created_at or now_timestamp()
    payload = {
        "profile_id": f"profile_{uuid4().hex}",
        "profile_name": profile_name.strip(),
        "username": normalized_username,
        "chart_id": chart_id,
        "created_at": timestamp,
        "updated_at": updated_at or timestamp,
    }
    write_json(profile_path(payload["profile_id"]), payload)
    return payload


def update_profile(profile_id: str, profile_name: str, username: str, chart_id: str) -> dict[str, Any]:
    path, existing = load_profile(profile_id)
    normalized_username = ensure_username_available(username, exclude_profile_id=profile_id)
    updated = {
        **existing,
        "profile_name": profile_name.strip(),
        "username": normalized_username,
        "chart_id": chart_id,
        "updated_at": now_timestamp(),
    }
    write_json(path, updated)
    return updated


def resolve_profile_chart_id(profile_id: str) -> str:
    _, profile = load_profile(profile_id)
    return str(profile["chart_id"])
