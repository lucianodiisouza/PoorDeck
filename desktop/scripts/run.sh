#!/usr/bin/env bash
#
# run.sh — build the Svelte client + the WebDeck macOS app, then launch it.
#
# For fast iteration the app is pointed at the client's built `dist/` via the
# WEBDECK_WEBROOT env var, so you don't need to re-bundle the web assets into
# the .app on every change.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESKTOP_DIR="${REPO_ROOT}/desktop"
CLIENT_DIR="${REPO_ROOT}/client"
BUILD_DIR="${DESKTOP_DIR}/build"

step() { printf '\033[1;34m▸\033[0m %s\n' "$1"; }

step "Building Svelte client"
cd "${CLIENT_DIR}"
[ -d node_modules ] || npm install
npm run build

step "Generating Xcode project"
cd "${DESKTOP_DIR}"
xcodegen generate

step "Building WebDeck.app"
xcodebuild \
  -project WebDeck.xcodeproj \
  -scheme WebDeck \
  -configuration Debug \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build

APP="${BUILD_DIR}/Build/Products/Debug/WebDeck.app"
step "Launching ${APP}"
# Kill any previous instance so the port frees up.
pkill -f "WebDeck.app/Contents/MacOS/WebDeck" 2>/dev/null || true
WEBDECK_WEBROOT="${CLIENT_DIR}/dist" open -n "${APP}" --env WEBDECK_WEBROOT="${CLIENT_DIR}/dist"

step "WebDeck launched. Look for the grid icon in your menu bar."
