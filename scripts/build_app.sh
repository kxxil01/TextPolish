#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TextPolish"
BUNDLE_ID="com.kxxil01.TextPolish"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
EXEC_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
ICON_NAME="AppIcon"
ICON_FILE="${ICON_NAME}.icns"
VERSION="${TEXT_POLISH_VERSION:-}"
BUILD="${TEXT_POLISH_BUILD:-}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/kxxil01/TextPolish/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
SPARKLE_REQUIRE_PUBLIC_KEY="${SPARKLE_REQUIRE_PUBLIC_KEY:-}"

if [[ -z "$VERSION" ]]; then
  if git -C "$ROOT_DIR" describe --tags --abbrev=0 >/dev/null 2>&1; then
    VERSION="$(git -C "$ROOT_DIR" describe --tags --abbrev=0)"
    VERSION="${VERSION#v}"
  else
    VERSION="0.1.1"
  fi
fi

if [[ -z "$BUILD" ]]; then
  if git -C "$ROOT_DIR" rev-list --count HEAD >/dev/null 2>&1; then
    BUILD="$(git -C "$ROOT_DIR" rev-list --count HEAD)"
  else
    BUILD="1"
  fi
fi

if [[ -n "$SPARKLE_REQUIRE_PUBLIC_KEY" && -z "$SPARKLE_PUBLIC_KEY" ]]; then
  echo "Missing SPARKLE_PUBLIC_KEY for release build."
  exit 2
fi

if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
  SPARKLE_AUTOMATIC_CHECKS="<true/>"
else
  SPARKLE_AUTOMATIC_CHECKS="<false/>"
fi

if [[ -e "$APP_DIR" && ! -w "$APP_DIR" ]]; then
  ALT_DIR="$BUILD_DIR/dev/${APP_NAME}.app"
  echo "Warning: $APP_DIR is not writable; building to $ALT_DIR"
  APP_DIR="$ALT_DIR"
  EXEC_DIR="$APP_DIR/Contents/MacOS"
  RES_DIR="$APP_DIR/Contents/Resources"
  FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
fi

rm -rf "$APP_DIR"
mkdir -p "$EXEC_DIR"
mkdir -p "$RES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

"$ROOT_DIR/scripts/generate_app_icon.sh" "$RES_DIR/$ICON_FILE" >/dev/null

swift build -c release --product "$APP_NAME"

BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY_PATH="$BIN_DIR/$APP_NAME"
if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Failed to find built binary at: $BINARY_PATH"
  exit 2
fi

/bin/cp "$BINARY_PATH" "$EXEC_DIR/$APP_NAME"

SPARKLE_FRAMEWORK_PATH="$BIN_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK_PATH" ]]; then
  SPARKLE_FRAMEWORK_PATH="$(find "$ROOT_DIR/.build" -type d -name Sparkle.framework | head -n 1)"
fi

if [[ -d "$SPARKLE_FRAMEWORK_PATH" ]]; then
  /bin/rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
  /bin/cp -R "$SPARKLE_FRAMEWORK_PATH" "$FRAMEWORKS_DIR/"
else
  echo "Failed to find Sparkle.framework in build artifacts."
  exit 2
fi

if command -v otool >/dev/null 2>&1 && command -v install_name_tool >/dev/null 2>&1; then
  if ! otool -l "$EXEC_DIR/$APP_NAME" | /usr/bin/grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXEC_DIR/$APP_NAME"
  fi
fi

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
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD}</string>
  <key>CFBundleIconFile</key>
  <string>${ICON_NAME}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>SUFeedURL</key>
  <string>${SPARKLE_FEED_URL}</string>
  <key>SUPublicEDKey</key>
  <string>${SPARKLE_PUBLIC_KEY}</string>
  <key>SUEnableAutomaticChecks</key>
  ${SPARKLE_AUTOMATIC_CHECKS}
  <key>SUScheduledCheckInterval</key>
  <integer>21600</integer>
</dict>
</plist>
EOF

echo "Built: $APP_DIR"
