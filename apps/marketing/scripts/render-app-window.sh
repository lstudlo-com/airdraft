#!/usr/bin/env bash
# Renders the homepage's real app window (the interface section) from a Debug
# build: the Settings page at the fixed 784-point width, light and dark,
# with an isolated empty data directory (--e2e-local), so the sidebar reads
# "Ready to dictate" and no history, usage count or personal setting appears.
# The renders are converted to grayscale, as the app looks with the system's
# Graphite accent; the site carries no hue (scripts/check-neutral.mjs).
#
# Usage, from the repository root:
#   apps/marketing/scripts/render-app-window.sh ["path/to/Airdraft Debug.app"]
set -euo pipefail

app="${1:-}"
if [[ -z "$app" ]]; then
  app="$(ls -td "$HOME"/Library/Developer/Xcode/DerivedData/airdraft-*/Build/Products/Debug/"Airdraft Debug.app" 2>/dev/null | head -n 1 || true)"
fi
if [[ ! -x "$app/Contents/MacOS/Airdraft Debug" ]]; then
  echo "No Airdraft Debug build found; build Debug first or pass the .app path." >&2
  exit 1
fi
command -v magick >/dev/null || { echo "ImageMagick (magick) is required." >&2; exit 1; }

out="apps/marketing/public/app"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/data" "$work/renders" "$out"

AIRDRAFT_RENDER_MIC_DEVICES=single AIRDRAFT_RENDER_HEIGHT=760 \
  "$app/Contents/MacOS/Airdraft Debug" --e2e-local "$work/data" \
  --render-window configuration "$work/renders" >/dev/null

for appearance in light dark; do
  magick -quiet "$work/renders/configuration-$appearance.png" \
    -colorspace Gray -colorspace sRGB -strip -quality 86 \
    "$out/configuration-$appearance.webp"
done
chmod 644 "$out"/configuration-*.webp
ls -l "$out"
