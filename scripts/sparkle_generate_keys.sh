#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.8.1}"
TOOLS_DIR="$ROOT_DIR/.sparkle/$SPARKLE_VERSION"
GEN_KEYS="$TOOLS_DIR/bin/generate_keys"
ACCOUNT="${SPARKLE_KEYCHAIN_ACCOUNT:-ed25519}"
OUTPUT_PATH="${1:-$ROOT_DIR/.sparkle/private_key}"

download_tools() {
  if [[ -x "$GEN_KEYS" ]]; then
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
  /bin/cp "$tmp_dir/bin/generate_keys" "$TOOLS_DIR/bin/"
  chmod +x "$TOOLS_DIR/bin/generate_keys" || true
}

download_tools

mkdir -p "$(dirname "$OUTPUT_PATH")"

"$GEN_KEYS" --account "$ACCOUNT"
"$GEN_KEYS" --account "$ACCOUNT" -x "$OUTPUT_PATH"
chmod 600 "$OUTPUT_PATH" || true

echo "Private key exported to: $OUTPUT_PATH"
echo "Store the public key in SPARKLE_PUBLIC_KEY and the private key in SPARKLE_PRIVATE_KEY."
