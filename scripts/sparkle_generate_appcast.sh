#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.8.1}"
TOOLS_DIR="$ROOT_DIR/.sparkle/$SPARKLE_VERSION"
GEN_APPCAST="$TOOLS_DIR/bin/generate_appcast"

ARCHIVES_DIR="${1:-}"
OUTPUT_PATH="${2:-}"

if [[ -z "$ARCHIVES_DIR" || -z "$OUTPUT_PATH" ]]; then
  echo "Usage: $0 <archives-dir> <output-path>"
  exit 2
fi

if [[ ! -d "$ARCHIVES_DIR" ]]; then
  echo "Archives directory not found: $ARCHIVES_DIR"
  exit 2
fi

if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "Missing SPARKLE_PRIVATE_KEY."
  exit 2
fi

if [[ -z "${SPARKLE_DOWNLOAD_URL_PREFIX:-}" ]]; then
  echo "Missing SPARKLE_DOWNLOAD_URL_PREFIX."
  exit 2
fi

if [[ "${SPARKLE_DOWNLOAD_URL_PREFIX}" != */ ]]; then
  SPARKLE_DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX}/"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

download_tools() {
  if [[ -x "$GEN_APPCAST" ]]; then
    return
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  local archive
  archive="$tmp_dir/Sparkle.tar.xz"
  local url
  url="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

  curl -sL --fail "$url" -o "$archive"
  tar -xf "$archive" -C "$tmp_dir"

  mkdir -p "$TOOLS_DIR/bin"
  /bin/cp "$tmp_dir/bin/generate_appcast" "$TOOLS_DIR/bin/"
  /bin/cp "$tmp_dir/bin/generate_keys" "$TOOLS_DIR/bin/" 2>/dev/null || true
  chmod +x "$TOOLS_DIR/bin/generate_appcast" || true
}

download_tools

printf '%s' "$SPARKLE_PRIVATE_KEY" | \
  "$GEN_APPCAST" \
  --ed-key-file - \
  --download-url-prefix "$SPARKLE_DOWNLOAD_URL_PREFIX" \
  -o "$OUTPUT_PATH" \
  "$ARCHIVES_DIR"
