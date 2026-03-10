"""Entrypoint for the Swiss Ephemeris natal chart prototype."""

from __future__ import annotations

from pathlib import Path
import runpy


if __name__ == "__main__":
    script_path = Path(__file__).resolve().parent / "swiss-test" / "chart_test.py"
    runpy.run_path(str(script_path), run_name="__main__")
