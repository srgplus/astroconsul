#!/usr/bin/env python3
"""Render HTML files to PNG and upload to Supabase Storage.

This script does NOT generate HTML — Claude generates HTML using the
big3me-content-design skill. This script only:
1. Takes a directory of HTML files
2. Screenshots each to PNG via Playwright
3. Uploads PNGs to Supabase Storage
4. Updates the news post with image URLs

Usage:
  # Step 1: Claude generates HTML files in tmp/post-images/
  # Step 2: Run this script
  python scripts/render_and_upload_images.py <slug> <html_dir>

Example:
  python scripts/render_and_upload_images.py weekly-cosmic-outlook-march-23-29-2026 tmp/post-images/

HTML file naming convention:
  cover.html              → hero_image_url + og_image_url
  section_0_*.html        → sections[0].image_url
  section_1_*.html        → sections[1].image_url
  section_2_*.html        → sections[2].image_url
  ...

Requires: playwright, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
"""

import json
import os
import subprocess
import sys
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


# ── Supabase helpers ──

def get_supabase_creds():
    # Load .env.local
    env_file = Path(__file__).resolve().parents[1] / ".env.local"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())

    for alt in ("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_KEY"):
        if os.environ.get(alt):
            os.environ.setdefault("SUPABASE_KEY", os.environ[alt])
            break
    for alt in ("ASTRO_CONSUL_SUPABASE_URL",):
        if os.environ.get(alt):
            os.environ.setdefault("SUPABASE_URL", os.environ[alt])
            break

    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_KEY", "")
    if not url or not key:
        print("ERROR: Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY")
        sys.exit(1)
    return url, key


def supabase_get(path):
    url, key = get_supabase_creds()
    req = Request(
        f"{url}/rest/v1/{path}",
        headers={"apikey": key, "Authorization": f"Bearer {key}"},
    )
    with urlopen(req) as resp:
        return json.loads(resp.read())


def supabase_update(path, data):
    url, key = get_supabase_creds()
    req = Request(
        f"{url}/rest/v1/{path}",
        data=json.dumps(data, ensure_ascii=False, default=str).encode(),
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
        method="PATCH",
    )
    with urlopen(req) as resp:
        return json.loads(resp.read())


def upload_to_storage(file_path: Path, storage_path: str) -> str:
    url, key = get_supabase_creds()
    bucket = "news-images"

    with open(file_path, "rb") as f:
        data = f.read()

    req = Request(
        f"{url}/storage/v1/object/{bucket}/{storage_path}",
        data=data,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "image/png",
            "x-upsert": "true",
        },
        method="POST",
    )
    try:
        with urlopen(req) as resp:
            resp.read()
    except HTTPError as e:
        body = e.read().decode()
        if "Bucket not found" in body:
            print(f"  Creating storage bucket '{bucket}'...")
            _create_bucket(bucket)
            req = Request(
                f"{url}/storage/v1/object/{bucket}/{storage_path}",
                data=data,
                headers={
                    "apikey": key,
                    "Authorization": f"Bearer {key}",
                    "Content-Type": "image/png",
                    "x-upsert": "true",
                },
                method="POST",
            )
            with urlopen(req) as resp:
                resp.read()
        else:
            print(f"  Upload error: {e.code} {body}")
            raise

    return f"{url}/storage/v1/object/public/{bucket}/{storage_path}"


def _create_bucket(name: str):
    url, key = get_supabase_creds()
    req = Request(
        f"{url}/storage/v1/bucket",
        data=json.dumps({"id": name, "name": name, "public": True}).encode(),
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urlopen(req) as resp:
        resp.read()


# ── Playwright rendering ──

def html_to_png(html_path: Path, png_path: Path, width: int = 1080, height: int = 1350):
    """Screenshot an HTML file to PNG using Playwright."""
    subprocess.run(
        [
            "playwright", "screenshot",
            "--viewport-size", f"{width},{height}",
            f"file://{html_path.resolve()}",
            str(png_path),
        ],
        check=True,
        capture_output=True,
    )


# ── Main ──

def main():
    if len(sys.argv) < 3:
        print("Usage: python scripts/render_and_upload_images.py <slug> <html_dir>")
        print("")
        print("  slug      - Post slug (e.g. weekly-cosmic-outlook-march-23-29-2026)")
        print("  html_dir  - Directory containing HTML files generated by Claude")
        print("")
        print("HTML naming: cover.html, section_0_*.html, section_1_*.html, ...")
        sys.exit(1)

    slug = sys.argv[1]
    html_dir = Path(sys.argv[2])

    if not html_dir.exists():
        print(f"ERROR: Directory not found: {html_dir}")
        sys.exit(1)

    # Find all HTML files
    html_files = sorted(html_dir.glob("*.html"))
    if not html_files:
        print(f"ERROR: No HTML files in {html_dir}")
        sys.exit(1)

    print(f"Post: {slug}")
    print(f"HTML dir: {html_dir}")
    print(f"Found {len(html_files)} HTML files\n")

    # Render HTML → PNG
    png_files = {}
    for html_file in html_files:
        png_path = html_file.with_suffix(".png")
        print(f"  Rendering {html_file.name} → {png_path.name}...")
        html_to_png(html_file, png_path)
        png_files[html_file.stem] = png_path

    print(f"\nRendered {len(png_files)} images\n")

    # Upload to Supabase Storage
    print("Uploading to Supabase Storage...")
    cover_url = None
    section_urls = {}  # section index → url

    for name, png_path in png_files.items():
        storage_path = f"{slug}/{png_path.name}"
        url = upload_to_storage(png_path, storage_path)
        print(f"  {name}: {url}")

        if name == "cover":
            cover_url = url
        elif name.startswith("section_"):
            # Extract section index: "section_0_something" → 0
            parts = name.split("_")
            if len(parts) >= 2 and parts[1].isdigit():
                section_urls[int(parts[1])] = (url, name)

    # Update post in Supabase
    print("\nUpdating post...")

    # Fetch current post to get sections
    posts = supabase_get(f"news_posts?slug=eq.{slug}&limit=1")
    if not posts:
        print(f"WARNING: Post not found in Supabase: {slug}")
        print("Images uploaded but post not updated. URLs above can be used manually.")
        return

    post = posts[0]
    sections = post.get("sections") or []

    # Add image URLs to sections
    for idx, (url, name) in section_urls.items():
        if idx < len(sections):
            sections[idx]["image_url"] = url
            sections[idx]["image_alt"] = sections[idx].get("heading", f"Section {idx}")

    update_data = {"sections": sections}
    if cover_url:
        update_data["hero_image_url"] = cover_url
        update_data["og_image_url"] = cover_url

    supabase_update(f"news_posts?slug=eq.{slug}", update_data)

    print(f"\nDone!")
    if cover_url:
        print(f"  Cover: {cover_url}")
    print(f"  Section images: {len(section_urls)}")
    print(f"  View: https://big3.me/news/{slug}")


if __name__ == "__main__":
    main()
