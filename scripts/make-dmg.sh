#!/usr/bin/env bash
#
# make-dmg.sh — build a distributable PoorDeck.app and wrap it in a .dmg.
#
# Unlike scripts/build-run.sh (which builds a Debug bundle and runs it against
# the client on disk via POORDECK_WEBROOT), this script produces a *self-
# contained* Release bundle: it copies the built Svelte client into
# `PoorDeck.app/Contents/Resources/web`, which is exactly where the server
# looks for it when no POORDECK_WEBROOT override is set (see Server.webRoot()).
# So the resulting .dmg runs on any Mac without the repo present.
#
# The build is ad-hoc signed only (CODE_SIGN_IDENTITY="-"): there is no Apple
# Developer ID signature or notarization, so the first launch needs the
# right-click ▸ Open / xattr dance documented in the README.
#
# Output: dist/PoorDeck-<version>.dmg (version = MARKETING_VERSION, or the
# value passed as $1 — the CI workflow passes the pushed tag).
#
# Usage:
#   scripts/make-dmg.sh            # version from project.yml MARKETING_VERSION
#   scripts/make-dmg.sh v0.2.0     # override the version label
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP_DIR="${REPO_ROOT}/desktop"
CLIENT_DIR="${REPO_ROOT}/client"
BUILD_DIR="${DESKTOP_DIR}/build"
DIST_DIR="${REPO_ROOT}/dist"
CONFIG="Release"

# Version label: explicit arg wins, else MARKETING_VERSION from project.yml,
# else 0.0.0. Strip a leading "v" so PoorDeck-0.2.0.dmg, not PoorDeck-v0.2.0.dmg.
VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
  VERSION="$(grep -E '^\s*MARKETING_VERSION:' "${DESKTOP_DIR}/project.yml" \
    | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
fi
VERSION="${VERSION#v}"
: "${VERSION:=0.0.0}"

step() { printf '\033[1;34m▸\033[0m %s\n' "$1"; }
info() { printf '  \033[0;90m%s\033[0m\n' "$1"; }

step "Building Svelte client"
cd "${CLIENT_DIR}"
[ -d node_modules ] || npm install
npm run build

step "Generating Xcode project"
cd "${DESKTOP_DIR}"
xcodegen generate >/dev/null

step "Building PoorDeck.app (${CONFIG})"
xcodebuild \
  -project PoorDeck.xcodeproj \
  -scheme PoorDeck \
  -configuration "${CONFIG}" \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build

APP="${BUILD_DIR}/Build/Products/${CONFIG}/PoorDeck.app"
BIN="${APP}/Contents/MacOS/PoorDeck"
if [ ! -x "${BIN}" ]; then
  echo "build did not produce ${BIN}" >&2
  exit 1
fi

step "Embedding client into the bundle (Contents/Resources/web)"
WEB_DEST="${APP}/Contents/Resources/web"
rm -rf "${WEB_DEST}"
mkdir -p "${WEB_DEST}"
cp -R "${CLIENT_DIR}/dist/." "${WEB_DEST}/"
if [ ! -f "${WEB_DEST}/index.html" ]; then
  echo "client dist did not land at ${WEB_DEST}/index.html" >&2
  exit 1
fi
info "web root: ${WEB_DEST}"

# Re-sign ad-hoc after mutating the bundle so the added Resources are covered
# and Gatekeeper doesn't reject a bundle whose seal no longer matches.
step "Re-signing (ad-hoc)"
codesign --force --deep --sign - "${APP}"

step "Packaging DMG"
mkdir -p "${DIST_DIR}"
DMG="${DIST_DIR}/PoorDeck-${VERSION}.dmg"
rm -f "${DMG}"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
cp -R "${APP}" "${STAGE}/PoorDeck.app"
ln -s /Applications "${STAGE}/Applications"

hdiutil create \
  -volname "PoorDeck ${VERSION}" \
  -srcfolder "${STAGE}" \
  -ov -format UDZO \
  "${DMG}" >/dev/null

step "Done"
info "dmg    : ${DMG}"
info "size   : $(du -h "${DMG}" | cut -f1)"
info "version: ${VERSION}"

# Expose the path to a GitHub Actions job when running in CI.
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "dmg=${DMG}"
    echo "version=${VERSION}"
  } >> "${GITHUB_OUTPUT}"
fi
