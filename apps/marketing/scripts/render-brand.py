# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Render Airdraft's brand SVGs from the app icon's geometry and the app wordmark.

Writes, into apps/marketing/public/brand/ (served as-is, for use outside the
site; the site itself draws the logo with ui/Brand.astro):
  airdraft-mark.svg  the icon's raised capsule, pressed track, waveform and caret
  airdraft-logo.svg  the mark beside the app's outlined "airdraft" lettering

The capsule mirrors scripts/render-app-icon.swift: neutral grays only, raised
gray bars and a graphite caret, lit from the top left. Change both together.
The lettering is read from the app's wordmark asset
(Sources/App/Assets.xcassets/SidebarWordmark.imageset/wordmark.svg, outlined
SF Pro), so it is never re-typeset here.

Usage, from the repo root:  uv run apps/marketing/scripts/render-brand.py
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "apps/marketing/public/brand"
WORDMARK = ROOT / "Sources/App/Assets.xcassets/SidebarWordmark.imageset/wordmark.svg"
INK = "#262626"

# Icon geometry (render-app-icon.swift), in icon points.
PILL_W, PILL_H = 744, 364
TRACK_W, TRACK_H = 650, 270
LEVELS = [0.36, 0.66, 1.0, 0.72, 0.48]
BAR_W, BAR_GAP, BAR_H = 38, 30, 190
CARET_H, CARET_EXTRA = 208, 20
PAD_X, PAD_TOP, PAD_BOTTOM = 32, 24, 48   # room for the light and the shade


def gray(white: float) -> str:
    value = round(white * 255)
    return f"#{value:02X}{value:02X}{value:02X}"


def mark(prefix: str) -> tuple[str, str]:
    """Return (defs, body) for the mark, with the pill's origin at 0,0."""
    cx, cy = PILL_W / 2, PILL_H / 2
    tx, ty = (PILL_W - TRACK_W) / 2, (PILL_H - TRACK_H) / 2
    widths = len(LEVELS) * BAR_W + len(LEVELS) * BAR_GAP + CARET_EXTRA + BAR_W
    x = cx - widths / 2  # the icon's HStack spacing sits between every item
    bars = []
    for level in LEVELS:
        h = BAR_H * level
        bars.append(
            f'<rect x="{x:.1f}" y="{cy - h / 2:.1f}" width="{BAR_W}" height="{h:.1f}" '
            f'rx="{BAR_W / 2}" fill="url(#{prefix}bar)" filter="url(#{prefix}raise)"/>')
        x += BAR_W + BAR_GAP
    x += CARET_EXTRA
    bars.append(
        f'<rect x="{x:.1f}" y="{cy - CARET_H / 2:.1f}" width="{BAR_W}" height="{CARET_H}" '
        f'rx="{BAR_W / 2}" fill="url(#{prefix}caret)" filter="url(#{prefix}raise)"/>')
    defs = [
        f'<linearGradient id="{prefix}pill" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="{gray(0.96)}"/><stop offset="1" stop-color="{gray(0.85)}"/></linearGradient>',
        f'<linearGradient id="{prefix}bevel" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity=".9"/>'
        '<stop offset=".5" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>',
        f'<linearGradient id="{prefix}bar" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="{gray(0.79)}"/><stop offset="1" stop-color="{gray(0.54)}"/></linearGradient>',
        f'<linearGradient id="{prefix}caret" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="{gray(0.40)}"/><stop offset="1" stop-color="{gray(0.18)}"/></linearGradient>',
        # A shade cast down-right plus a tight contact shadow.
        f'<filter id="{prefix}lift" x="-10%" y="-10%" width="125%" height="145%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="10"/><feOffset dx="10" dy="18" result="key"/>'
        f'<feFlood flood-color="{gray(0.58)}" flood-opacity=".55"/><feComposite in2="key" operator="in" result="keyShadow"/>'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="1"/><feOffset dx="2" dy="3" result="edge"/>'
        f'<feFlood flood-color="{gray(0.36)}" flood-opacity=".35"/><feComposite in2="edge" operator="in" result="edgeShadow"/>'
        '<feMerge><feMergeNode in="keyShadow"/><feMergeNode in="edgeShadow"/><feMergeNode in="SourceGraphic"/></feMerge>'
        '</filter>',
        # The pressed track: shade along the upper-left inner wall, light along the lower right.
        f'<filter id="{prefix}press" x="-5%" y="-10%" width="110%" height="120%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="8"/><feOffset dx="12" dy="12" result="darkOffset"/>'
        '<feComposite in="SourceAlpha" in2="darkOffset" operator="arithmetic" k2="1" k3="-1" result="darkMask"/>'
        f'<feFlood flood-color="{gray(0.58)}"/><feComposite in2="darkMask" operator="in" result="dark"/>'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="7"/><feOffset dx="-10" dy="-10" result="lightOffset"/>'
        '<feComposite in="SourceAlpha" in2="lightOffset" operator="arithmetic" k2="1" k3="-1" result="lightMask"/>'
        '<feFlood flood-color="#FFFFFF"/><feComposite in2="lightMask" operator="in" result="light"/>'
        '<feMerge><feMergeNode in="SourceGraphic"/><feMergeNode in="dark"/><feMergeNode in="light"/></feMerge>'
        '</filter>',
        # Raised bars: light up-left, shade down-right.
        f'<filter id="{prefix}raise" x="-80%" y="-30%" width="260%" height="160%">'
        '<feDropShadow dx="5" dy="8" stdDeviation="4" flood-color="#000000" flood-opacity=".32"/>'
        '<feDropShadow dx="-4" dy="-5" stdDeviation="3.5" flood-color="#FFFFFF" flood-opacity="1"/></filter>',
    ]
    body = "".join([
        f'<rect width="{PILL_W}" height="{PILL_H}" rx="{PILL_H / 2}" fill="url(#{prefix}pill)" filter="url(#{prefix}lift)"/>',
        f'<rect x="2" y="2" width="{PILL_W - 4}" height="{PILL_H - 4}" rx="{PILL_H / 2 - 2}" fill="none" '
        f'stroke="url(#{prefix}bevel)" stroke-width="4"/>',
        f'<rect x="{tx}" y="{ty}" width="{TRACK_W}" height="{TRACK_H}" rx="{TRACK_H / 2}" fill="{gray(0.91)}" '
        f'filter="url(#{prefix}press)"/>',
        *bars,
    ])
    return "".join(defs), body


def lettering() -> tuple[str, float, float, float, float]:
    """Return (path data, viewBox width, height, capsule outer width, outer height)
    from the app wordmark. Its capsule is a stroked rect; the lettering is the
    filled path after it."""
    svg = WORDMARK.read_text()
    view = [float(v) for v in re.search(r'viewBox="([^"]+)"', svg).group(1).split()]
    stroke = float(re.search(r'stroke-width="([\d.]+)"', svg).group(1))
    rect = re.search(r'<rect x="[\d.]+" y="[\d.]+" width="([\d.]+)" height="([\d.]+)"', svg)
    outer_w = float(rect.group(1)) + stroke
    outer_h = float(rect.group(2)) + stroke
    path = re.search(r'<path fill="#000" d="([^"]+)"', svg).group(1)
    return path, view[2], view[3], outer_w, outer_h


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    width, height = PILL_W + 2 * PAD_X, PILL_H + PAD_TOP + PAD_BOTTOM

    defs, body = mark("am-")
    (OUT / "airdraft-mark.svg").write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-PAD_X} {-PAD_TOP} {width} {height}" '
        f'width="{width}" height="{height}" role="img" aria-label="Airdraft">'
        f"<defs>{defs}</defs>{body}</svg>\n")

    # Lockup: the rendered mark takes the place of the wordmark's stroked capsule.
    path, view_w, view_h, outer_w, outer_h = lettering()
    k = outer_h / PILL_H
    top = (view_h - outer_h) / 2
    pad_x, pad_top, pad_bottom = PAD_X * k, PAD_TOP * k, PAD_BOTTOM * k
    defs, body = mark("al-")
    total_w = view_w + 2 * pad_x
    total_h = max(view_h, top + outer_h + pad_bottom) + pad_top
    scale = 10  # export at a usable pixel size
    (OUT / "airdraft-logo.svg").write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-pad_x:.2f} {-pad_top:.2f} {total_w:.2f} {total_h:.2f}" '
        f'width="{total_w * scale:.0f}" height="{total_h * scale:.0f}" role="img" aria-label="Airdraft">'
        f"<defs>{defs}</defs>"
        f'<g transform="translate({(outer_w - PILL_W * k) / 2:.3f} {top:.3f}) scale({k:.6f})">{body}</g>'
        f'<path fill="{INK}" d="{path}"/>'
        "</svg>\n")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
