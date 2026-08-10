import AppKit

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
