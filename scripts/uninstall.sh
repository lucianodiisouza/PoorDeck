#!/usr/bin/env bash
#
# uninstall.sh — wipe every trace of PoorDeck from this Mac.
#
# Removes, in order:
#   • running instances
#   • the repo's build output (desktop/build) and Xcode DerivedData copies
#   • installed app bundles in /Applications and ~/Applications
#   • persisted data in ~/Library/Application Support/PoorDeck (your saved
#     layout, themes) — the next launch reseeds the default deck
#   • the preferences domain and saved window state
#
# It then reports (but does NOT delete) any stray PoorDeck.app copies found
# elsewhere via Spotlight, so you can decide about those yourself.
#
# NOTE: This does not revoke the Accessibility / Audio permissions macOS has
# granted — those live in the TCC database and can only be removed from
# System Settings ▸ Privacy & Security. The script prints a reminder.
#
# Flags:
#   --dry-run   Show what would be removed without touching anything.
#   --yes       Skip the confirmation prompt.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP_DIR="${REPO_ROOT}/desktop"
BUNDLE_ID="dev.oprimo.poordeck.app"

DRY_RUN=false
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --yes|-y)  ASSUME_YES=true ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

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

if ! $DRY_RUN && ! $ASSUME_YES; then
  printf '\033[1;33mThis deletes your saved PoorDeck layout, themes, and preferences.\033[0m\n'
  read -r -p "Continue? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

step "Stopping running PoorDeck instances"
if pgrep -f "PoorDeck.app/Contents/MacOS/PoorDeck" >/dev/null 2>&1; then
  $DRY_RUN || pkill -f "PoorDeck.app/Contents/MacOS/PoorDeck" || true
  echo "  stopped running instance(s)"
else
  echo "  none running"
fi

step "Removing built app bundles"
rm_path "${DESKTOP_DIR}/build"
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
# `defaults delete` errors when the domain is absent, so guard it.
if defaults read "${BUNDLE_ID}" >/dev/null 2>&1; then
  if $DRY_RUN; then printf '  \033[0;33m· would remove\033[0m preferences domain %s\n' "${BUNDLE_ID}"
  else defaults delete "${BUNDLE_ID}" >/dev/null 2>&1 || true; gone "preferences domain ${BUNDLE_ID}"; fi
else
  skip "preferences domain ${BUNDLE_ID}"
fi
rm_path "${HOME}/Library/Preferences/${BUNDLE_ID}.plist"
rm_path "${HOME}/Library/Saved Application State/${BUNDLE_ID}.savedState"

step "Scanning for stray PoorDeck.app copies (reported, not deleted)"
STRAY=$(mdfind -name "PoorDeck.app" 2>/dev/null || true)
if [ -n "$STRAY" ]; then
  echo "$STRAY" | sed 's/^/  • /'
  echo "  (remove these manually if they shouldn't be there)"
else
  echo "  none found"
fi

step "Reminder: macOS permissions are not removed automatically"
echo "  System Settings ▸ Privacy & Security ▸ Accessibility  → remove PoorDeck"
echo "  System Settings ▸ Privacy & Security ▸ Microphone/Audio → remove PoorDeck"

$DRY_RUN && step "Dry run — nothing was deleted." || step "Uninstall complete."
