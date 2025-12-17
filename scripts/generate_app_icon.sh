#!/usr/bin/env bash
set -euo pipefail

OUT_ICNS="${1:-}"
if [[ -z "$OUT_ICNS" ]]; then
  echo "Usage: $0 <output.icns>"
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_SRC="$ROOT_DIR/scripts/IconGenerator.swift"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BASE_PNG="$TMP_DIR/AppIcon.png"
ICONSET_DIR="$TMP_DIR/AppIcon.iconset"
BIN="$TMP_DIR/icon_gen"

swiftc -O -framework AppKit -framework Foundation "$SWIFT_SRC" -o "$BIN"
"$BIN" "$BASE_PNG"

mkdir -p "$ICONSET_DIR"

make_png() {
  local size="$1"
  local name="$2"
  /usr/bin/sips -z "$size" "$size" "$BASE_PNG" --out "$ICONSET_DIR/$name" >/dev/null
}

make_png 16  icon_16x16.png
make_png 32  icon_16x16@2x.png
make_png 32  icon_32x32.png
make_png 64  icon_32x32@2x.png
make_png 128 icon_128x128.png
make_png 256 icon_128x128@2x.png
make_png 256 icon_256x256.png
make_png 512 icon_256x256@2x.png
make_png 512 icon_512x512.png
make_png 1024 icon_512x512@2x.png

mkdir -p "$(dirname "$OUT_ICNS")"
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$OUT_ICNS"

echo "Built: $OUT_ICNS"
