// Wire protocol shared with the desktop server. Keep in sync with
// desktop/Sources/WebDeck/Model/Protocol.swift.

export interface Layout {
  pages: Page[];
  theme: Theme;
}

export interface Page {
  id: string;
  name: string;
  columns: number;
  buttons: Button[];
}

export interface Button {
  id: string;
  label: string;
  icon?: string | null; // PNG data URL
  symbol?: string | null; // SF-symbol-style fallback name
  action: Action;
}

export interface Action {
  kind: "openApp" | "none";
  bundleId?: string | null;
}

export interface Theme {
  background: string;
  surface: string;
  text: string;
  accent: string;
  radius: number;
}

// server -> client
export type ServerMessage =
  | { type: "layout"; data: Layout }
  | { type: "ack"; buttonId: string; ok: boolean };

// client -> server
export type ClientMessage =
  | { type: "hello"; name?: string }
  | { type: "press"; buttonId: string };
