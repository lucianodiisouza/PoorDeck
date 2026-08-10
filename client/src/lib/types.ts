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

export type Modifier = "command" | "shift" | "option" | "control";

export interface Shortcut {
  key: string;
  modifiers: Modifier[];
}

export type VolumeTarget = "system";

export interface Action {
  kind: "openApp" | "keyShortcut" | "volume" | "none";
  bundleId?: string | null;
  shortcut?: Shortcut | null;
  /** For `volume` controls: which audio target this control drives. */
  target?: VolumeTarget | null;
}

export interface Theme {
  background: string;
  surface: string;
  text: string;
  accent: string;
  radius: number;
}

/// Per-app audio snapshot. The id is an opaque string (CoreAudio
/// AudioObjectID on the server). `volume` is 0..2 (2 = boost).
export interface AudioApp {
  id: string;
  name: string;
  icon?: string | null;
  playing: boolean;
  volume: number;
  muted: boolean;
}

// server -> client
export type ServerMessage =
  | { type: "layout"; data: Layout }
  | { type: "ack"; buttonId: string; ok: boolean }
  | { type: "volume"; target: VolumeTarget; value: number }
  | { type: "apps"; list: AudioApp[] }
  | { type: "appVolume"; id: string; volume: number; muted: boolean };

// client -> server
export type ClientMessage =
  | { type: "hello"; name?: string }
  | { type: "press"; buttonId: string }
  | { type: "volume"; target: VolumeTarget; value: number }
  | { type: "setAppVolume"; id: string; value: number; muted: boolean };
