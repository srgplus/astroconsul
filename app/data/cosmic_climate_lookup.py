"""Cosmic Climate descriptions lookup.

Loads cosmic_climate_descriptions.json once at import time.
Key format: ``"{transit_planet}_{aspect}_{natal_point}"`` (original case from JSON).

Supports two JSON formats:

1. **i18n** (preferred)::

    "Pluto_opposition_Sun": {
        "en": {"meaning": "...", "insight": "..."},
        "ru": {"meaning": "...", "insight": "..."}
    }

2. **Legacy flat** (auto-detected, treated as ``ru``)::

    "Pluto_opposition_Sun": {"meaning": "...", "insight": "..."}

Usage::

    from app.data.cosmic_climate_lookup import get_cosmic_description

    desc = get_cosmic_description("Pluto", "opposition", "Sun", lang="ru")
    # {"meaning": "...", "insight": "..."}
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

_DATA_PATH = Path(__file__).with_name("cosmic_climate_descriptions.json")

# key -> { "en": {"meaning": ..., "insight": ...}, "ru": {...} }
_LOOKUP: dict[str, dict[str, dict[str, Any]]] = {}


def _build_key(transit: str, aspect: str, natal: str) -> str:
    return f"{transit}_{aspect}_{natal}".lower()


def _is_i18n_record(rec: dict) -> bool:
    """Check if record has language sub-keys (en/ru) vs flat meaning/insight."""
    return any(isinstance(v, dict) for v in rec.values())


def _load() -> None:
    global _LOOKUP  # noqa: PLW0603
    _LOOKUP.clear()
    try:
        data = json.loads(_DATA_PATH.read_text(encoding="utf-8"))
        for composite_key, rec in data.items():
            key = composite_key.lower()
            if _is_i18n_record(rec):
                # i18n format: { "en": {...}, "ru": {...} }
                _LOOKUP[key] = {
                    lang_code: {
                        "meaning": lang_data.get("meaning", ""),
                        "insight": lang_data.get("insight"),
                    }
                    for lang_code, lang_data in rec.items()
                    if isinstance(lang_data, dict)
                }
            else:
                # Legacy flat format — treat as Russian
                _LOOKUP[key] = {
                    "ru": {
                        "meaning": rec.get("meaning", ""),
                        "insight": rec.get("insight"),
                    }
                }
        logger.info("Loaded %d cosmic climate descriptions", len(_LOOKUP))
    except Exception:
        logger.exception("Failed to load cosmic climate descriptions from %s", _DATA_PATH)


# Eager load on import
_load()


def get_cosmic_description(
    transit_planet: str,
    aspect_type: str,
    natal_point: str,
    lang: str = "ru",
) -> dict[str, Any] | None:
    """Return meaning/insight for a cosmic climate aspect, or None if not found.

    Tries requested ``lang`` first, then falls back to ``ru``, then ``en``.
    """
    key = _build_key(transit_planet, aspect_type, natal_point)
    entry = _LOOKUP.get(key)
    if not entry:
        return None
    # Try requested lang, then fallbacks
    for try_lang in (lang, "ru", "en"):
        if try_lang in entry:
            return entry[try_lang]
    return None
