#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TextPolish"
BUNDLE_ID="com.kxxil01.TextPolish"
LEGACY_BUNDLE_ID="com.ilham.GrammarCorrection"
PKG_ID="${BUNDLE_ID}.pkg"
LEGACY_PKG_ID="${LEGACY_BUNDLE_ID}.pkg"
SERVICE="$BUNDLE_ID"
LEGACY_SERVICE="$LEGACY_BUNDLE_ID"

APP_PATH="/Applications/${APP_NAME}.app"
LEGACY_APP_PATH="/Applications/GrammarCorrection.app"
SETTINGS_DIR="$HOME/Library/Application Support/${APP_NAME}"
LEGACY_SETTINGS_DIR="$HOME/Library/Application Support/GrammarCorrection"

YES=false
KEEP_APP=false
KEEP_KEYCHAIN=false
KEEP_SETTINGS=false
KEEP_RECEIPT=false
KEEP_BUILDS=false

for arg in "$@"; do
  case "$arg" in
    --yes) YES=true ;;
    --keep-app) KEEP_APP=true ;;
    --keep-keychain) KEEP_KEYCHAIN=true ;;
    --keep-settings) KEEP_SETTINGS=true ;;
    --keep-receipt) KEEP_RECEIPT=true ;;
    --keep-builds) KEEP_BUILDS=true ;;
    *)
      echo "Unknown arg: $arg"
      echo "Usage: $0 [--yes] [--keep-app] [--keep-keychain] [--keep-settings] [--keep-receipt] [--keep-builds]"
      exit 2
      ;;
  esac
done

if [[ "$YES" != "true" ]]; then
  echo "This will stop ${APP_NAME}, disable Start at Login, and remove:"
  echo "- ${APP_PATH}"
  echo "- ${LEGACY_APP_PATH}"
  echo "- ${SETTINGS_DIR}"
  echo "- ${LEGACY_SETTINGS_DIR}"
  echo "- Keychain items (${SERVICE} / geminiApiKey, openRouterApiKey)"
  echo "- Keychain items (${LEGACY_SERVICE} / geminiApiKey, openRouterApiKey)"
  echo "- Package receipt (${PKG_ID}) if possible"
  echo "- Package receipt (${LEGACY_PKG_ID}) if possible"
  echo "- Repo build artifacts (.build/, build/) if run inside the repo"
  echo
  read -r -p "Type YES to continue: " CONFIRM
  if [[ "$CONFIRM" != "YES" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "Stopping running processes…"
/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
/usr/bin/pkill -x "GrammarCorrection" >/dev/null 2>&1 || true

run_with_timeout() {
  local seconds="$1"
  shift
  /usr/bin/python3 - "$seconds" "$@" <<'PY' || true
import subprocess
import sys

timeout = float(sys.argv[1])
cmd = sys.argv[2:]
try:
  subprocess.run(cmd, timeout=timeout, check=False)
except subprocess.TimeoutExpired:
  pass
PY
}

echo "Disabling Start at Login (best-effort)…"
if [[ -x "$APP_PATH/Contents/MacOS/$APP_NAME" ]]; then
  run_with_timeout 8 "$APP_PATH/Contents/MacOS/$APP_NAME" --unregister-login-item >/dev/null 2>&1 || true
elif [[ -x "$LEGACY_APP_PATH/Contents/MacOS/GrammarCorrection" ]]; then
  run_with_timeout 8 "$LEGACY_APP_PATH/Contents/MacOS/GrammarCorrection" --unregister-login-item >/dev/null 2>&1 || true
fi

if [[ "$KEEP_SETTINGS" != "true" ]]; then
  echo "Removing settings…"
  /bin/rm -rf "$SETTINGS_DIR" || true
  /bin/rm -rf "$LEGACY_SETTINGS_DIR" || true
fi

if [[ "$KEEP_KEYCHAIN" != "true" ]]; then
  echo "Removing Keychain items…"
  run_with_timeout 8 /usr/bin/security delete-generic-password -s "$SERVICE" -a "geminiApiKey" >/dev/null 2>&1 || true
  run_with_timeout 8 /usr/bin/security delete-generic-password -s "$SERVICE" -a "openRouterApiKey" >/dev/null 2>&1 || true
  run_with_timeout 8 /usr/bin/security delete-generic-password -s "$LEGACY_SERVICE" -a "geminiApiKey" >/dev/null 2>&1 || true
  run_with_timeout 8 /usr/bin/security delete-generic-password -s "$LEGACY_SERVICE" -a "openRouterApiKey" >/dev/null 2>&1 || true
fi

if [[ "$KEEP_APP" != "true" ]]; then
  echo "Removing app…"
  /bin/rm -rf "$APP_PATH" || true
  /bin/rm -rf "$LEGACY_APP_PATH" || true
fi

if [[ "$KEEP_RECEIPT" != "true" ]]; then
  echo "Forgetting package receipt (best-effort)…"
  run_with_timeout 8 /usr/sbin/pkgutil --forget "$PKG_ID" >/dev/null 2>&1 || true
  run_with_timeout 8 /usr/sbin/pkgutil --forget "$LEGACY_PKG_ID" >/dev/null 2>&1 || true
fi

if [[ "$KEEP_BUILDS" != "true" ]]; then
  if [[ -f "Package.swift" && -d "src" ]]; then
    echo "Removing repo build artifacts…"
    /bin/rm -rf .build build >/dev/null 2>&1 || true
  fi
fi

echo "Done."
