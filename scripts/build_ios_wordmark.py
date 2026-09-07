#!/usr/bin/env python3
"""Outline the big3.me wordmark into the iOS asset catalogue.

The mark is type, not a drawing: "big" light, "3" bold, ".me" small and muted,
set in Space Grotesk — the same lockup B3Wordmark.swift draws in SwiftUI and
B3Logo.tsx draws on the web. SwiftUI can set it live, but the launch screen is
a storyboard that runs before any code, so there it has to be an image.

Xcode's asset catalogue renders SVG paths and ignores SVG <text>, so the faces
are converted to outlines here rather than shipped as a font dependency. One
variant per appearance, because a launch screen has no way to tint.

    python3 scripts/build_ios_wordmark.py

Requires fontTools (pip install fonttools).
"""

from pathlib import Path

from fontTools.misc.transform import Transform
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "frontend/ios/App/App/Native/Design/Fonts"
IMAGESET = ROOT / "frontend/ios/App/App/Assets.xcassets/B3Logo.imageset"

UPEM = 1000.0
EM = 100.0  # SVG units per em, so two decimals stay well under a hairline

# Proportions mirror B3Wordmark.swift.
ME_SCALE = 0.65  # ".me" against the rest
TRACKING = -1.8  # .tracking(-0.8), as a share of the em
ME_LEAD = 2.0  # .padding(.leading, 1)

# Framed on the cap height rather than the full em box, so the mark sits
# optically centred wherever it is dropped.
TOP, BOTTOM = -75.0, 21.0

RUNS = [
    ("SpaceGrotesk-Light.ttf", "big", 1.0, "ink"),
    ("SpaceGrotesk-Bold.ttf", "3", 1.0, "ink"),
    ("SpaceGrotesk-Regular.ttf", ".me", ME_SCALE, "dim"),
]

# Theme.text / Theme.textDim, per appearance.
VARIANTS = {
    "light": {"ink": "#1A1A1A", "dim": "#6B7280"},
    "dark": {"ink": "#F5F5F7", "dim": "#98989D"},
}

CONTENTS = """{
  "images" : [
    {
      "filename" : "b3-wordmark-light.svg",
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "b3-wordmark-dark.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "original"
  }
}
"""


def outline(font_file: str, text: str, scale: float, pen_x: float) -> tuple[str, float]:
    """Return the run's path data and its advance, laid out from `pen_x`."""
    font = TTFont(FONTS / font_file)
    cmap = font.getBestCmap()
    glyphs = font.getGlyphSet()
    widths = font["hmtx"]
    unit = scale * EM / UPEM

    data: list[str] = []
    x = pen_x
    for character in text:
        name = cmap[ord(character)]
        pen = SVGPathPen(glyphs, ntos=lambda value: f"{value:.2f}")
        # Flip Y: font units climb from the baseline, SVG units fall from the top.
        glyphs[name].draw(TransformPen(pen, Transform(unit, 0, 0, -unit, x, 0)))
        if commands := pen.getCommands():
            data.append(commands)
        x += widths[name][0] * unit + TRACKING

    return " ".join(data), x - pen_x


def build(variant: str) -> str:
    palette = VARIANTS[variant]
    paths: list[tuple[str, str]] = []
    x = 0.0

    for font_file, text, scale, role in RUNS:
        if role == "dim":
            x += ME_LEAD
        data, advance = outline(font_file, text, scale, x)
        paths.append((data, palette[role]))
        x += advance

    width = x - TRACKING  # the last character tracks into nothing
    height = BOTTOM - TOP
    body = "\n".join(f'  <path d="{data}" fill="{fill}"/>' for data, fill in paths)

    return (
        '<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 {TOP:.2f} {width:.2f} {height:.2f}" '
        f'width="{width:.2f}" height="{height:.2f}">\n'
        f"{body}\n"
        "</svg>\n"
    )


def main() -> None:
    IMAGESET.mkdir(parents=True, exist_ok=True)
    for variant in VARIANTS:
        target = IMAGESET / f"b3-wordmark-{variant}.svg"
        target.write_text(build(variant))
        print(f"wrote {target.relative_to(ROOT)}")

    (IMAGESET / "Contents.json").write_text(CONTENTS)
    print(f"wrote {(IMAGESET / 'Contents.json').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
