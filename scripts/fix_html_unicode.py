#!/usr/bin/env python3
"""Fix Unicode escape sequences in HTML image card files.

Replaces literal \\uXXXX text (e.g. \\u2642) with actual Unicode characters.
This fixes files pushed via GitHub MCP where Unicode was double-escaped.

Usage: python scripts/fix_html_unicode.py tmp/post-images/
"""
import re
import sys
from pathlib import Path


def fix_unicode_escapes(text):
    """Replace literal \\uXXXX sequences with actual Unicode characters."""
    return re.sub(
        r'\\u([0-9a-fA-F]{4})',
        lambda m: chr(int(m.group(1), 16)),
        text
    )


if __name__ == "__main__":
    target_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("tmp/post-images")

    for html_file in sorted(target_dir.glob("*.html")):
        content = html_file.read_text()
        fixed = fix_unicode_escapes(content)
        if fixed != content:
            html_file.write_text(fixed)
            print(f"Fixed: {html_file.name}")
        else:
            print(f"OK: {html_file.name}")
