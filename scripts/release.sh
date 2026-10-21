#!/usr/bin/env bash
# Publishes a release only after CI passes on the exact main commit, then waits for the signed build
# and checks that Sparkle and Homebrew offer the new version.
#
#   scripts/release.sh 0.0.74 notes.md
set -euo pipefail

REPO="kxxil01/TextPolish"
APPCAST_URL="https://github.com/$REPO/releases/latest/download/appcast.xml"
CASK_URL="https://raw.githubusercontent.com/kxxil01/homebrew-tap/main/Casks/textpolish.rb"

fail() {
  echo "release: $*" >&2
  exit 1
}

[[ $# -eq 2 ]] || fail "usage: scripts/release.sh <version> <notes-file>"
VERSION="$1"
NOTES_FILE="$2"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 0.0.74 (no v prefix)"
[[ -s "$NOTES_FILE" ]] || fail "notes file $NOTES_FILE is missing or empty"
if gh release view "$VERSION" --repo "$REPO" >/dev/null 2>&1; then
  fail "release $VERSION already exists"
fi

SHA="$(gh api "repos/$REPO/commits/main" --jq .sha)"
echo "release: main is at ${SHA:0:7}"

# The CI run for a fresh merge can take a few seconds to appear.
CI_RUN=""
for _ in $(seq 1 30); do
  CI_RUN="$(gh run list --repo "$REPO" --workflow ci.yml --branch main --commit "$SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
  [[ -n "$CI_RUN" ]] && break
  sleep 10
done
[[ -n "$CI_RUN" ]] || fail "no CI run found for ${SHA:0:7}"

echo "release: waiting for CI run $CI_RUN"
if ! gh run watch "$CI_RUN" --repo "$REPO" --exit-status --interval 20 >/dev/null; then
  fail "CI failed for ${SHA:0:7}; not releasing (gh run view $CI_RUN --repo $REPO --log-failed)"
fi
echo "release: CI passed"

gh release create "$VERSION" --repo "$REPO" --target "$SHA" --title "$VERSION" --notes-file "$NOTES_FILE"

BUILD_RUN=""
for _ in $(seq 1 30); do
  BUILD_RUN="$(gh run list --repo "$REPO" --workflow release.yml --branch "$VERSION" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
  [[ -n "$BUILD_RUN" ]] && break
  sleep 10
done
[[ -n "$BUILD_RUN" ]] || fail "no release build started for $VERSION"

echo "release: waiting for signed build $BUILD_RUN"
if ! gh run watch "$BUILD_RUN" --repo "$REPO" --exit-status --interval 30 >/dev/null; then
  fail "release build failed (gh run view $BUILD_RUN --repo $REPO --log-failed)"
fi

# Release assets and the tap update can lag the build by a little while.
for _ in $(seq 1 12); do
  APPCAST_VERSION="$(curl -fsSL "$APPCAST_URL" | sed -n 's/.*<sparkle:shortVersionString>\([^<]*\)<.*/\1/p' | head -1 || true)"
  CASK_VERSION="$(curl -fsSL "$CASK_URL" | sed -n 's/^ *version "\([^"]*\)".*/\1/p' | head -1 || true)"
  if [[ "$APPCAST_VERSION" == "$VERSION" && "$CASK_VERSION" == "$VERSION" ]]; then
    echo "release: $VERSION is live (Sparkle and Homebrew)"
    exit 0
  fi
  sleep 10
done
fail "build finished but appcast shows '${APPCAST_VERSION:-none}' and cask shows '${CASK_VERSION:-none}'"
