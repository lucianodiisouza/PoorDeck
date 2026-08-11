import AppKit

/// Posts the standard system media / transport keys — the ones on the F-row and
/// Touch Bar (play/pause, next, previous, volume…). These aren't ordinary
/// keystrokes: macOS carries them as `NSEvent.EventType.systemDefined` events
/// with subtype 8 and an `NX_KEYTYPE_*` code, and the OS routes them to whatever
/// app currently owns "Now Playing" (Music, Spotify, a browser tab…). That's
/// why a single Play/Pause button works across every media app without us
/// knowing which one is in front.
///
/// Like `KeyEmitter`, posting synthetic HID events needs the Accessibility
/// (AXIsProcessTrusted) permission.
enum MediaKeyEmitter {

    /// Whether we're allowed to post synthetic HID events right now.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Fire `key` as a press-and-release. Returns false if Accessibility isn't
    /// granted or the event couldn't be built.
    @discardableResult
    static func send(_ key: MediaKey) -> Bool {
        guard isTrusted else {
            NSLog("PoorDeck: media key blocked — Accessibility not granted")
            return false
        }
        return post(key.nxKeyCode, down: true) && post(key.nxKeyCode, down: false)
    }

    /// Build and post one half (key-down or key-up) of a media-key event.
    /// The magic numbers are the documented shape of a system-defined media
    /// event: subtype 8, `data1 = (keyCode << 16) | (down ? 0xA00 : 0xB00)`,
    /// with the same value mirrored into the modifier flags.
    private static func post(_ keyCode: Int32, down: Bool) -> Bool {
        let state = down ? 0xA00 : 0xB00
        let data1 = (Int(keyCode) << 16) | state
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )?.cgEvent else {
            NSLog("PoorDeck: could not build media-key event for \(keyCode)")
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }
}
