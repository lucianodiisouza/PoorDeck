#!/usr/bin/env bash
#
# clean.sh — wipe every trace of PoorDeck from this Mac for a fresh start.
#
# Removes: running instances, built .app bundles (run.sh's build/ and Xcode's
# DerivedData), any installed copies in /Applications and ~/Applications, the
# persisted layout in Application Support, the preferences domain, and saved
# window state. This DELETES your saved layout — the next launch reseeds the
# default deck.
#
# Pass --dry-run to see what would be removed without touching anything.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESKTOP_DIR="${REPO_ROOT}/desktop"
BUNDLE_ID="dev.oprimo.poordeck.app"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

step() { printf '\033[1;34m▸\033[0m %s\n' "$1"; }
gone() { printf '  \033[0;32m✓ removed\033[0m %s\n' "$1"; }
skip() { printf '  \033[0;90m· absent \033[0m %s\n' "$1"; }

# Remove a path, reporting whether it was there. Honors --dry-run.
rm_path() {
  local p="$1"
  if [ -e "$p" ] || [ -L "$p" ]; then
    if $DRY_RUN; then printf '  \033[0;33m· would remove\033[0m %s\n' "$p"
    else rm -rf "$p"; gone "$p"; fi
  else
    skip "$p"
  fi
}

step "Stopping running PoorDeck instances"
if pgrep -f "PoorDeck.app/Contents/MacOS/PoorDeck" >/dev/null 2>&1; then
  $DRY_RUN || pkill -f "PoorDeck.app/Contents/MacOS/PoorDeck" || true
  echo "  stopped running instance(s)"
else
  echo "  none running"
fi

step "Removing built app bundles"
rm_path "${DESKTOP_DIR}/build"
# Xcode default DerivedData copies (hash suffix varies).
shopt -s nullglob
for d in "${HOME}/Library/Developer/Xcode/DerivedData/"PoorDeck-*; do
  rm_path "$d"
done
shopt -u nullglob

step "Removing installed app copies"
rm_path "/Applications/PoorDeck.app"
rm_path "${HOME}/Applications/PoorDeck.app"

step "Removing persisted data & preferences"
rm_path "${HOME}/Library/Application Support/PoorDeck"
# defaults delete is a no-op (nonzero) when the domain is absent; guard it.
if defaults read "${BUNDLE_ID}" >/dev/null 2>&1; then
  if $DRY_RUN; then printf '  \033[0;33m· would remove\033[0m preferences domain %s\n' "${BUNDLE_ID}"
  else defaults delete "${BUNDLE_ID}" || true; gone "preferences domain ${BUNDLE_ID}"; fi
else
  skip "preferences domain ${BUNDLE_ID}"
fi
rm_path "${HOME}/Library/Preferences/${BUNDLE_ID}.plist"
rm_path "${HOME}/Library/Saved Application State/${BUNDLE_ID}.savedState"

step "Scanning for any stray PoorDeck.app copies (reported, not deleted)"
STRAY=$(mdfind -name "PoorDeck.app" 2>/dev/null || true)
if [ -n "$STRAY" ]; then
  echo "$STRAY" | sed 's/^/  • /'
  echo "  (remove these manually if they shouldn't be there)"
else
  echo "  none found"
fi

$DRY_RUN && step "Dry run — nothing was deleted." || step "Clean complete."
