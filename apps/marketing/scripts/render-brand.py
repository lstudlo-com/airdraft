# /// script
# requires-python = ">=3.10"
# dependencies = ["fonttools>=4.50", "brotli>=1.1", "uharfbuzz>=0.39"]
# ///
"""Render Airdraft's brand SVGs from the app icon's geometry and Manrope.

Writes, into apps/marketing/public/brand/ (served as-is, for use outside the
site; the site itself draws the logo in CSS 3D with ui/Brand.astro):
  airdraft-mark.svg  the icon's raised capsule, groove, waveform and caret
  airdraft-logo.svg  the mark with the "Airdraft" wordmark as outlines

The capsule mirrors scripts/render-app-icon.swift (Edged, larger); change both
together. The wordmark is Manrope at the header's weight and tracking, shaped
with HarfBuzz so kerning matches the browser.

Usage, from the repo root:  uv run apps/marketing/scripts/render-brand.py
"""

from io import BytesIO
from pathlib import Path

import uharfbuzz as hb
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "apps/marketing/public/brand"
FONT = next(ROOT.glob(
    "node_modules/.pnpm/@fontsource-variable+manrope@*/node_modules/"
    "@fontsource-variable/manrope/files/manrope-latin-wght-normal.woff2"))

WORDMARK = "Airdraft"
WEIGHT = 750            # .brand in src/styles/global.css
TRACKING = -0.03        # em
INK = "#263146"

# Icon geometry (render-app-icon.swift), in icon points.
PILL_W, PILL_H = 744, 364
TRACK_W, TRACK_H = 650, 270
LEVELS = [0.36, 0.66, 1.0, 0.72, 0.48]
BAR_W, BAR_GAP, BAR_H = 38, 30, 190
CARET_H, CARET_EXTRA = 208, 20
PAD_X, PAD_TOP, PAD_BOTTOM = 24, 16, 44   # room for the lift shadow

NEUTRAL, VIOLET, CYAN = (174, 185, 204), (107, 122, 255), (59, 195, 244)


def mix(a, b, t):
    return "#%02X%02X%02X" % tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def mark(prefix: str) -> tuple[str, str]:
    """Return (defs, body) for the mark, with the pill's origin at 0,0."""
    cx, cy = PILL_W / 2, PILL_H / 2
    tx, ty = (PILL_W - TRACK_W) / 2, (PILL_H - TRACK_H) / 2
    widths = len(LEVELS) * BAR_W + len(LEVELS) * BAR_GAP + CARET_EXTRA + BAR_W
    x = cx - widths / 2  # the icon's HStack spacing sits between every item
    defs, bars = [], []
    for i, level in enumerate(LEVELS):
        t = (i + 1) / (len(LEVELS) + 1) * 0.85
        h = BAR_H * level
        defs.append(
            f'<linearGradient id="{prefix}bar{i}" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{mix(NEUTRAL, VIOLET, t)}"/>'
            f'<stop offset="1" stop-color="{mix(NEUTRAL, CYAN, t)}"/></linearGradient>')
        bars.append(
            f'<rect x="{x:.1f}" y="{cy - h / 2:.1f}" width="{BAR_W}" height="{h:.1f}" '
            f'rx="{BAR_W / 2}" fill="url(#{prefix}bar{i})" filter="url(#{prefix}barShadow)"/>')
        x += BAR_W + BAR_GAP
    x += CARET_EXTRA
    caret = (f'<rect x="{x:.1f}" y="{cy - CARET_H / 2:.1f}" width="{BAR_W}" height="{CARET_H}" '
             f'rx="{BAR_W / 2}" fill="url(#{prefix}caret)"')
    defs += [
        f'<linearGradient id="{prefix}pill" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#F1F4F9"/><stop offset="1" stop-color="#DCE1E9"/></linearGradient>',
        f'<linearGradient id="{prefix}bevel" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity=".9"/>'
        '<stop offset=".5" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>',
        f'<linearGradient id="{prefix}caret" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#6B7AFF"/><stop offset="1" stop-color="#3BC3F4"/></linearGradient>',
        # A short shadow underneath plus a tight contact shadow.
        f'<filter id="{prefix}lift" x="-10%" y="-10%" width="120%" height="140%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="10"/><feOffset dy="18" result="key"/>'
        '<feFlood flood-color="#A3B0C6" flood-opacity=".55"/><feComposite in2="key" operator="in" result="keyShadow"/>'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="1"/><feOffset dy="3" result="edge"/>'
        '<feFlood flood-color="#5F6C87" flood-opacity=".35"/><feComposite in2="edge" operator="in" result="edgeShadow"/>'
        '<feMerge><feMergeNode in="keyShadow"/><feMergeNode in="edgeShadow"/><feMergeNode in="SourceGraphic"/></feMerge>'
        '</filter>',
        # The pressed track: dark along the upper-left inner wall, light along the lower right.
        f'<filter id="{prefix}press" x="-5%" y="-10%" width="110%" height="120%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="8"/><feOffset dx="12" dy="12" result="darkOffset"/>'
        '<feComposite in="SourceAlpha" in2="darkOffset" operator="arithmetic" k2="1" k3="-1" result="darkMask"/>'
        '<feFlood flood-color="#A3B0C6"/><feComposite in2="darkMask" operator="in" result="dark"/>'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="7"/><feOffset dx="-10" dy="-10" result="lightOffset"/>'
        '<feComposite in="SourceAlpha" in2="lightOffset" operator="arithmetic" k2="1" k3="-1" result="lightMask"/>'
        '<feFlood flood-color="#FFFFFF"/><feComposite in2="lightMask" operator="in" result="light"/>'
        '<feMerge><feMergeNode in="SourceGraphic"/><feMergeNode in="dark"/><feMergeNode in="light"/></feMerge>'
        '</filter>',
        f'<filter id="{prefix}barShadow" x="-40%" y="-20%" width="200%" height="150%">'
        '<feDropShadow dx="2" dy="3" stdDeviation="2" flood-color="#A3B0C6" flood-opacity=".2"/></filter>',
        f'<filter id="{prefix}glow" x="-200%" y="-40%" width="500%" height="180%">'
        '<feGaussianBlur stdDeviation="11"/></filter>',
    ]
    body = "".join([
        f'<rect width="{PILL_W}" height="{PILL_H}" rx="{PILL_H / 2}" fill="url(#{prefix}pill)" filter="url(#{prefix}lift)"/>',
        f'<rect x="2" y="2" width="{PILL_W - 4}" height="{PILL_H - 4}" rx="{PILL_H / 2 - 2}" fill="none" '
        f'stroke="url(#{prefix}bevel)" stroke-width="4"/>',
        f'<rect x="{tx}" y="{ty}" width="{TRACK_W}" height="{TRACK_H}" rx="{TRACK_H / 2}" fill="#E6EAF1" '
        f'filter="url(#{prefix}press)"/>',
        *bars,
        f'<g opacity=".6" filter="url(#{prefix}glow)">{caret} fill-opacity="1"/></g>',
        f'{caret}/>',
    ])
    return "".join(defs), body


def wordmark(size: float) -> tuple[str, float, float]:
    """Return (path data, advance width, cap height) for the wordmark at `size`."""
    font = TTFont(FONT)
    font.flavor = None
    static = instancer.instantiateVariableFont(font, {"wght": WEIGHT})
    data = BytesIO()
    static.save(data)
    upem = static["head"].unitsPerEm
    face = hb.Face(data.getvalue())
    shaper = hb.Font(face)
    buffer = hb.Buffer()
    buffer.add_str(WORDMARK)
    buffer.guess_segment_properties()
    hb.shape(shaper, buffer, {"kern": True, "liga": True})
    order = static.getGlyphOrder()
    glyphs = static.getGlyphSet()
    scale = size / upem
    tracking = TRACKING * upem
    pen = SVGPathPen(glyphs)
    x = 0.0
    count = len(buffer.glyph_infos)
    for index, (info, position) in enumerate(zip(buffer.glyph_infos, buffer.glyph_positions)):
        # Font units are y-up; SVG is y-down with the baseline at y = 0.
        glyphs[order[info.codepoint]].draw(
            TransformPen(pen, (scale, 0, 0, -scale, (x + position.x_offset) * scale, -position.y_offset * scale)))
        x += position.x_advance + (tracking if index < count - 1 else 0)
    cap = static["OS/2"].sCapHeight * scale
    return pen.getCommands(), x * scale, cap


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    width, height = PILL_W + 2 * PAD_X, PILL_H + PAD_TOP + PAD_BOTTOM

    defs, body = mark("am-")
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-PAD_X} {-PAD_TOP} {width} {height}" '
           f'width="{width}" height="{height}" role="img" aria-label="Airdraft">'
           f"<defs>{defs}</defs>{body}</svg>\n")
    (OUT / "airdraft-mark.svg").write_text(svg)

    # Lockup: pill height is 1.43 × the wordmark's font size, as in the header.
    font_size = 200
    k = 1.43 * font_size / PILL_H
    path, advance, cap = wordmark(font_size)
    gap = 0.55 * font_size
    mark_w, mark_h = width * k, height * k
    baseline = (PAD_TOP + PILL_H / 2) * k + cap / 2
    defs, body = mark("al-")
    total = mark_w + gap + advance + PAD_X * k
    (OUT / "airdraft-logo.svg").write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {total:.1f} {mark_h:.1f}" '
        f'width="{total:.0f}" height="{mark_h:.0f}" role="img" aria-label="Airdraft">'
        f"<defs>{defs}</defs>"
        f'<g transform="translate({PAD_X * k:.2f} {PAD_TOP * k:.2f}) scale({k:.5f})">{body}</g>'
        f'<path transform="translate({mark_w + gap:.2f} {baseline:.2f})" fill="{INK}" d="{path}"/>'
        "</svg>\n")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
