from __future__ import annotations

from typing import Any

from natal_profiles import profile_summary

from app.application.services.chart_service import ChartService


class ProfileService:
    def __init__(self, chart_service: ChartService):
        self.chart_service = chart_service

    def list_profiles(self, profile_repository) -> dict[str, object]:
        return {"profiles": profile_repository.list_summaries()}

    def profile_detail(self, profile_id: str, *, profile_repository, chart_repository) -> dict[str, object]:
        profile = profile_repository.load_profile(profile_id)
        chart_reference, chart = chart_repository.load_chart(str(profile["chart_id"]))
        return {
            "profile": profile_summary(profile, chart),
            "chart": self.chart_service.build_saved_chart_response(str(profile["chart_id"]), chart_reference, chart),
        }

    def create_profile(
        self,
        payload,
        *,
        chart_id: str,
        chart_reference: str,
        chart: dict[str, Any],
        profile_repository,
    ) -> dict[str, object]:
        profile = profile_repository.create_profile(
            payload.profile_name,
            payload.username,
            chart_id,
            profile_input=payload.model_dump(),
        )
        return {
            "profile": profile_summary(profile, chart),
            "chart": self.chart_service.build_saved_chart_response(chart_id, chart_reference, chart),
        }

    def update_profile(
        self,
        profile_id: str,
        payload,
        *,
        previous_chart_id: str,
        chart_id: str,
        chart_reference: str,
        chart: dict[str, Any],
        profile_repository,
    ) -> dict[str, object]:
        profile = profile_repository.update_profile(
            profile_id,
            payload.profile_name,
            payload.username,
            chart_id,
            profile_input=payload.model_dump(),
        )
        if chart_id != previous_chart_id:
            profile_repository.delete_chart_if_unreferenced(previous_chart_id, exclude_profile_id=profile_id)
        return {
            "profile": profile_summary(profile, chart),
            "chart": self.chart_service.build_saved_chart_response(chart_id, chart_reference, chart),
        }

