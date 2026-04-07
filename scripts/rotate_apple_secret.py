#!/usr/bin/env python3
"""
Rotate Apple Sign in with Apple client secret in Supabase.

Apple requires the JWT secret to expire within 6 months.
This script generates a new one and updates Supabase via Management API.

Run manually or via cron every 5 months:
  python3 scripts/rotate_apple_secret.py

Requires env vars:
  APPLE_TEAM_ID        - Apple Developer Team ID
  APPLE_CLIENT_ID      - Services ID (e.g. me.big3.auth)
  APPLE_KEY_ID         - Key ID from Apple Developer Console
  APPLE_PRIVATE_KEY    - Contents of .p8 file (with newlines)
  SUPABASE_PROJECT_REF - Supabase project ref (e.g. penhmylyqxzxvjxrbxen)
  SUPABASE_ACCESS_TOKEN - Supabase personal access token (from dashboard)
"""

import os
import sys
import time
import json
import urllib.request
import jwt


def generate_apple_secret(team_id: str, client_id: str, key_id: str, private_key: str) -> str:
    now = int(time.time())
    payload = {
        "iss": team_id,
        "iat": now,
        "exp": now + (86400 * 180),  # 180 days
        "aud": "https://appleid.apple.com",
        "sub": client_id,
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})


def update_supabase_apple_secret(project_ref: str, access_token: str, client_id: str, secret: str):
    url = f"https://api.supabase.com/v1/projects/{project_ref}/config/auth"
    data = json.dumps({
        "EXTERNAL_APPLE_ENABLED": True,
        "EXTERNAL_APPLE_CLIENT_ID": client_id,
        "EXTERNAL_APPLE_SECRET": secret,
    }).encode()

    req = urllib.request.Request(url, data=data, method="PATCH", headers={
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req) as resp:
        if resp.status == 200:
            print("Supabase Apple secret updated successfully.")
        else:
            print(f"Supabase API returned status {resp.status}")
            sys.exit(1)


def main():
    team_id = os.environ.get("APPLE_TEAM_ID", "85679N47YT")
    client_id = os.environ.get("APPLE_CLIENT_ID", "me.big3.auth")
    key_id = os.environ.get("APPLE_KEY_ID", "T722Z7TX6W")

    private_key = os.environ.get("APPLE_PRIVATE_KEY")
    if not private_key:
        # Try reading from file
        p8_path = os.path.join(os.path.dirname(__file__), "..", "AuthKey_T722Z7TX6W.p8")
        if os.path.exists(p8_path):
            with open(p8_path) as f:
                private_key = f.read()
        else:
            print("Error: Set APPLE_PRIVATE_KEY env var or place .p8 file in project root")
            sys.exit(1)

    project_ref = os.environ.get("SUPABASE_PROJECT_REF", "penhmylyqxzxvjxrbxen")
    access_token = os.environ.get("SUPABASE_ACCESS_TOKEN")

    secret = generate_apple_secret(team_id, client_id, key_id, private_key)
    print(f"Generated new Apple client secret (expires in 180 days)")

    if access_token:
        update_supabase_apple_secret(project_ref, access_token, client_id, secret)
    else:
        print("\nNo SUPABASE_ACCESS_TOKEN set. Paste this secret manually in Supabase Dashboard:")
        print(f"\n{secret}\n")


if __name__ == "__main__":
    main()
