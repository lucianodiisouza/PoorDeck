import Foundation

/// Wire protocol shared with the Svelte client. Keep these shapes in sync with
/// `client/src/lib/types.ts`.
///
/// Everything travels as JSON text frames over the WebSocket. The desktop is the
/// source of truth: it pushes the full `Layout` on connect and executes the
/// actions the client asks for.

// MARK: Layout (server -> client)

struct Layout: Codable {
    var pages: [Page]
    var theme: Theme
}

struct Page: Codable {
    var id: String
    var name: String
    /// Column count the client uses to lay the grid out.
    var columns: Int
    var buttons: [DeckButton]
}

/// Named `DeckButton` (not `Button`) to avoid colliding with SwiftUI.Button in
/// the desktop UI. Serializes the same shape as the client's `Button` type.
struct DeckButton: Codable {
    var id: String
    var label: String
    /// PNG data URL (e.g. the app's own icon), when we have one.
    var icon: String?
    /// SF-Symbol-style fallback name the client maps to its own glyphs.
    var symbol: String?
    var action: Action
}

struct Action: Codable {
    enum Kind: String, Codable {
        case openApp      // launch or bring an app to the front
        case keyShortcut  // post a keyboard shortcut (e.g. ⌘↵)
        case volume       // a non-tap control bound to system volume
        case none         // placeholder / not wired yet
    }
    var kind: Kind
    /// Bundle id. For `openApp` it's the target; for `keyShortcut` it's an
    /// optional app to bring to the front before the keys are sent (nil = send
    /// to whatever's already focused). Reserved / unused for `volume`.
    var bundleId: String?
    /// The keystroke for `keyShortcut`.
    var shortcut: Shortcut?
    /// For `volume` controls: which audio target this control drives. Right now
    /// we only ship `system` (the default output device). Per-app volume needs
    /// the process-tap engine mentioned in the README and is intentionally not
    /// modeled yet — `target` is forward-compatible.
    var target: VolumeTarget?
}

enum VolumeTarget: String, Codable {
    case system
}

/// A keyboard shortcut, described by layout-independent key name + modifiers.
/// e.g. ⌘↵ = Shortcut(key: "return", modifiers: [.command]).
struct Shortcut: Codable {
    enum Modifier: String, Codable {
        case command, shift, option, control
    }
    /// Key name resolved to a virtual keycode by `KeyEmitter` (letters, digits,
    /// "return", "space", "tab", "escape", arrows, "f1"…"f12", etc.).
    var key: String
    var modifiers: [Modifier]
}

struct Theme: Codable {
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

// MARK: Messages

/// server -> client
enum ServerMessage: Codable {
    case layout(Layout)
    case ack(buttonId: String, ok: Bool)
    /// Current system volume (0…1). Pushed on connect and whenever the value
    /// changes from any source (slider on the client, macOS menu bar, keys).
    case volume(target: VolumeTarget, value: Float)

    private enum CodingKeys: String, CodingKey {
        case type, data, buttonId, ok, target, value
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
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                                                        debugDescription: "unknown server message")
        }
    }
}

/// client -> server
enum ClientMessage: Decodable {
    case hello(name: String?)
    case press(buttonId: String)
    /// Continuous control input. `volume` updates the given target to `value`
    /// (0…1) and is fire-and-forget — there's no per-message ack; the server
    /// broadcasts the new level back so all clients stay in sync.
    case volume(target: VolumeTarget, value: Float)

    private enum CodingKeys: String, CodingKey { case type, name, buttonId, target, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "hello": self = .hello(name: try c.decodeIfPresent(String.self, forKey: .name))
        case "press": self = .press(buttonId: try c.decode(String.self, forKey: .buttonId))
        case "volume":
            self = .volume(target: try c.decode(VolumeTarget.self, forKey: .target),
                           value: try c.decode(Float.self, forKey: .value))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                                                        debugDescription: "unknown client message")
        }
    }
}
