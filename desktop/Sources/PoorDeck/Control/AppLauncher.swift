import AppKit
import UniformTypeIdentifiers

/// Executes button actions that target other apps. For the spike that's just
/// "open / bring to front", which is all macOS needs — `NSWorkspace.open` on an
/// already-running app activates it, so tap-to-switch comes for free.
enum AppLauncher {

    /// Launch the app with the given bundle id, or bring it to the front if it's
    /// already running. Returns whether we found the app to act on.
    @discardableResult
    @MainActor
    static func openApp(bundleId: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            NSLog("PoorDeck: no app for bundle id \(bundleId)")
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { NSLog("PoorDeck: open failed \(bundleId): \(error)") }
        }
        return true
    }

    /// Human-readable name for an installed app's bundle id (e.g.
    /// "com.apple.Safari" -> "Safari"), or nil if it isn't installed.
    @MainActor
    static func displayName(bundleId: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    /// Prompt the user to pick an installed application, returning its bundle
    /// id (and display name). Runs a standard open panel scoped to
    /// `/Applications`, so users choose an app by its icon instead of typing a
    /// reverse-DNS string they'd have to look up.
    @MainActor
    static func chooseApp() -> (bundleId: String, name: String)? {
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return (id, name)
    }

    /// The app's own icon as a PNG `data:` URL, sized for the client grid.
    /// Returns nil if the app isn't installed.
    @MainActor
    static func iconDataURL(bundleId: String, size: CGFloat = 128) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let target = NSSize(width: size, height: size)

        let resized = NSImage(size: target)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(in: NSRect(origin: .zero, size: target),
                  from: NSRect(origin: .zero, size: icon.size),
                  operation: .copy, fraction: 1.0)
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }
}
