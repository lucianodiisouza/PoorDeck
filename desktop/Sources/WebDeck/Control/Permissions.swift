import ApplicationServices
import Combine
import SwiftUI

/// Tracks the Accessibility permission, which keyboard-shortcut actions need.
/// The grant is tied to the app binary, so ad-hoc/dev rebuilds can reset it —
/// the config window surfaces the current state and a button to request it.
@MainActor
final class Permissions: ObservableObject {
    @Published private(set) var accessibilityGranted = false

    init() { refresh() }

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    /// Ask macOS to prompt the user to add WebDeck under
    /// System Settings ▸ Privacy & Security ▸ Accessibility.
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        refresh()
    }

    /// Deep link to the Accessibility settings pane.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
