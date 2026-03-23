#!/usr/bin/env python3
"""Upload all post images to big3.me via base64 API endpoint."""

import base64, json, sys
from pathlib import Path
from urllib.request import Request, urlopen

SLUG = "weekly-cosmic-outlook-march-23-29-2026"
API_URL = "https://big3.me/api/v1/images/upload-base64"
IMAGE_DIR = Path(__file__).parent / "post-images"

files = sorted(IMAGE_DIR.glob("*.png"))
if not files:
    print("No PNG files found in", IMAGE_DIR)
    sys.exit(1)

for fpath in files:
    print(f"Uploading {fpath.name}...", end=" ", flush=True)
    with open(fpath, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    req = Request(
        API_URL,
        data=json.dumps({"slug": SLUG, "filename": fpath.name, "data": b64}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        resp = json.loads(urlopen(req).read())
        print("✓", resp.get("url", resp))
    except Exception as e:
        print("✗", e)

print("\nDone!")
