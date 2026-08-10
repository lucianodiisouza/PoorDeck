<h1 align="center">WebDeck</h1>

<p align="center">
  <em>A Stream-Deck-style control surface for your Mac — driven from your phone,
  tablet, or any browser on the same Wi-Fi.</em>
</p>

WebDeck is two projects:

- **`desktop/`** — a macOS menu-bar app (SwiftUI) that *is* the server. It hosts
  the client, executes the actions, and holds the configuration.
- **`client/`** — a Svelte + Vite web app the desktop serves. It's a thin
  renderer: it draws the pages and sends button presses over a WebSocket.

You install the desktop app on your Mac, then pair a device by scanning a QR
code (or typing the URL). Same Wi-Fi is all it needs.

## Architecture

```
┌──────────────── Mac ────────────────┐        ┌──── phone / tablet / web ────┐
│  WebDeck.app (menu bar + config)     │  http  │  Svelte client                │
│  • HTTP + WebSocket server (native)  │◀──────▶│  • renders pages              │
│  • Bonjour  _webdeck._tcp            │   ws   │  • swipe to switch page       │
│  • executes: open/switch app …       │        │  • tap to fire an action      │
└──────────────────────────────────────┘        └───────────────────────────────┘
```

The server is built on **Network.framework** — no third-party dependencies. The
HTTP server serves the built client and upgrades `/ws` to a WebSocket that
speaks the JSON protocol in `desktop/…/Model/Protocol.swift` (mirrored in
`client/src/lib/types.ts`).

## Status: spike

This first cut proves the risky end-to-end path:

- [x] Desktop serves the client + pairs via QR / URL
- [x] WebSocket protocol, full-layout push on connect
- [x] Tap a button → open / switch the target Mac app (with its real icon)
- [x] Swipe between pages
- [x] Keyboard-shortcut actions (CGEvent + Accessibility)
- [x] System volume slider + mute (master output, live updates both ways)
- [x] Per-app volume — Core Audio process taps drive a live list of apps
      playing audio on the Volume page (icons + horizontal sliders + mute).
      Boost up to 2× and per-app mute. Built on the same process-tap
      pipeline that powers [Voulum](https://github.com/lucianodiisouza/voulum).
- [ ] Page / button / theme editors in the desktop config window
- [ ] Persisted configuration

## Run it

Requires Xcode, [xcodegen](https://github.com/yonyz/XcodeGen) (`brew install
xcodegen`), and Node.

```bash
desktop/scripts/run.sh
```

That builds the client, generates + builds the app, and launches it. Look for
the grid icon in the menu bar; open **configuration** to see the QR code, then
scan it from a device on the same network.

### Client dev server (hot reload)

For UI iteration you can run Vite directly, but the WebSocket needs the desktop
app running to connect to:

```bash
cd client && npm run dev
```
