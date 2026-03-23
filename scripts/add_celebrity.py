#!/usr/bin/env python3
"""Add a celebrity profile to big3.me via Supabase REST API.

Computes the natal chart using Swiss Ephemeris, then inserts into
natal_charts + profiles tables. Links to hi@srgplus.com user.

Usage:
  python scripts/add_celebrity.py scripts/celebrities/zendaya.py

Celebrity definition file should export a CELEBRITY dict:
  CELEBRITY = {
      "name": "Zendaya",
      "birth_date": "1996-09-01",
      "birth_time": "18:55",
      "timezone": "America/Los_Angeles",
      "location_name": "Oakland, CA",
      "latitude": 37.8044,
      "longitude": -122.2712,
      "rodden_rating": "AA",        # AA or A only
      "astro_databank_url": "https://www.astro.com/astro-databank/Zendaya",
  }

Requires env vars: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
"""

import hashlib
import json
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

# Add project root to path for imports
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def load_env_file():
    """Load .env.local from project root if it exists."""
    env_file = Path(__file__).resolve().parents[1] / ".env.local"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())


def get_supabase_creds():
    """Resolve Supabase URL and key from env vars."""
    load_env_file()

    url = os.environ.get("SUPABASE_URL") or os.environ.get("ASTRO_CONSUL_SUPABASE_URL")
    key = (
        os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        or os.environ.get("SUPABASE_KEY")
        or os.environ.get("ASTRO_CONSUL_SUPABASE_SERVICE_ROLE_KEY")
    )

    if not url or not key:
        print("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY env vars")
        sys.exit(1)

    return url, key


def supabase_request(method, path, data=None, *, url=None, key=None):
    """Make a Supabase REST API request."""
    if url is None or key is None:
        url, key = get_supabase_creds()

    req_url = f"{url}/rest/v1/{path}"
    body = json.dumps(data, ensure_ascii=False, default=str).encode("utf-8") if data else None

    req = Request(
        req_url,
        data=body,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
        method=method,
    )
    try:
        with urlopen(req) as resp:
            return json.loads(resp.read())
    except HTTPError as e:
        body = e.read().decode()
        print(f"ERROR {e.code}: {body}")
        return None


def find_admin_user(url, key):
    """Find the hi@srgplus.com user ID."""
    result = supabase_request(
        "GET",
        "users?select=id&email=eq.hi@srgplus.com&limit=1",
        url=url, key=key,
    )
    if result and len(result) > 0:
        return result[0]["id"]
    print("WARNING: hi@srgplus.com user not found. Using 'admin' as user_id.")
    return "admin"


def compute_chart(celebrity):
    """Compute natal chart using Swiss Ephemeris."""
    from chart_builder import build_chart
    from astro_utils import time_str_to_decimal_hours

    birth_date = celebrity["birth_date"]  # "1996-09-01"
    birth_time = celebrity["birth_time"]  # "18:55"

    # Parse date
    parts = birth_date.split("-")
    year, month, day = int(parts[0]), int(parts[1]), int(parts[2])

    # Parse time to decimal hours
    time_parts = birth_time.split(":")
    hour = int(time_parts[0]) + int(time_parts[1]) / 60.0

    # Convert local time to UTC if timezone provided
    tz_name = celebrity.get("timezone", "UTC")
    if tz_name != "UTC":
        try:
            from zoneinfo import ZoneInfo
        except ImportError:
            from backports.zoneinfo import ZoneInfo
        from datetime import datetime as dt

        local_dt = dt(year, month, day, int(time_parts[0]), int(time_parts[1]),
                      tzinfo=ZoneInfo(tz_name))
        utc_dt = local_dt.astimezone(ZoneInfo("UTC"))
        year = utc_dt.year
        month = utc_dt.month
        day = utc_dt.day
        hour = utc_dt.hour + utc_dt.minute / 60.0
        utc_str = utc_dt.isoformat()
        local_str = local_dt.isoformat()
    else:
        utc_str = f"{birth_date}T{birth_time}:00+00:00"
        local_str = utc_str

    chart = build_chart(
        year, month, day, hour,
        celebrity["latitude"],
        celebrity["longitude"],
        birth_input={
            "name": celebrity["name"],
            "birth_date": celebrity["birth_date"],
            "birth_time": celebrity["birth_time"],
            "timezone": tz_name,
            "location_name": celebrity.get("location_name", ""),
            "local_birth_datetime": local_str,
            "utc_birth_datetime": utc_str,
            "latitude": celebrity["latitude"],
            "longitude": celebrity["longitude"],
            "time_basis": "local",
        },
    )
    return chart, year, month, day, hour


def chart_hash(chart):
    """Compute SHA-256 hash of chart payload."""
    payload = json.dumps(chart, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def make_handle(name):
    """Create a URL-safe handle from celebrity name."""
    return name.lower().replace(" ", "-").replace(".", "").replace("'", "")


def add_celebrity(celebrity):
    """Add celebrity profile to Supabase."""
    url, key = get_supabase_creds()
    now = datetime.now(timezone.utc).isoformat()

    # Validate Rodden rating
    rating = celebrity.get("rodden_rating", "")
    if rating not in ("AA", "A"):
        print(f"ERROR: Rodden rating '{rating}' not acceptable. Only AA or A allowed.")
        sys.exit(1)

    handle = make_handle(celebrity["name"])

    # Check if profile already exists
    existing = supabase_request(
        "GET",
        f"profiles?select=id,display_name&handle=eq.{handle}&limit=1",
        url=url, key=key,
    )
    if existing and len(existing) > 0:
        print(f"  SKIP (exists): {celebrity['name']} — profile_id: {existing[0]['id']}")
        return existing[0]["id"]

    # Find admin user
    user_id = find_admin_user(url, key)

    # Compute natal chart
    print(f"  Computing natal chart for {celebrity['name']}...")
    chart, year, month, day, hour = compute_chart(celebrity)

    # Check if chart already exists by hash
    c_hash = chart_hash(chart)
    existing_chart = supabase_request(
        "GET",
        f"natal_charts?select=id&chart_hash=eq.{c_hash}&limit=1",
        url=url, key=key,
    )

    if existing_chart and len(existing_chart) > 0:
        chart_id = existing_chart[0]["id"]
        print(f"  Chart already exists: {chart_id}")
    else:
        # Insert chart
        import swisseph as swe
        chart_id = str(uuid.uuid4())
        jd = swe.julday(year, month, day, hour)

        chart_row = {
            "id": chart_id,
            "chart_hash": c_hash,
            "house_system": "Placidus",
            "julian_day": jd,
            "birth_input_json": chart.get("birth_input", {}),
            "chart_payload_json": chart,
            "created_at": now,
        }
        result = supabase_request("POST", "natal_charts", chart_row, url=url, key=key)
        if not result:
            print("  FAILED to insert chart")
            return None
        print(f"  Chart created: {chart_id}")

    # Insert profile
    profile_id = str(uuid.uuid4())
    profile_row = {
        "id": profile_id,
        "user_id": user_id,
        "handle": handle,
        "display_name": celebrity["name"],
        "birth_date": celebrity["birth_date"],
        "birth_time": celebrity["birth_time"],
        "timezone": celebrity.get("timezone", "UTC"),
        "location_name": celebrity.get("location_name", ""),
        "latitude": celebrity["latitude"],
        "longitude": celebrity["longitude"],
        "chart_id": chart_id,
        "is_featured": True,
        "created_at": now,
        "updated_at": now,
    }
    result = supabase_request("POST", "profiles", profile_row, url=url, key=key)
    if not result:
        print("  FAILED to insert profile")
        return None

    print(f"  Profile created: {celebrity['name']}")
    print(f"  Profile ID: {profile_id}")
    print(f"  Handle: {handle}")
    print(f"  View: https://big3.me/{handle}")
    print(f"  Transits API: https://big3.me/api/v1/profiles/{profile_id}/transits")
    return profile_id


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python scripts/add_celebrity.py <celebrity_file.py>")
        print("  See scripts/celebrities/example.py for template")
        sys.exit(1)

    celeb_file = sys.argv[1]
    import importlib.util
    spec = importlib.util.spec_from_file_location("celeb_module", celeb_file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    if not hasattr(module, "CELEBRITY"):
        print(f"ERROR: {celeb_file} must define a CELEBRITY dict")
        sys.exit(1)

    add_celebrity(module.CELEBRITY)
