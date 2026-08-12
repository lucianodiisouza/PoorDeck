// Wire protocol shared with the desktop server. Keep in sync with
// desktop/Sources/PoorDeck/Model/Protocol.swift.

export interface Layout {
  pages: Page[];
  theme: Theme;
}

export type OrientationLock = "portrait" | "landscape";

export interface Page {
  id: string;
  name: string;
  /** Default column count. Used when columnsPortrait / columnsLandscape
   *  aren't set, so layouts saved before per-orientation columns keep
   *  working. */
  columns: number;
  /** Columns when the device is portrait. Wins over `columns` when set. */
  columnsPortrait?: number;
  /** Columns when the device is landscape. Wins over `columns` when set. */
  columnsLandscape?: number;
  /** If set, the client forces the chosen orientation regardless of
   *  what the device reports. The canvas respects the same flag. */
  orientationLock?: OrientationLock;
  buttons: Button[];
}

export interface Button {
  id: string;
  label: string;
  /** Resolved PNG data URL the server bakes in before sending (an app's own
   *  icon, or the user's custom image — see `customIcon` / `iconOverride`).
   *  Transient: authored layouts leave this null and the server fills it. */
  icon?: string | null;
  /** A user-supplied PNG data URL that travels with the layout (and with
   *  shared packs). Distinct from `icon`, which is the transient resolved
   *  slot. Used as the tile art when `iconOverride` is on, or as a fallback
   *  when an `openApp` button's target app isn't installed. */
  customIcon?: string | null;
  /** When true, the tile shows `customIcon` / `symbol` instead of the
   *  target app's own icon. Lets a user override the auto-resolved app icon
   *  with their own art. Undefined / false keeps the old behavior (app icon
   *  wins). */
  iconOverride?: boolean;
  symbol?: string | null; // SF-symbol-style fallback name
  action: Action;
}

export type Modifier = "command" | "shift" | "option" | "control";

export interface Shortcut {
  key: string;
  modifiers: Modifier[];
}

export type VolumeTarget = "system";

/** Standard system media / transport keys — the ones on the F-row / Touch Bar.
 *  They drive whatever app currently owns "Now Playing" (Music, Spotify, a
 *  browser tab…), so a single button works across every media app. */
export type MediaKey =
  | "playPause"
  | "next"
  | "previous"
  | "fastForward"
  | "rewind"
  | "mute"
  | "volumeUp"
  | "volumeDown";

export interface Action {
  kind: "openApp" | "keyShortcut" | "volume" | "media" | "none";
  bundleId?: string | null;
  shortcut?: Shortcut | null;
  /** For `volume` controls: which audio target this control drives. */
  target?: VolumeTarget | null;
  /** For `media` controls: which standard transport key this button posts. */
  mediaKey?: MediaKey | null;
}

export interface Theme {
  background: string;
  surface: string;
  text: string;
  accent: string;
  /** Button corner radius (px). 0 = squared (non-rounded) buttons. */
  radius: number;
  /** Gap between buttons (px). 0 = seamless, no-gap grid. Optional so
   *  layouts saved before it existed keep decoding; the client defaults
   *  to 12 when absent. */
  gap?: number;
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

/// An app mirrored on the Dock page. `id` is the bundle id. `running` is
/// false for pinned Dock apps that aren't open; `active` marks the frontmost.
export interface RunningApp {
  id: string;
  name: string;
  icon?: string | null;
  running: boolean;
  active: boolean;
}

// server -> client
export type ServerMessage =
  | { type: "layout"; data: Layout }
  | { type: "ack"; buttonId: string; ok: boolean }
  | { type: "volume"; target: VolumeTarget; value: number }
  | { type: "apps"; list: AudioApp[] }
  | { type: "dock"; list: RunningApp[] }
  | { type: "appVolume"; id: string; volume: number; muted: boolean }
  // Reply to the client's `ping`. Used purely to prove the socket is alive
  // end-to-end; a missing pong past the liveness deadline means the
  // connection has silently died (common on iOS after backgrounding).
  | { type: "pong" };

// client -> server
export type ClientMessage =
  | { type: "hello"; name?: string; deviceId?: string }
  | { type: "ping" }
  | { type: "press"; buttonId: string }
  | { type: "volume"; target: VolumeTarget; value: number }
  | { type: "setAppVolume"; id: string; value: number; muted: boolean }
  | { type: "activateApp"; bundleId: string }
  // Reports the client's current viewport orientation. Drives the editor's
  // "Follow device" preview. Decoded by the desktop as `deviceOrientation`.
  | { type: "deviceOrientation"; isPortrait: boolean };
