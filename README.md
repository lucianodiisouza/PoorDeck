<h1 align="center">PoorDeck</h1>

<p align="center">
  <em>A Stream-Deck-style control surface for your Mac — driven from your phone,
  tablet, or any browser on the same Wi-Fi.</em>
</p>

PoorDeck is two projects:

- **`desktop/`** — a macOS menu-bar app (SwiftUI) that *is* the server. It hosts
  the client, executes the actions, holds the configuration, and gives you the
  editor UI for pages, buttons, and theme.
- **`client/`** — a Svelte + Vite web app the desktop serves. It's a thin
  renderer: it draws the pages and sends button presses over a WebSocket.

You install the desktop app on your Mac, then pair a device by scanning a QR
code (or typing the URL). Same Wi-Fi is all it needs — no cloud, no account.

## Architecture

```
┌──────────────── Mac ────────────────┐        ┌──── phone / tablet / web ────┐
│  PoorDeck.app (menu bar + config)    │  http  │  Svelte client                │
│  • HTTP + WebSocket server (native)  │◀──────▶│  • renders pages              │
│  • Bonjour  _poordeck._tcp           │   ws   │  • swipe to switch page       │
│  • executes actions, edits layout    │        │  • tap to fire an action      │
│  • persists layout to disk           │        │  • drives volume sliders      │
└──────────────────────────────────────┘        └───────────────────────────────┘
```

The server is built on **Network.framework** — no third-party dependencies. The
HTTP server serves the built client and upgrades `/ws` to a WebSocket that
speaks the JSON protocol in `desktop/…/Model/Protocol.swift` (mirrored in
`client/src/lib/types.ts`). On connect the server pushes the full resolved
layout (app icons baked in as data URLs); it re-pushes whenever you edit the
layout in the config window, so connected devices update live.

## What it does

- **Pairing** — the config window shows a QR code / URL for a device on the
  same network. Each device persists a stable `deviceId` in `localStorage`, so
  a reload or reconnect from the same phone counts as one device, not three.
  The config UI shows a paired badge and a live connected-device count.
- **Open / switch apps** — tap a button to launch or foreground a Mac app,
  rendered with the app's real icon.
- **Keyboard shortcuts** — post any `⌘`/`⌥`/`⌃`/`⇧` combo via CGEvent
  (needs Accessibility permission).
- **Media keys** — play/pause, next, previous, fast-forward, rewind, volume
  up/down, mute — the standard transport keys.
- **System volume** — a master-output slider + mute, live in both directions.
- **Per-app volume** — Core Audio process taps drive a live list of apps
  playing audio: icons, horizontal sliders, per-app mute, boost up to 2×.
  Built on the same process-tap pipeline that powers
  [Voulum](https://github.com/lucianodiisouza/voulum).
- **Dock page** — mirror running (and pinned) apps; tap to activate or launch.
- **Pages & orientation** — swipe between pages; per-page column counts for
  portrait and landscape, with an optional orientation lock.
- **Editors** — add/edit/delete pages and buttons and edit the theme
  (background, surface, text, accent, corner radius) right in the config
  window, with a live device preview that can follow the device's real
  orientation.
- **Persistence** — the layout is saved as JSON in
  `~/Library/Application Support/PoorDeck/layout.json` and reloaded on launch
  (seeded from a default on first run).

## Run it from source

Requires Xcode, [xcodegen](https://github.com/yonyz/XcodeGen) (`brew install
xcodegen`), and Node.

```bash
scripts/build-run.sh
```

That builds the client, generates + builds the app, kills any running copy, and
launches the freshly built bundle (printing its version, build time, and git
commit so you know it's the latest). Look for the grid icon in the menu bar;
open **configuration** to see the QR code, then scan it from a device on the
same network.

To wipe every trace of the app from your Mac — built bundles, installed copies,
saved layout, and preferences:

```bash
scripts/uninstall.sh
```

### Client dev server (hot reload)

For UI iteration you can run Vite directly, but the WebSocket needs the desktop
app running to connect to:

```bash
cd client && npm run dev
```

## Releases (DMG)

Tagged commits ship a `.dmg` via GitHub Actions
([`.github/workflows/release.yml`](.github/workflows/release.yml)).

- **Cut a release** — push a `v*` tag; the workflow builds a self-contained
  Release bundle (the client is embedded in `PoorDeck.app/Contents/Resources/web`),
  wraps it in a `.dmg`, and attaches it to a GitHub Release for that tag:

  ```bash
  git tag v0.1.0
  git push origin v0.1.0
  ```

- **First release / manual run** — trigger the workflow from the Actions tab
  ("Run workflow") and type the tag; it creates the tag's release if it doesn't
  exist yet.

- **Build a DMG locally** — same packaging, no CI:

  ```bash
  scripts/make-dmg.sh          # → dist/PoorDeck-<version>.dmg
  ```

The build is **ad-hoc signed only** — no Apple Developer ID signature or
notarization. macOS quarantines it on first launch, so open it once with
right-click ▸ **Open**, or clear the flag:

```bash
xattr -dr com.apple.quarantine /Applications/PoorDeck.app
```
