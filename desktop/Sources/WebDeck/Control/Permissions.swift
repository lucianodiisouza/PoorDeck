import AVFoundation
import ApplicationServices
import Combine
import SwiftUI

/// Tracks the macOS permissions WebDeck needs:
/// - **Accessibility**: keyboard-shortcut actions (CGEvent posting).
/// - **Audio capture** (Microphone TCC): the process-tap engine routes other
///   apps' audio through us, which counts as capture, so the user has to
///   grant the same TCC prompt a normal mic app would.
///
/// Both grants are tied to the app binary — ad-hoc / dev rebuilds can reset
/// them. The config window surfaces the current state and a button to request
/// each one.
@MainActor
final class Permissions: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var audioGranted = false

    init() { refresh() }

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        audioGranted = Self.queryAudio()
    }

    // MARK: Accessibility

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

    // MARK: Audio capture (process taps)

    /// AVFoundation's mic authorization is the public API for the TCC grant
    /// the Core Audio process-tap pipeline rides on. The first call to
    /// `requestAccess` triggers the system prompt (using the
    /// `NSMicrophoneUsageDescription` from Info.plist).
    private static func queryAudio() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Ask macOS to prompt the user to grant microphone access. Refreshes
    /// `audioGranted` when the user responds. No-op if already granted.
    func requestAudio() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            // Hop back to the main actor — the published property is bound
            // to the UI, and `authorizationStatus` is the only authoritative
            // read after the prompt resolves.
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Deep link to the Microphone settings pane, where the user can flip the
    /// toggle after the fact (e.g. if they denied it the first time).
    func openAudioSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
