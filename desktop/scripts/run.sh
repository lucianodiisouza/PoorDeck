#!/usr/bin/env bash
#
# run.sh — build the Svelte client + the PoorDeck macOS app, then launch it.
#
# For fast iteration the app is pointed at the client's built `dist/` via the
# POORDECK_WEBROOT env var, so you don't need to re-bundle the web assets into
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

step "Building PoorDeck.app"
xcodebuild \
  -project PoorDeck.xcodeproj \
  -scheme PoorDeck \
  -configuration Debug \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build

APP="${BUILD_DIR}/Build/Products/Debug/PoorDeck.app"
step "Launching ${APP}"
# Kill any previous instance so the port frees up.
pkill -f "PoorDeck.app/Contents/MacOS/PoorDeck" 2>/dev/null || true
POORDECK_WEBROOT="${CLIENT_DIR}/dist" open -n "${APP}" --env POORDECK_WEBROOT="${CLIENT_DIR}/dist"

step "PoorDeck launched. Look for the grid icon in your menu bar."
