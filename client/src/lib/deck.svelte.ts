import type { ClientMessage, Layout, ServerMessage } from "./types";

type Status = "connecting" | "open" | "closed";

// Reactive deck state, shared across components (Svelte 5 module runes).
export const deck = $state<{
  status: Status;
  layout: Layout | null;
  lastAck: { buttonId: string; ok: boolean } | null;
}>({
  status: "connecting",
  layout: null,
  lastAck: null,
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
