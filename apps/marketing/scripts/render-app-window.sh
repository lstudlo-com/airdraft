#!/usr/bin/env bash
# Renders the homepage's real app window (the interface section) from a Debug
# build: the Settings page at the fixed 784-point width, light and dark,
# with an isolated empty data directory (--e2e-local), so no history, usage
# count or personal setting appears. The fixture never starts the shortcut, so
# the sidebar footer reads "Finish Setup".
# It renders the English interface for the English pages and the Traditional
# Chinese (zh-Hant, Taiwan) interface for the /zh-tw/ pages, which the app
# ships from 0.11.0. Render from a Debug build of the current release's sources.
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
mkdir -p "$out"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"

# Site locale, output prefix, app launch arguments (placed before --e2e-local).
render() {
  local locale="$1" prefix="$2"
  shift 2
  mkdir -p "$work/data-$locale" "$work/renders-$locale"
  AIRDRAFT_RENDER_MIC_DEVICES=single AIRDRAFT_RENDER_HEIGHT=1000 \
    "$app/Contents/MacOS/Airdraft Debug" "$@" --e2e-local "$work/data-$locale" \
    --render-window configuration "$work/renders-$locale" >/dev/null
  for appearance in light dark; do
    magick -quiet "$work/renders-$locale/configuration-$appearance.png" \
      -colorspace Gray -colorspace sRGB -strip -quality 86 \
      "$out/$prefix-$appearance.webp"
  done
}
render en configuration
render zh-tw configuration-zh-tw -AppleLanguages '(zh-Hant)' -AppleLocale zh_TW

python3 - "$out" "$version" <<'PY'
import json
import sys
from pathlib import Path

languages = {"configuration": "English", "configuration-zh-tw": "Traditional Chinese (zh-Hant, Taiwan)"}
for prefix, language in languages.items():
    for appearance in ("light", "dark"):
        image = Path(sys.argv[1]) / f"{prefix}-{appearance}.webp"
        origin = (f"Origin: native Airdraft {sys.argv[2]} Debug Settings window in "
                  f"{appearance} mode with the {language} interface, rendered at "
                  "784 by 1000 points with isolated empty data and one fixture "
                  "microphone by apps/marketing/scripts/render-app-window.sh; "
                  "converted to grayscale WebP. No image-generation model was used.")
        image.with_suffix(image.suffix + ".json").write_text(
            json.dumps({"prompt": origin}, indent=2) + "\n", encoding="utf-8")
PY
chmod 644 "$out"/configuration-*.webp
ls -l "$out"
