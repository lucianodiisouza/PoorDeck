import Foundation

/// Wire protocol shared with the Svelte client. Keep these shapes in sync with
/// `client/src/lib/types.ts`.
///
/// Everything travels as JSON text frames over the WebSocket. The desktop is the
/// source of truth: it pushes the full `Layout` on connect and executes the
/// actions the client asks for.

// MARK: Layout (server -> client)

struct Layout: Codable, Equatable {
    var pages: [Page]
    var theme: Theme
}

struct Page: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// Column count the client uses to lay the grid out. Kept as a
    /// fallback for layouts saved before per-orientation columns
    /// existed — `columnsPortrait` / `columnsLandscape` win when
    /// they're present.
    var columns: Int
    /// Column count when the device is in portrait. When nil, falls
    /// back to `columns` so existing layouts keep working.
    var columnsPortrait: Int?
    /// Column count when the device is in landscape. When nil,
    /// falls back to `columns` (or `columnsPortrait` as a last resort).
    var columnsLandscape: Int?
    /// If set, the client forces the chosen orientation regardless of
    /// what the device sensor reports. The canvas respects the same
    /// flag so the preview matches what the user will actually see.
    /// `nil` means "follow device orientation".
    var orientationLock: OrientationLock?
    var buttons: [DeckButton]

    /// The column count the client should use, given a viewport
    /// orientation. Centralizes the portrait/landscape lookup so the
    /// editor, the canvas, and the client all read the same logic.
    func columns(forPortrait isPortrait: Bool) -> Int {
        if isPortrait, let c = columnsPortrait { return c }
        if !isPortrait, let c = columnsLandscape { return c }
        return columns
    }
}

enum OrientationLock: String, Codable, Equatable {
    case portrait
    case landscape
}

/// Named `DeckButton` (not `Button`) to avoid colliding with SwiftUI.Button in
/// the desktop UI. Serializes the same shape as the client's `Button` type.
struct DeckButton: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    /// PNG data URL (e.g. the app's own icon), when we have one.
    var icon: String?
    /// SF-Symbol-style fallback name the client maps to its own glyphs.
    var symbol: String?
    var action: Action
}

struct Action: Codable, Equatable {
    enum Kind: String, Codable {
        case openApp      // launch or bring an app to the front
        case keyShortcut  // post a keyboard shortcut (e.g. ⌘↵)
        case volume       // a non-tap control bound to system volume
        case media        // a standard media/transport key (play/pause, next…)
        case none         // placeholder / not wired yet
    }
    var kind: Kind
    /// Bundle id. For `openApp` it's the target; for `keyShortcut` it's an
    /// optional app to bring to the front before the keys are sent (nil = send
    /// to whatever's already focused). Reserved / unused for `volume` / `media`.
    var bundleId: String?
    /// The keystroke for `keyShortcut`.
    var shortcut: Shortcut?
    /// For `volume` controls: which audio target this control drives. Right now
    /// we only ship `system` (the default output device). Per-app volume needs
    /// the process-tap engine mentioned in the README and is intentionally not
    /// modeled yet — `target` is forward-compatible.
    var target: VolumeTarget?
    /// For `media` controls: which standard transport key this button posts.
    /// These are the system-wide media keys (the ones on the F-row / Touch Bar),
    /// so they drive whatever app currently owns "Now Playing" — Music,
    /// Spotify, a browser tab, etc.
    var mediaKey: MediaKey? = nil
}

/// A standard system media / transport key. Posted as an NSSystem-defined
/// event by `MediaKeyEmitter`, so it reaches the current Now Playing app the
/// same way the hardware keys do. Raw values are the IOKit `NX_KEYTYPE_*`
/// codes the emitter feeds to the HID event.
enum MediaKey: String, Codable {
    case playPause    // NX_KEYTYPE_PLAY (16)
    case next         // NX_KEYTYPE_NEXT (17)
    case previous     // NX_KEYTYPE_PREVIOUS (18)
    case fastForward  // NX_KEYTYPE_FAST (19)
    case rewind       // NX_KEYTYPE_REWIND (20)
    case mute         // NX_KEYTYPE_MUTE (7)
    case volumeUp     // NX_KEYTYPE_SOUND_UP (0)
    case volumeDown   // NX_KEYTYPE_SOUND_DOWN (1)

    /// The IOKit `NX_KEYTYPE_*` code fed to the system-defined HID event.
    var nxKeyCode: Int32 {
        switch self {
        case .volumeUp: return 0
        case .volumeDown: return 1
        case .mute: return 7
        case .playPause: return 16
        case .next: return 17
        case .previous: return 18
        case .fastForward: return 19
        case .rewind: return 20
        }
    }
}

enum VolumeTarget: String, Codable {
    case system
}

/// A keyboard shortcut, described by layout-independent key name + modifiers.
/// e.g. ⌘↵ = Shortcut(key: "return", modifiers: [.command]).
struct Shortcut: Codable, Equatable {
    enum Modifier: String, Codable {
        case command, shift, option, control
    }
    /// Key name resolved to a virtual keycode by `KeyEmitter` (letters, digits,
    /// "return", "space", "tab", "escape", arrows, "f1"…"f12", etc.).
    var key: String
    var modifiers: [Modifier]
}

struct Theme: Codable, Equatable {
    var background: String
    var surface: String
    var text: String
    var accent: String
    /// Corner radius (px) for buttons.
    var radius: Int

    static let dark = Theme(
        background: "#0f1115",
        surface: "#1b1f27",
        text: "#e7e9ee",
        accent: "#5b8cff",
        radius: 18
    )
}

// MARK: Per-app audio

/// Snapshot of one audio process, sent to clients. `id` is the opaque
/// Core Audio process object id, serialized as a string because JS doesn't
/// have a fixed-width 32-bit type. `icon` is a PNG data URL when the
/// running app has one (most foreground apps do; helpers don't).
struct AudioApp: Codable {
    var id: String
    var name: String
    var icon: String?
    var playing: Bool
    /// 0…maxGain (0 = mute, 1 = unity, 2 = boost). Reflects the controller's
    /// stored slider position even when not currently tapped.
    var volume: Float
    var muted: Bool
}

/// An app mirrored to the client's Dock page. `id` is the bundle id (used to
/// activate or launch it). `running` is false for pinned Dock apps that aren't
/// currently open; `active` marks the frontmost running app.
struct RunningApp: Codable {
    var id: String
    var name: String
    var icon: String?
    var running: Bool
    var active: Bool
}

// MARK: Messages

/// server -> client
enum ServerMessage: Codable {
    case layout(Layout)
    case ack(buttonId: String, ok: Bool)
    /// Snapshot of the currently running apps, for the Dock page. Refreshed
    /// as apps launch / quit / come to the front. Replaces the client list.
    case dock(list: [RunningApp])
    /// Current system volume (0…1). Pushed on connect and whenever the value
    /// changes from any source (slider on the client, macOS menu bar, keys).
    case volume(target: VolumeTarget, value: Float)
    /// Snapshot of every audio process the server currently sees, refreshed
    /// periodically. Replaces the prior list on the client.
    case apps(list: [AudioApp])
    /// Per-app volume or mute change. Fired after the controller applies a
    /// client-driven set (so other clients can mirror it) and on connect
    /// for any app that already has a non-default stored level.
    case appVolume(id: String, volume: Float, muted: Bool)

    private enum CodingKeys: String, CodingKey {
        case type, data, buttonId, ok, target, value, list, id, volume, muted
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .layout(let layout):
            try c.encode("layout", forKey: .type)
            try c.encode(layout, forKey: .data)
        case .ack(let buttonId, let ok):
            try c.encode("ack", forKey: .type)
            try c.encode(buttonId, forKey: .buttonId)
            try c.encode(ok, forKey: .ok)
        case .volume(let target, let value):
            try c.encode("volume", forKey: .type)
            try c.encode(target, forKey: .target)
            try c.encode(value, forKey: .value)
        case .apps(let list):
            try c.encode("apps", forKey: .type)
            try c.encode(list, forKey: .list)
        case .dock(let list):
            try c.encode("dock", forKey: .type)
            try c.encode(list, forKey: .list)
        case .appVolume(let id, let volume, let muted):
            try c.encode("appVolume", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(volume, forKey: .volume)
            try c.encode(muted, forKey: .muted)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "layout": self = .layout(try c.decode(Layout.self, forKey: .data))
        case "ack": self = .ack(buttonId: try c.decode(String.self, forKey: .buttonId),
                                ok: try c.decode(Bool.self, forKey: .ok))
        case "volume": self = .volume(target: try c.decode(VolumeTarget.self, forKey: .target),
                                      value: try c.decode(Float.self, forKey: .value))
        case "apps": self = .apps(list: try c.decode([AudioApp].self, forKey: .list))
        case "dock": self = .dock(list: try c.decode([RunningApp].self, forKey: .list))
        case "appVolume":
            self = .appVolume(id: try c.decode(String.self, forKey: .id),
                              volume: try c.decode(Float.self, forKey: .volume),
                              muted: try c.decode(Bool.self, forKey: .muted))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                                                        debugDescription: "unknown server message")
        }
    }
}

/// client -> server
enum ClientMessage: Decodable {
    /// First message after the socket opens. `deviceId` is a stable id the
    /// client persists in `localStorage`, so a reload / reconnect / service
    /// worker from the *same* physical device reuses it. The server keys the
    /// connected-device count on it, which is what stops one phone from
    /// showing up as two or three "devices".
    case hello(name: String?, deviceId: String?)
    case press(buttonId: String)
    /// Continuous control input. `volume` updates the given target to `value`
    /// (0…1) and is fire-and-forget — there's no per-message ack; the server
    /// broadcasts the new level back so all clients stay in sync.
    case volume(target: VolumeTarget, value: Float)
    /// Set a per-app slider position. The server will lazily create a tap on
    /// the first call for a given app id (which is the moment macOS will prompt
    /// the user for audio capture permission). `muted` flips the mute bit
    /// independently of `value`; the server treats a 0 value as "muted via
    /// slider" but the two concepts are kept separate for cleaner state.
    case setAppVolume(id: String, value: Float, muted: Bool)
    /// The client reports its current viewport orientation. Used by the
    /// editor's "Follow device" preview toggle to render the device
    /// the same way the user is actually holding it.
    case deviceOrientation(isPortrait: Bool)
    /// Activate (or launch) a running app from the Dock page, by bundle id.
    case activateApp(bundleId: String)
    /// Client keepalive. Carries no data; its only job is to be periodic
    /// traffic. iOS Safari reclaims/reloads an idle `apple-mobile-web-app`
    /// page that has no JS/network activity, which put the client in an
    /// endless reload loop when nothing was happening on the Mac. The client
    /// sends this every few seconds; the server just lets it refresh the
    /// connection's `lastSeen` (see `handleFrame`) and otherwise ignores it.
    case ping

    private enum CodingKeys: String, CodingKey {
        case type, name, deviceId, buttonId, target, value, id, muted, isPortrait, bundleId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "hello": self = .hello(name: try c.decodeIfPresent(String.self, forKey: .name),
                                    deviceId: try c.decodeIfPresent(String.self, forKey: .deviceId))
        case "press": self = .press(buttonId: try c.decode(String.self, forKey: .buttonId))
        case "volume":
            self = .volume(target: try c.decode(VolumeTarget.self, forKey: .target),
                           value: try c.decode(Float.self, forKey: .value))
        case "setAppVolume":
            self = .setAppVolume(id: try c.decode(String.self, forKey: .id),
                                 value: try c.decode(Float.self, forKey: .value),
                                 muted: try c.decode(Bool.self, forKey: .muted))
        case "deviceOrientation":
            self = .deviceOrientation(
                isPortrait: try c.decode(Bool.self, forKey: .isPortrait)
            )
        case "activateApp":
            self = .activateApp(bundleId: try c.decode(String.self, forKey: .bundleId))
        case "ping":
            self = .ping
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                                                        debugDescription: "unknown client message")
        }
    }
}
