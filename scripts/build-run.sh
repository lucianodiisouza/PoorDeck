#!/usr/bin/env bash
#
# build-run.sh — build the Svelte client + the PoorDeck macOS app from source,
# stop every running copy, and launch the binary you just built.
#
# The whole point of this script is to remove the "am I actually running the
# latest build?" doubt:
#   • It always rebuilds both the client bundle and the .app.
#   • It kills EVERY running PoorDeck instance first, so no stale process
#     survives and keeps the port.
#   • It launches the freshly built bundle by explicit path (never a copy that
#     happens to be installed in /Applications), and prints that bundle's
#     version + build time + git commit so you can see it's the current one.
#
# Flags:
#   --release   Build the Release configuration instead of Debug.
#   --no-open   Build only; don't launch (useful for CI / a quick compile check).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP_DIR="${REPO_ROOT}/desktop"
CLIENT_DIR="${REPO_ROOT}/client"
BUILD_DIR="${DESKTOP_DIR}/build"

CONFIG="Debug"
DO_OPEN=true
for arg in "$@"; do
  case "$arg" in
    --release) CONFIG="Release" ;;
    --no-open) DO_OPEN=false ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

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

step "Stopping every running PoorDeck instance"
if pgrep -f "PoorDeck.app/Contents/MacOS/PoorDeck" >/dev/null 2>&1; then
  pkill -f "PoorDeck.app/Contents/MacOS/PoorDeck" || true
  # Give the old process a moment to release the listening port.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "PoorDeck.app/Contents/MacOS/PoorDeck" >/dev/null 2>&1 || break
    sleep 0.3
  done
  info "stopped previous instance(s)"
else
  info "none were running"
fi

# Report exactly what we're about to run so "is this the latest?" is answerable.
step "This is the build you're about to run"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "${APP}/Contents/Info.plist" 2>/dev/null || echo '?')"
BUILDNO="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "${APP}/Contents/Info.plist" 2>/dev/null || echo '?')"
BUILT_AT="$(date -r "${BIN}" '+%Y-%m-%d %H:%M:%S')"
GIT_COMMIT="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
GIT_DIRTY=""
git -C "${REPO_ROOT}" diff --quiet 2>/dev/null || GIT_DIRTY=" (+uncommitted changes)"
info "bundle : ${APP}"
info "version: ${VERSION} (build ${BUILDNO})"
info "binary : compiled ${BUILT_AT}"
info "commit : ${GIT_COMMIT}${GIT_DIRTY}"

# Warn if a *different* PoorDeck.app is installed system-wide — launching by
# explicit path below avoids it, but it's worth knowing it exists.
for other in "/Applications/PoorDeck.app" "${HOME}/Applications/PoorDeck.app"; do
  [ -e "$other" ] && info "note: another copy exists at ${other} (not launched)"
done

if ! $DO_OPEN; then
  step "Built only (--no-open). Not launching."
  exit 0
fi

step "Launching the freshly built bundle"
# Explicit path + --env keeps the app pointed at the client we just built,
# and -n forces a new instance of *this* bundle specifically.
POORDECK_WEBROOT="${CLIENT_DIR}/dist" \
  open -n "${APP}" --env POORDECK_WEBROOT="${CLIENT_DIR}/dist"

info "Look for the grid icon in your menu bar."
