import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Posts keyboard shortcuts to other apps via CGEvent. Requires the
/// Accessibility (AXIsProcessTrusted) permission — macOS blocks synthetic key
/// events otherwise. Optionally brings a target app to the front first, so a
/// shortcut like Claude's ⌘↵ lands in the right place.
enum KeyEmitter {

    /// Whether we're allowed to post synthetic key events right now.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Send `shortcut`. If `bundleId` is set, activate that app first and give it
    /// a beat to come forward. Returns false if Accessibility isn't granted or
    /// the key name is unknown.
    @discardableResult
    @MainActor
    static func send(_ shortcut: Shortcut, activating bundleId: String?) -> Bool {
        guard isTrusted else {
            NSLog("WebDeck: keyShortcut blocked — Accessibility not granted")
            return false
        }
        guard let keyCode = virtualKey(for: shortcut.key) else {
            NSLog("WebDeck: unknown key '\(shortcut.key)'")
            return false
        }
        let flags = eventFlags(shortcut.modifiers)

        if let bundleId,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    post(keyCode: keyCode, flags: flags)
                }
            }
        } else {
            post(keyCode: keyCode, flags: flags)
        }
        return true
    }

    private static func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func eventFlags(_ modifiers: [Shortcut.Modifier]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .shift: flags.insert(.maskShift)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            }
        }
        return flags
    }

    /// Layout-independent virtual keycodes (Carbon `kVK_*`) for the keys we
    /// expose. These map hardware positions, not characters, which is exactly
    /// what shortcuts want.
    private static func virtualKey(for name: String) -> CGKeyCode? {
        let key = name.lowercased()
        if let code = map[key] { return CGKeyCode(code) }
        // Single letter / digit fall through to the map above; nothing else.
        return nil
    }

    private static let map: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "return": kVK_Return, "enter": kVK_Return,
        "tab": kVK_Tab, "space": kVK_Space,
        "delete": kVK_Delete, "backspace": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
        "escape": kVK_Escape, "esc": kVK_Escape,
        "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "up": kVK_UpArrow, "down": kVK_DownArrow,
        "home": kVK_Home, "end": kVK_End,
        "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period, "slash": kVK_ANSI_Slash,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
        "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
        "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]
}
