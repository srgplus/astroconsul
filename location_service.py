from __future__ import annotations

import json
from functools import lru_cache
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

try:
    from timezonefinder import TimezoneFinder
except ImportError:  # pragma: no cover - covered through runtime dependency installation
    TimezoneFinder = None

NOMINATIM_SEARCH_URL = "https://nominatim.openstreetmap.org/search"
NOMINATIM_USER_AGENT = "AstroConsul/1.0 (local prototype)"
LOCATION_SOURCE = "OpenStreetMap Nominatim + timezonefinder"

_TIMEZONE_FINDER = TimezoneFinder() if TimezoneFinder is not None else None


class LocationResolutionError(ValueError):
    """Raised when the prototype cannot resolve a place name into chart-ready metadata."""


def normalize_location_query(value: str) -> str:
    return " ".join((value or "").split())


def geocode_place_name(location_name: str, *, timeout: float = 8.0) -> dict[str, Any] | None:
    query = normalize_location_query(location_name)
    params = urlencode({"q": query, "format": "jsonv2", "limit": 1, "accept-language": "en"})
    request = Request(
        f"{NOMINATIM_SEARCH_URL}?{params}",
        headers={
            "User-Agent": NOMINATIM_USER_AGENT,
            "Accept": "application/json",
        },
    )

    try:
        with urlopen(request, timeout=timeout) as response:
            payload = json.load(response)
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise LocationResolutionError(
            "Location lookup is temporarily unavailable. Please try again or enter coordinates manually."
        ) from exc

    if not payload:
        return None

    best_match = payload[0]
    return {
        "resolved_name": best_match.get("display_name") or query,
        "latitude": float(best_match["lat"]),
        "longitude": float(best_match["lon"]),
        "source": "OpenStreetMap Nominatim",
    }


def lookup_timezone_name(latitude: float, longitude: float) -> str | None:
    if _TIMEZONE_FINDER is None:
        raise LocationResolutionError(
            "Timezone lookup is not available. Install timezonefinder or enter timezone manually."
        )

    timezone_name = _TIMEZONE_FINDER.timezone_at(lat=latitude, lng=longitude)
    return timezone_name or None


@lru_cache(maxsize=128)
def resolve_location_name(location_name: str) -> dict[str, Any]:
    query = normalize_location_query(location_name)
    if not query:
        raise LocationResolutionError("location_name is required.")

    geocoded = geocode_place_name(query)
    if not geocoded:
        raise LocationResolutionError(
            "Could not resolve this location. Please check spelling or enter coordinates manually."
        )

    latitude = float(geocoded["latitude"])
    longitude = float(geocoded["longitude"])
    timezone_name = lookup_timezone_name(latitude, longitude)
    if not timezone_name:
        raise LocationResolutionError(
            "Location resolved, but timezone lookup failed. Please enter timezone manually."
        )

    return {
        "location_name": query,
        "resolved_name": geocoded["resolved_name"],
        "latitude": latitude,
        "longitude": longitude,
        "timezone": timezone_name,
        "source": LOCATION_SOURCE,
    }
