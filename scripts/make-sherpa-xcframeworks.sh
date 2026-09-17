#!/bin/bash
# Repackages the official sherpa-onnx + onnxruntime static xcframeworks as
# *library* xcframeworks. The official ones wrap static archives in .framework
# bundles, which Xcode then embeds and tries to sign (and fails). Library
# xcframeworks are linked only, never embedded. Run once after cloning.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Packages/SherpaOnnxKit/Vendor"
TMP="$(mktemp -d)"
SHERPA_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.8-macos-static.xcframework.zip"
ORT_URL="https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.28.2/onnxruntime-macos-static-xcframework-1.28.2.xcframework.zip"

fetch() { # url dest-dir
  echo "downloading $1"
  curl -sL "$1" -o "$TMP/pkg.zip"
  mkdir -p "$2" && unzip -q -o "$TMP/pkg.zip" -d "$2"
}

fetch "$SHERPA_URL" "$TMP/sherpa"
fetch "$ORT_URL" "$TMP/ort"

SHERPA_FW="$(find "$TMP/sherpa" -type d -path '*macos*' -name 'SherpaOnnxC.framework' | head -1)"
ORT_FW="$(find "$TMP/ort" -type d -path '*macos*' -name 'onnxruntime.framework' | head -1)"
[ -n "$SHERPA_FW" ] && [ -n "$ORT_FW" ] || { echo "frameworks not found in archives"; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT" "$TMP/build/headers"
cp "$SHERPA_FW/Versions/A/SherpaOnnxC" "$TMP/build/libSherpaOnnxC.a"
cp -R "$SHERPA_FW/Versions/A/Headers/." "$TMP/build/headers/"
cat > "$TMP/build/headers/module.modulemap" <<'MM'
module SherpaOnnxC {
  header "sherpa-onnx/c-api/c-api.h"
  export *
}
MM
cp "$ORT_FW/Versions/A/onnxruntime" "$TMP/build/libonnxruntime.a"

xcodebuild -create-xcframework -library "$TMP/build/libSherpaOnnxC.a" -headers "$TMP/build/headers" -output "$OUT/SherpaOnnxC.xcframework" >/dev/null
xcodebuild -create-xcframework -library "$TMP/build/libonnxruntime.a" -output "$OUT/onnxruntime.xcframework" >/dev/null
rm -rf "$TMP"
echo "wrote $OUT"; ls "$OUT"
