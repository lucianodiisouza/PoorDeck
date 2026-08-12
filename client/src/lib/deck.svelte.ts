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
let keepaliveTimer: ReturnType<typeof setInterval> | null = null;

/// How often the client pings while connected. iOS Safari reclaims/reloads an
/// idle `apple-mobile-web-app` page that has no JS/network activity — with the
/// app being purely event-driven, an idle deck (nothing happening on the Mac)
/// sat completely silent and iOS reload-looped it forever. A few seconds of
/// heartbeat is enough to keep the page alive; the message also refreshes the
/// server's liveness tracking.
const KEEPALIVE_MS = 3000;

/// If we send pings but hear *nothing* back for this long, the socket is
/// considered silently dead and we reconnect. The server answers every `ping`
/// with a `pong`, so on a healthy LAN connection this resets every few
/// seconds; only a genuinely one-way-dead socket (the classic iOS
/// backgrounded-then-foregrounded case, where `readyState` still lies "OPEN")
/// ages past the deadline. Set to tolerate two missed pongs.
const LIVENESS_TIMEOUT_MS = 8000;
/// Timestamp of the last inbound frame (any server message, including `pong`).
/// Any traffic proves the socket is alive, not just the pong.
let lastInboundAt = 0;

function startKeepalive(): void {
  stopKeepalive();
  lastInboundAt = Date.now(); // grace period: assume alive right after open
  keepaliveTimer = setInterval(() => {
    if (socket?.readyState !== WebSocket.OPEN) return;
    if (Date.now() - lastInboundAt > LIVENESS_TIMEOUT_MS) {
      // Pings went unanswered past the deadline — the socket is dead despite
      // reporting OPEN. Stop trusting it and reconnect from scratch.
      reconnectNow();
      return;
    }
    send({ type: "ping" });
  }, KEEPALIVE_MS);
}

function stopKeepalive(): void {
  if (keepaliveTimer) {
    clearInterval(keepaliveTimer);
    keepaliveTimer = null;
  }
}

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
    reconnectAttempt = 0;
    send({ type: "hello", name: navigator.userAgent, deviceId: deviceId() });
    // Report viewport orientation so the editor's "Follow device"
    // preview can mirror it. Re-sent on every resize/orientationchange.
    sendDeviceOrientation();
    // Keep the page from being reclaimed by iOS while idle (see KEEPALIVE_MS).
    startKeepalive();
  };

  ws.onmessage = (event) => {
    let msg: ServerMessage;
    try {
      msg = JSON.parse(event.data);
    } catch {
      return;
    }
    // Any inbound frame proves the socket is alive; refresh the liveness clock
    // the keepalive checks against.
    lastInboundAt = Date.now();
    if (msg.type === "pong") {
      // Liveness-only; the timestamp bump above is its entire purpose.
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
    stopKeepalive();
    scheduleReconnect();
  };

  ws.onerror = () => ws.close();
}

/// Backoff for *passive* reconnects (an unexpected `onclose`). The first
/// retry is near-instant so a brief Wi-Fi blip recovers without the user
/// noticing; it then settles to a steady interval. Reset to 0 on every
/// successful open.
const RECONNECT_BACKOFF_MS = [300, 800, 1500];
let reconnectAttempt = 0;

function scheduleReconnect(): void {
  if (reconnectTimer) return;
  const delay =
    RECONNECT_BACKOFF_MS[Math.min(reconnectAttempt, RECONNECT_BACKOFF_MS.length - 1)];
  reconnectAttempt += 1;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, delay);
}

/// Force a fresh connection right now, discarding any existing socket.
///
/// This is the cure for the iOS foreground race: when an installed PWA (or a
/// Safari tab) is backgrounded, WebKit freezes the page — timers stop and the
/// TCP socket dies without ever firing `onclose`. On return the stale socket
/// frequently still reports `readyState === OPEN`, so we cannot trust it and
/// must not wait for a reconnect that will never be scheduled. We detach the
/// old socket's handlers (so its late `onclose` can't race a second connect),
/// drop it, and reconnect immediately. The desktop dedups by `deviceId` and
/// reaps the old socket via its heartbeat, so replacing a possibly-live socket
/// is cheap and safe.
function reconnectNow(): void {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  reconnectAttempt = 0;
  if (socket) {
    socket.onclose = null;
    socket.onerror = null;
    try {
      socket.close();
    } catch {
      /* already closing/closed */
    }
    socket = null;
  }
  stopKeepalive();
  connect();
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

  // Foreground recovery. iOS freezes a backgrounded page (installed PWA or
  // Safari tab): its socket dies without firing `onclose` and the frozen
  // reconnect timer never runs, so on return the deck can be silently dead
  // while `readyState` still lies "OPEN". Instead of waiting for a reconnect
  // that will never be scheduled, we act on the page becoming visible again.
  if (typeof document !== "undefined") {
    // If we were hidden longer than this, assume iOS killed the connection
    // and reconnect unconditionally (a stale socket often still reads OPEN).
    // Shorter app-switches with a genuinely-open socket are left untouched.
    const STALE_AFTER_HIDDEN_MS = 10_000;
    let hiddenSince: number | null = null;

    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "hidden") {
        hiddenSince = Date.now();
        return;
      }
      const hiddenMs = hiddenSince ? Date.now() - hiddenSince : 0;
      hiddenSince = null;
      // A handshake already in flight — let it finish.
      if (socket?.readyState === WebSocket.CONNECTING) return;
      const open = socket?.readyState === WebSocket.OPEN;
      if (!open || hiddenMs > STALE_AFTER_HIDDEN_MS) reconnectNow();
    });
  }

  // bfcache restore (Back/forward or returning to a frozen tab): the page is
  // resurrected with its old, now-dead socket. Always start fresh.
  window.addEventListener("pageshow", (event) => {
    if ((event as PageTransitionEvent).persisted) reconnectNow();
  });
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
