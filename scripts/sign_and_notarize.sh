#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TextPolish"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP_PATH="$ROOT_DIR/build/${APP_NAME}.app.zip"

if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  echo "Missing CODESIGN_IDENTITY."
  echo "Example: export CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'"
  exit 2
fi

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "Missing NOTARY_PROFILE."
  echo "Create one with:"
  echo "  xcrun notarytool store-credentials 'TextPolishNotary' --apple-id 'you@example.com' --team-id 'TEAMID' --password 'APP_SPECIFIC_PASSWORD'"
  echo "Then: export NOTARY_PROFILE='TextPolishNotary'"
  exit 2
fi

BUILD_OUTPUT="$("$ROOT_DIR/scripts/build_app.sh")"
echo "$BUILD_OUTPUT"
APP_PATH="$(echo "$BUILD_OUTPUT" | tail -n 1 | sed -E 's/^Built: //')"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Failed to find built app bundle at: $APP_PATH"
  exit 2
fi

echo "Signing: $APP_PATH"
if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' framework; do
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" --deep "$framework"
  done < <(find "$APP_PATH/Contents/Frameworks" -type d -name "*.framework" -print0)
fi
codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_PATH/Contents/MacOS/$APP_NAME"
codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_PATH"

echo "Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Submitting for notarization…"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "Stapling ticket…"
xcrun stapler staple "$APP_PATH"

echo "Assessing with Gatekeeper…"
spctl --assess --type execute --verbose=4 "$APP_PATH"

echo "Done: $APP_PATH"
