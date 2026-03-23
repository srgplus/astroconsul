#!/usr/bin/env python3
"""Generate blog post images (cover + section images) and upload to Supabase Storage.

Usage:
  python scripts/generate_post_images.py <slug>

Generates:
  1. Cover image (1200x630 Blog Hero format)
  2. Section images for key transit aspects

Uploads to Supabase Storage bucket "news-images" and updates the post
with image URLs.

Requires: playwright, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
"""

import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


# ── Supabase helpers ──

def get_supabase_creds():
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
        print("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY")
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
    """Upload file to Supabase Storage and return public URL."""
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
            # Retry upload
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

    public_url = f"{url}/storage/v1/object/public/{bucket}/{storage_path}"
    return public_url


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


# ── HTML generation ──

COVER_HTML_TEMPLATE = """<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif&family=DM+Sans:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{
  width: 1200px; height: 630px;
  background: #0a0a0b;
  color: #e8e8ec;
  font-family: 'DM Sans', system-ui, sans-serif;
  display: flex; flex-direction: column;
  justify-content: center; align-items: center;
  text-align: center;
  position: relative; overflow: hidden;
}}
.glow-1 {{
  position: absolute; top: -80px; right: -80px;
  width: 350px; height: 350px; border-radius: 50%;
  background: radial-gradient(circle, rgba(167,139,250,0.1) 0%, transparent 65%);
}}
.glow-2 {{
  position: absolute; bottom: -80px; left: -80px;
  width: 300px; height: 300px; border-radius: 50%;
  background: radial-gradient(circle, rgba(244,114,182,0.08) 0%, transparent 65%);
}}
.logo {{
  position: absolute; top: 24px; left: 28px;
  font-size: 15px; font-weight: 600; color: #8e8e96;
}}
.logo .three {{ color: #a78bfa; }}
.tag {{
  position: absolute; top: 26px; right: 28px;
  font-size: 10px; font-weight: 600; letter-spacing: 2px;
  color: #a78bfa; text-transform: uppercase;
}}
.date {{
  font-size: 13px; color: #8e8e96; margin-bottom: 16px;
}}
.title {{
  font-family: 'Instrument Serif', Georgia, serif;
  font-size: 38px; font-weight: 400; line-height: 1.2;
  max-width: 900px; padding: 0 40px; margin-bottom: 12px;
}}
.subtitle {{
  font-size: 15px; color: #8e8e96; max-width: 700px;
  line-height: 1.5; padding: 0 40px;
}}
.footer {{
  position: absolute; bottom: 24px;
  font-size: 10px; color: rgba(255,255,255,0.3);
  letter-spacing: 3px; text-transform: uppercase;
}}
.ring {{
  position: absolute; border-radius: 50%;
  border: 1px solid rgba(255,255,255,0.03);
}}
.ring-1 {{ width: 500px; height: 500px; top: 50%; left: 50%; transform: translate(-50%,-50%); }}
.ring-2 {{ width: 350px; height: 350px; top: 50%; left: 50%; transform: translate(-50%,-50%); }}
</style>
</head><body>
<div class="glow-1"></div>
<div class="glow-2"></div>
<div class="ring ring-1"></div>
<div class="ring ring-2"></div>
<div class="logo">big<span class="three">3</span>.me</div>
<div class="tag">{tag}</div>
<div class="date">{date}</div>
<div class="title">{title}</div>
<div class="subtitle">{subtitle}</div>
<div class="footer">transit astrology</div>
</body></html>"""


SECTION_HTML_TEMPLATE = """<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif&family=DM+Sans:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{
  width: 1200px; height: 630px;
  background: {bg};
  color: {text};
  font-family: 'DM Sans', system-ui, sans-serif;
  display: flex; flex-direction: column;
  justify-content: center;
  padding: 48px 64px;
  position: relative; overflow: hidden;
}}
.glow {{
  position: absolute; top: -60px; right: -60px;
  width: 300px; height: 300px; border-radius: 50%;
  background: radial-gradient(circle, {glow} 0%, transparent 65%);
}}
.logo {{
  position: absolute; top: 24px; left: 28px;
  font-size: 13px; font-weight: 600; color: {muted};
}}
.logo .three {{ color: {accent}; }}
.badge {{
  display: inline-block;
  background: {badge_bg};
  color: {badge_color};
  padding: 4px 14px; border-radius: 20px;
  font-size: 11px; font-weight: 600;
  margin-bottom: 16px;
}}
.heading {{
  font-family: 'Instrument Serif', Georgia, serif;
  font-size: 32px; font-weight: 400; line-height: 1.2;
  margin-bottom: 20px;
}}
.body-text {{
  font-size: 15px; line-height: 1.7;
  color: {muted}; max-width: 800px;
}}
.footer {{
  position: absolute; bottom: 24px; left: 28px;
  font-size: 11px; color: {muted}; opacity: 0.5;
}}
</style>
</head><body>
<div class="glow"></div>
<div class="logo">big<span class="three">3</span>.me</div>
<div class="badge">{badge_text}</div>
<div class="heading">{heading}</div>
<div class="body-text">{body_text}</div>
<div class="footer">{footer}</div>
</body></html>"""


# Theme configs
DARK = {
    "bg": "#0a0a0b", "text": "#e8e8ec", "muted": "#8e8e96",
    "accent": "#a78bfa", "glow": "rgba(167,139,250,0.08)",
}
LIGHT = {
    "bg": "#faf9f7", "text": "#1a1a1f", "muted": "#6e6e76",
    "accent": "#7c3aed", "glow": "rgba(167,139,250,0.04)",
}

STRENGTH_STYLES = {
    "EXACT": {"badge_bg": "rgba(52,211,153,0.12)", "badge_color": "#34d399"},
    "STRONG": {"badge_bg": "rgba(251,146,60,0.12)", "badge_color": "#fb923c"},
    "APPLYING": {"badge_bg": "rgba(96,165,250,0.12)", "badge_color": "#60a5fa"},
    "default": {"badge_bg": "rgba(167,139,250,0.12)", "badge_color": "#a78bfa"},
}


def html_to_png(html: str, output_path: Path, width: int = 1200, height: int = 630):
    """Render HTML to PNG using Playwright."""
    with tempfile.NamedTemporaryFile(suffix=".html", mode="w", delete=False) as f:
        f.write(html)
        html_path = f.name

    try:
        subprocess.run(
            [
                "playwright", "screenshot",
                "--viewport-size", f"{width},{height}",
                f"file://{html_path}",
                str(output_path),
            ],
            check=True,
            capture_output=True,
        )
    finally:
        os.unlink(html_path)


def generate_cover(post: dict, output_dir: Path) -> Path:
    """Generate cover image for a post."""
    tags = post.get("tags", "")
    first_tag = tags.split(",")[0].strip() if tags else "transit"

    html = COVER_HTML_TEMPLATE.format(
        title=post["title"],
        subtitle=post.get("subtitle", ""),
        date=post["date"],
        tag=first_tag,
    )
    output = output_dir / "cover.png"
    html_to_png(html, output, 1200, 630)
    return output


def generate_section_image(
    heading: str,
    body_text: str,
    badge_text: str = "",
    theme: str = "dark",
    index: int = 0,
    output_dir: Path = Path("."),
    footer: str = "",
) -> Path:
    """Generate a section image."""
    t = DARK if theme == "dark" else LIGHT
    s = STRENGTH_STYLES.get(badge_text.split()[0] if badge_text else "", STRENGTH_STYLES["default"])

    # Truncate body text to ~250 chars for image
    if len(body_text) > 280:
        body_text = body_text[:277] + "..."

    html = SECTION_HTML_TEMPLATE.format(
        heading=heading,
        body_text=body_text,
        badge_text=badge_text or "transit",
        footer=footer,
        **t,
        **s,
    )
    output = output_dir / f"section_{index}.png"
    html_to_png(html, output, 1200, 630)
    return output


def main():
    if len(sys.argv) < 2:
        print("Usage: python scripts/generate_post_images.py <slug>")
        sys.exit(1)

    slug = sys.argv[1]

    # Fetch post from Supabase
    print(f"Fetching post: {slug}")
    posts = supabase_get(f"news_posts?slug=eq.{slug}&limit=1")
    if not posts:
        print(f"Post not found: {slug}")
        sys.exit(1)

    post = posts[0]
    sections = post.get("sections") or []

    # Create temp output directory
    output_dir = Path(tempfile.mkdtemp(prefix="big3me_images_"))
    print(f"Output dir: {output_dir}")

    # 1. Generate cover image
    print("Generating cover image...")
    cover_path = generate_cover(post, output_dir)
    print(f"  Created: {cover_path}")

    # 2. Generate section images (for sections with body text, skip HTML-heavy ones)
    section_images = []
    themes = ["light", "dark"]  # alternate themes
    for i, section in enumerate(sections):
        body = section.get("body", "")
        if not body:
            # Extract text from body_html (strip tags roughly)
            body_html = section.get("body_html", "")
            if not body_html or "<div class=\"prompt-block\">" in body_html:
                continue  # Skip code-block sections
            import re
            body = re.sub(r"<[^>]+>", " ", body_html).strip()
            body = re.sub(r"\s+", " ", body)

        if len(body) < 50:
            continue  # Too short for an image

        heading = section.get("heading", "")
        theme = themes[i % 2]

        print(f"  Generating image for: {heading[:50]}...")
        img_path = generate_section_image(
            heading=heading,
            body_text=body,
            badge_text=post.get("tags", "").split(",")[0].strip(),
            theme=theme,
            index=i,
            output_dir=output_dir,
            footer=f"big3.me/news/{slug}",
        )
        section_images.append((i, img_path, heading))

    # 3. Upload to Supabase Storage
    print("\nUploading to Supabase Storage...")
    date_str = post["date"] if isinstance(post["date"], str) else post["date"].isoformat()

    # Upload cover
    cover_url = upload_to_storage(cover_path, f"{slug}/cover.png")
    print(f"  Cover: {cover_url}")

    # Upload section images
    updated_sections = list(sections)  # copy
    for section_idx, img_path, heading in section_images:
        storage_path = f"{slug}/section_{section_idx}.png"
        img_url = upload_to_storage(img_path, storage_path)
        print(f"  Section {section_idx}: {img_url}")

        # Add image_url to section
        if section_idx < len(updated_sections):
            updated_sections[section_idx]["image_url"] = img_url
            updated_sections[section_idx]["image_alt"] = heading

    # 4. Update post in Supabase
    print("\nUpdating post with image URLs...")
    supabase_update(
        f"news_posts?slug=eq.{slug}",
        {
            "hero_image_url": cover_url,
            "og_image_url": cover_url,
            "sections": updated_sections,
        },
    )

    print(f"\nDone! Post updated with images.")
    print(f"  Cover: {cover_url}")
    print(f"  Section images: {len(section_images)}")
    print(f"  View: https://big3.me/news/{slug}")

    # Cleanup
    import shutil
    shutil.rmtree(output_dir)


if __name__ == "__main__":
    main()
