#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TextPolish"
BUNDLE_ID="com.kxxil01.TextPolish"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
EXEC_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
ICON_NAME="AppIcon"
ICON_FILE="${ICON_NAME}.icns"

if [[ -e "$APP_DIR" && ! -w "$APP_DIR" ]]; then
  ALT_DIR="$BUILD_DIR/dev/${APP_NAME}.app"
  echo "Warning: $APP_DIR is not writable; building to $ALT_DIR"
  APP_DIR="$ALT_DIR"
  EXEC_DIR="$APP_DIR/Contents/MacOS"
  RES_DIR="$APP_DIR/Contents/Resources"
fi

rm -rf "$APP_DIR"
mkdir -p "$EXEC_DIR"
mkdir -p "$RES_DIR"

"$ROOT_DIR/scripts/generate_app_icon.sh" "$RES_DIR/$ICON_FILE" >/dev/null

swiftc \
  -O \
  -framework AppKit \
  -framework Carbon \
  -framework ApplicationServices \
  -framework Security \
  -framework ServiceManagement \
  -framework Foundation \
  "$ROOT_DIR/src/"*.swift \
  -o "$EXEC_DIR/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.1</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>CFBundleIconFile</key>
  <string>${ICON_NAME}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

echo "Built: $APP_DIR"
