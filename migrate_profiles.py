#!/usr/bin/env python3
"""Migrate local file-based profiles to production (Railway/Supabase) via API.

Usage:
    1. Get a valid auth token by logging in on the prod site, then from
       browser DevTools > Application > Local Storage > sb-*-auth-token,
       copy the access_token.
    2. Run:
       PROD_TOKEN="eyJ..." python3 migrate_profiles.py
"""

import json
import os
import sys
from pathlib import Path

import httpx

PROD_URL = os.environ.get("PROD_URL", "https://astroconsul-production.up.railway.app")
TOKEN = os.environ.get("PROD_TOKEN", "")

PROFILES_DIR = Path(__file__).parent / "profiles"
CHARTS_DIR = Path(__file__).parent / "charts"


def load_local_profiles():
    """Load all local profile + chart data."""
    profiles = []
    for pf in sorted(PROFILES_DIR.glob("profile_*.json")):
        profile = json.loads(pf.read_text())
        chart_id = profile["chart_id"]
        chart_path = CHARTS_DIR / f"{chart_id}.json"
        if not chart_path.exists():
            print(f"  SKIP {profile['profile_name']}: chart {chart_id} not found")
            continue
        chart = json.loads(chart_path.read_text())
        birth_input = chart.get("birth_input") or chart.get("birth_data") or {}
        profiles.append({
            "profile": profile,
            "chart": chart,
            "birth_input": birth_input,
        })
    return profiles


def create_profile_on_prod(client: httpx.Client, entry: dict) -> bool:
    """Create a single profile on prod via POST /api/v1/profiles."""
    profile = entry["profile"]
    bi = entry["birth_input"]

    payload = {
        "profile_name": profile["profile_name"],
        "username": profile["username"],
        "birth_date": bi.get("birth_date", ""),
        "birth_time": bi.get("birth_time", ""),
        "timezone": bi.get("timezone", ""),
        "location_name": bi.get("location_name", ""),
        "latitude": bi.get("latitude", 0),
        "longitude": bi.get("longitude", 0),
    }

    print(f"  Creating: {payload['profile_name']} (@{payload['username']})...", end=" ")

    resp = client.post(f"{PROD_URL}/api/v1/profiles", json=payload)
    if resp.status_code in (200, 201):
        print("OK")
        return True
    else:
        print(f"FAILED ({resp.status_code}): {resp.text[:200]}")
        return False


def main():
    if not TOKEN:
        print("ERROR: Set PROD_TOKEN env variable with a valid Supabase access_token")
        print("  Get it from browser DevTools on the prod site:")
        print("  Application > Local Storage > look for sb-*-auth-token > access_token")
        sys.exit(1)

    print(f"Target: {PROD_URL}")
    print(f"Loading local profiles from {PROFILES_DIR}...")

    entries = load_local_profiles()
    print(f"Found {len(entries)} profiles to migrate.\n")

    client = httpx.Client(
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
        },
        timeout=30,
    )

    ok = 0
    fail = 0
    for entry in entries:
        if create_profile_on_prod(client, entry):
            ok += 1
        else:
            fail += 1

    print(f"\nDone! {ok} created, {fail} failed.")


if __name__ == "__main__":
    main()
