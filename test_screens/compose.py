#!/usr/bin/env python3
"""Composes the website/README images from the renders in goldens/.

Run after `flutter test test_screens --update-goldens`:

    python3 test_screens/compose.py

Writes docs/screenshot-dark.png, docs/screenshot-light.png,
docs/social-preview.png and docs/icon.png. Needs rsvg-convert and the Noto Sans font.
"""
import base64
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GOLD = ROOT / "test_screens" / "goldens"
DOCS = ROOT / "docs"
ICON = ROOT / "assets" / "icon" / "app_icon.png"

SHOT_W, SHOT_H = 1440, 2140  # render width; height trimmed below "About"
BAR = 72  # title bar height at 2x

THEMES = {
    "dark": dict(page="#120c0b", glow="#b4531f", app="#1a1110",
                 bar="#2a201e", title="#f1dfda", line="#3a2e2b"),
    "light": dict(page="#f3e6e1", glow="#e8a07a", app="#fff8f6",
                  bar="#efe2dd", title="#3b2a25", line="#dccbc5"),
}


def uri(path: Path) -> str:
    # rsvg-convert only loads files next to the SVG, so embed them.
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode()


def window(t, shot, x, y, scale):
    """An app window with a title bar, drawn at (x, y)."""
    w, h = SHOT_W * scale, (SHOT_H + BAR) * scale
    r = 24 * scale
    return f"""
  <g transform="translate({x} {y})">
    <rect x="0" y="{24 * scale}" width="{w}" height="{h}" rx="{r}"
          fill="#000" opacity=".35" filter="url(#blur)"/>
    <clipPath id="win{x}"><rect width="{w}" height="{h}" rx="{r}"/></clipPath>
    <g clip-path="url(#win{x})">
      <rect width="{w}" height="{h}" fill="{t['app']}"/>
      <rect width="{w}" height="{BAR * scale}" fill="{t['bar']}"/>
      <text x="{w / 2}" y="{BAR * scale * .62}" text-anchor="middle"
            font-family="Noto Sans" font-weight="600"
            font-size="{26 * scale}" fill="{t['title']}">Pocket AMP Upgrader</text>
      <image href="{uri(shot)}" x="0" y="{BAR * scale}" width="{SHOT_W * scale}"
             height="{2200 * scale}" preserveAspectRatio="xMinYMin slice"/>
    </g>
    <rect width="{w}" height="{h}" rx="{r}" fill="none"
          stroke="{t['line']}" stroke-width="{2 * scale}"/>
  </g>"""


DEFS = """
  <defs>
    <filter id="blur" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="28"/>
    </filter>
    <radialGradient id="glow" cx="80%" cy="0%" r="90%">
      <stop offset="0" stop-color="{glow}" stop-opacity=".35"/>
      <stop offset="1" stop-color="{glow}" stop-opacity="0"/>
    </radialGradient>
  </defs>"""


def render(svg: str, out: Path, width: int):
    src = out.with_suffix(".svg")
    src.write_text(svg)
    try:
        subprocess.run(["rsvg-convert", "-w", str(width), "-o", str(out),
                        str(src)], check=True)
    finally:
        src.unlink()


def screenshot(name):
    t = THEMES[name]
    pad = 96
    W, H = SHOT_W + 2 * pad, SHOT_H + BAR + 2 * pad
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">
  {DEFS.format(**t)}
  <rect width="{W}" height="{H}" fill="{t['page']}"/>
  <rect width="{W}" height="{H}" fill="url(#glow)"/>
  {window(t, GOLD / f"ready-{name}.png", pad, pad, 1)}
</svg>"""
    render(svg, DOCS / f"screenshot-{name}.png", W)


def social():
    t = THEMES["dark"]
    W, H = 1280, 640
    s = 0.36
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">
  {DEFS.format(**t)}
  <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">
    <stop offset=".72" stop-color="{t['page']}" stop-opacity="0"/>
    <stop offset="1" stop-color="{t['page']}" stop-opacity="1"/>
  </linearGradient>
  <rect width="{W}" height="{H}" fill="{t['page']}"/>
  <rect width="{W}" height="{H}" fill="url(#glow)"/>
  {window(t, GOLD / "ready-dark.png", 724, 64, s)}
  <rect x="700" y="0" width="{W - 640}" height="{H}" fill="url(#fade)"/>
  <image href="{uri(ICON)}" x="64" y="88" width="88" height="88"/>
  <text font-family="Noto Sans" fill="#f1dfda">
    <tspan x="64" y="268" font-size="54" font-weight="700">Update your</tspan>
    <tspan x="64" y="336" font-size="54" font-weight="700">Pocket AMP firmware</tspan>
  </text>
  <text x="64" y="398" font-family="Noto Sans" font-size="27" fill="#d8c2bb">from macOS, Linux or Windows</text>
  <text x="64" y="440" font-family="Noto Sans" font-size="27" fill="#d8c2bb">and keep your 80 presets</text>
  <rect x="64" y="496" width="404" height="52" rx="26" fill="none" stroke="#ffb59a" stroke-width="2"/>
  <text x="266" y="530" text-anchor="middle" font-family="Noto Sans" font-weight="600" font-size="21" fill="#ffb59a">Free &amp; open source · GPL-3.0</text>
</svg>"""
    render(svg, DOCS / "social-preview.png", W)


if __name__ == "__main__":
    for n in ("dark", "light"):
        if not (GOLD / f"ready-{n}.png").exists():
            sys.exit(f"missing goldens/ready-{n}.png: render them first")
    screenshot("dark")
    screenshot("light")
    social()
    render(f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024">'
           f'<image href="{uri(ICON)}" width="1024" height="1024"/></svg>',
           DOCS / "icon.png", 180)
