#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TextPolish"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
PKG_PATH="$BUILD_DIR/${APP_NAME}.pkg"
PKG_ROOT="$BUILD_DIR/pkgroot"
COMPONENT_PLIST="$BUILD_DIR/components.plist"
PKG_SCRIPTS="$ROOT_DIR/scripts/pkg_scripts"

BUILD_OUTPUT="$("$ROOT_DIR/scripts/build_app.sh")"
echo "$BUILD_OUTPUT"
APP_PATH="$(echo "$BUILD_OUTPUT" | tail -n 1 | sed -E 's/^Built: //')"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Failed to find built app bundle at: $APP_PATH"
  exit 2
fi

VERSION="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.1.1"
)"
IDENTIFIER="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "com.kxxil01.${APP_NAME}"
)"

rm -f "$PKG_PATH"

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications"
ditto "$APP_PATH" "$PKG_ROOT/Applications/${APP_NAME}.app"

cat > "$COMPONENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
  <dict>
    <key>RootRelativeBundlePath</key>
    <string>Applications/${APP_NAME}.app</string>
    <key>BundleIsRelocatable</key>
    <false/>
    <key>BundleHasStrictIdentifier</key>
    <true/>
    <key>BundleOverwriteAction</key>
    <string>upgrade</string>
  </dict>
</array>
</plist>
EOF

pkgbuild \
  --root "$PKG_ROOT" \
  --component-plist "$COMPONENT_PLIST" \
  --scripts "$PKG_SCRIPTS" \
  --install-location "/" \
  --identifier "${IDENTIFIER}.pkg" \
  --version "$VERSION" \
  "$PKG_PATH"

echo "Built: $PKG_PATH"
