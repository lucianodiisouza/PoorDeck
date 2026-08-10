import type { ClientMessage, Layout, ServerMessage, VolumeTarget } from "./types";

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

// Reactive deck state, shared across components (Svelte 5 module runes).
export const deck = $state<{
  status: Status;
  layout: Layout | null;
  lastAck: { buttonId: string; ok: boolean } | null;
  /// Latest system volume (0…1). Updated from the server, seeded on connect.
  systemVolume: number | null;
}>({
  status: "connecting",
  layout: null,
  lastAck: null,
  systemVolume: null,
});

let socket: WebSocket | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;

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
    send({ type: "hello", name: navigator.userAgent });
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

export function press(buttonId: string): void {
  send({ type: "press", buttonId });
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
