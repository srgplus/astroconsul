from __future__ import annotations

from typing import Any, Callable


class LocationLookupService:
    def __init__(self, cache_repository: object | None = None):
        self.cache_repository = cache_repository

    def resolve(
        self,
        location_name: str,
        *,
        resolver: Callable[[str], dict[str, Any]],
    ) -> dict[str, Any]:
        normalized_query = " ".join((location_name or "").split())
        if not normalized_query:
            raise ValueError("location_name is required.")

        if self.cache_repository is not None:
            cached = self.cache_repository.get(normalized_query)
            if cached is not None:
                return cached

        resolved = resolver(normalized_query)
        if self.cache_repository is not None:
            self.cache_repository.put(normalized_query, resolved)
        return resolved

