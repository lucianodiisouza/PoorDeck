import AppKit

/// Mirrors the macOS Dock's "open apps" section: the set of regular (UI)
/// applications currently running, with the frontmost one flagged. Fires
/// `onChange` whenever that set — or the frontmost app — changes, so the
/// server can push a fresh snapshot to the Dock page on the client.
///
/// Modeled on `AudioProcessController`: a `@MainActor` shared singleton with
/// an `onChange` callback and a `snapshot()`. It observes `NSWorkspace`
/// notifications instead of polling — launches, quits, and activations each
/// post one — so it's effectively free when nothing is happening.
@MainActor
final class RunningAppsController: ObservableObject {

    static let shared = RunningAppsController()

    /// Called (on the main actor) whenever the running-app set or the
    /// frontmost app changes.
    var onChange: (() -> Void)?

    private var started = false
    private var observers: [NSObjectProtocol] = []
    /// data-URL icon cache, keyed by bundle id — decoding an app icon to PNG
    /// isn't free and the set barely changes, so we memoize.
    private var iconCache: [String: String] = [:]

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        let nc = NSWorkspace.shared.notificationCenter
        // Each of these alters what the Dock shows: an app appearing,
        // disappearing, or a different app coming to the front.
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ] {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?() }
            }
            observers.append(token)
        }
    }

    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0) }
        observers.removeAll()
        started = false
    }

    /// The current running apps, frontmost first-flagged. Filtered to
    /// `.regular` apps (the ones with a Dock tile / UI) and de-duplicated by
    /// bundle id. Ordered by launch time so the list stays stable as apps
    /// come and go, the way the Dock keeps a running app in place.
    func snapshot() -> [RunningApp] {
        let frontId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        var seen = Set<String>()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted {
                ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast)
            }

        var result: [RunningApp] = []
        for app in apps {
            guard let bundleId = app.bundleIdentifier, seen.insert(bundleId).inserted
            else { continue }
            let name = app.localizedName ?? AppLauncher.displayName(bundleId: bundleId) ?? bundleId
            result.append(
                RunningApp(
                    id: bundleId,
                    name: name,
                    icon: icon(for: app, bundleId: bundleId),
                    active: bundleId == frontId
                )
            )
        }
        return result
    }

    /// Encode a running app's icon to a PNG data URL, cached by bundle id.
    private func icon(for app: NSRunningApplication, bundleId: String) -> String? {
        if let cached = iconCache[bundleId] { return cached }
        // Prefer the bundle-id path (matches how layout buttons are encoded);
        // fall back to the live icon on the running app.
        let dataURL =
            AppLauncher.iconDataURL(bundleId: bundleId)
            ?? app.icon.flatMap { Self.encode($0) }
        if let dataURL { iconCache[bundleId] = dataURL }
        return dataURL
    }

    /// PNG data URL for an NSImage, at a grid-friendly size.
    private static func encode(_ image: NSImage, size: CGFloat = 128) -> String? {
        let target = NSSize(width: size, height: size)
        let resized = NSImage(size: target)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy, fraction: 1.0
        )
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }
}
