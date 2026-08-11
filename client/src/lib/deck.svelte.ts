import type {
  AudioApp,
  ClientMessage,
  Layout,
  RunningApp,
  ServerMessage,
  VolumeTarget,
} from "./types";

type Status = "connecting" | "open" | "closed";

/// Per-target "last value we sent". Incoming server messages whose value
/// matches our last write are treated as echoes of our own action and
/// dropped, so the slider doesn't fight itself while dragging. External
/// changes (menu bar, keyboard, another client) won't equal our last write
/// (with reasonable float precision) and are accepted.
const lastSent: Record<VolumeTarget, number | null> = {
  system: null,
};

function isEcho(target: VolumeTarget, value: number): boolean {
  const last = lastSent[target];
  if (last == null) return false;
  return Math.abs(last - value) < 0.005;
}

/// Per-app "last value we sent". Keyed by app id, so dragging one app's
/// slider doesn't interfere with another's echo detection.
const lastAppSent = new Map<string, { value: number; muted: boolean }>();
function isAppEcho(id: string, value: number, muted: boolean): boolean {
  const last = lastAppSent.get(id);
  if (!last) return false;
  return Math.abs(last.value - value) < 0.005 && last.muted === muted;
}

// Reactive deck state, shared across components (Svelte 5 module runes).
export const deck = $state<{
  status: Status;
  layout: Layout | null;
  lastAck: { buttonId: string; ok: boolean } | null;
  /// Latest system volume (0…1). Updated from the server, seeded on connect.
  systemVolume: number | null;
  /// List of audio apps the server currently sees. Replaced wholesale on
  /// every `apps` message; a per-app `appVolume` updates the matching row.
  apps: AudioApp[];
  /// Running apps for the Dock page. Replaced wholesale on every `dock`
  /// message (launch / quit / frontmost change).
  dock: RunningApp[];
}>({
  status: "connecting",
  layout: null,
  lastAck: null,
  systemVolume: null,
  apps: [],
  dock: [],
});

let socket: WebSocket | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;

/// A stable per-device id. Persisted in localStorage so a reload, a
/// reconnect, or the PWA's service worker all report the *same* device —
/// that's how the desktop counts one phone as one device instead of two or
/// three. Generated once and reused forever.
function deviceId(): string {
  const key = "poordeck.deviceId";
  try {
    let id = localStorage.getItem(key);
    if (!id) {
      id =
        typeof crypto !== "undefined" && crypto.randomUUID
          ? crypto.randomUUID()
          : `dev-${Date.now()}-${Math.random().toString(36).slice(2)}`;
      localStorage.setItem(key, id);
    }
    return id;
  } catch {
    // Private mode / storage disabled — fall back to a per-session id.
    return `dev-${Math.random().toString(36).slice(2)}`;
  }
}

function wsURL(): string {
  const proto = location.protocol === "https:" ? "wss" : "ws";
  return `${proto}://${location.host}/ws`;
}

export function connect(): void {
  deck.status = "connecting";
  const ws = new WebSocket(wsURL());
  socket = ws;

  ws.onopen = () => {
    deck.status = "open";
    send({ type: "hello", name: navigator.userAgent, deviceId: deviceId() });
    // Report viewport orientation so the editor's "Follow device"
    // preview can mirror it. Re-sent on every resize/orientationchange.
    sendDeviceOrientation();
  };

  ws.onmessage = (event) => {
    let msg: ServerMessage;
    try {
      msg = JSON.parse(event.data);
    } catch {
      return;
    }
    if (msg.type === "layout") {
      deck.layout = msg.data;
    } else if (msg.type === "ack") {
      deck.lastAck = { buttonId: msg.buttonId, ok: msg.ok };
    } else if (msg.type === "volume") {
      if (isEcho(msg.target, msg.value)) return;
      if (msg.target === "system") {
        deck.systemVolume = msg.value;
      }
    } else if (msg.type === "apps") {
      deck.apps = msg.list;
    } else if (msg.type === "dock") {
      deck.dock = msg.list;
    } else if (msg.type === "appVolume") {
      if (isAppEcho(msg.id, msg.volume, msg.muted)) return;
      const idx = deck.apps.findIndex((a) => a.id === msg.id);
      if (idx < 0) {
        // We don't have this app yet (e.g. it just started playing). It'll
        // come in the next full `apps` snapshot.
        return;
      }
      // Replace the row immutably so Svelte picks up the change.
      deck.apps = deck.apps.map((a, i) =>
        i === idx ? { ...a, volume: msg.volume, muted: msg.muted } : a,
      );
    }
  };

  ws.onclose = () => {
    deck.status = "closed";
    socket = null;
    scheduleReconnect();
  };

  ws.onerror = () => ws.close();
}

function scheduleReconnect(): void {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, 1500);
}

function send(message: ClientMessage): void {
  if (socket?.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}

function sendDeviceOrientation(): void {
  if (typeof window === "undefined") return;
  // `screen.orientation.type` is the reliable API on iOS Safari — the
  // `(orientation: portrait)` media query is unreliable on iOS (Safari
  // sometimes keeps reporting portrait regardless of actual orientation
  // and only fires `orientationchange` on full flips). Fall back to the
  // media query on browsers that don't expose `screen.orientation`.
  let isPortrait: boolean;
  const so = (screen as Screen & { orientation?: { type: string } }).orientation;
  if (so?.type) {
    isPortrait = so.type.startsWith("portrait");
  } else {
    isPortrait = window.matchMedia("(orientation: portrait)").matches;
  }
  send({ type: "deviceOrientation", isPortrait });
}

// Re-send the orientation every time the user rotates the device or
// resizes the window. The editor's "Follow device" preview mode reads
// the latest value, so this keeps the canvas in sync without any
// extra round-trip.
if (typeof window !== "undefined") {
  window.addEventListener("resize", sendDeviceOrientation);
  window.addEventListener("orientationchange", sendDeviceOrientation);
  // `screen.orientation` fires its own change event with the resolved
  // type — most reliable on iOS Safari, where the resize event can be
  // debounced or skipped during a rotation animation.
  const so = (screen as Screen & { orientation?: EventTarget }).orientation;
  so?.addEventListener?.("change", sendDeviceOrientation);
}

export function press(buttonId: string): void {
  send({ type: "press", buttonId });
}

/// Bring a running app to the front (or launch it) from the Dock page.
export function activateApp(bundleId: string): void {
  send({ type: "activateApp", bundleId });
}

/// Push a new target value to the server. Records the value so the round-trip
/// echo can be recognized and dropped. Called on every slider input event.
export function setVolume(target: VolumeTarget, value: number): void {
  const clamped = Math.max(0, Math.min(1, value));
  lastSent[target] = clamped;
  send({ type: "volume", target, value: clamped });
}

/// Toggle the system volume between the last known level and 0. Used by the
/// mute button on the volume page.
export function toggleMuteSystem(): void {
  const current = deck.systemVolume ?? 0;
  const next = current > 0.001 ? 0 : 0.6;
  setVolume("system", next);
}

/// Set a per-app volume + mute. Records the values so the round-trip echo
/// can be recognized and dropped. `value` is 0..2 (boost allowed).
export function setAppVolume(id: string, value: number, muted: boolean): void {
  const clamped = Math.max(0, Math.min(2, value));
  lastAppSent.set(id, { value: clamped, muted });
  send({ type: "setAppVolume", id, value: clamped, muted });
}

/// Toggle the per-app mute without changing the slider value. Sends 0 gain
/// (muted) or restores the last volume when unmuting.
export function toggleAppMute(id: string): void {
  const app = deck.apps.find((a) => a.id === id);
  if (!app) return;
  if (app.muted) {
    // Restore: 1.0 is a safe default if we don't have a stored value.
    setAppVolume(id, app.volume > 0 ? app.volume : 1, false);
  } else {
    setAppVolume(id, app.volume, true);
  }
}
