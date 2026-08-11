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
    private var distributedObservers: [NSObjectProtocol] = []
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

        // The Dock posts this (distributed) when its pinned set changes —
        // add / remove / reorder. Refresh so pinned tiles stay in sync.
        let dockToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.dock.prefchanged"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        distributedObservers.append(dockToken)
    }

    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0) }
        observers.removeAll()
        distributedObservers.forEach {
            DistributedNotificationCenter.default().removeObserver($0)
        }
        distributedObservers.removeAll()
        started = false
    }

    /// The Dock, mirrored: the user's pinned apps first (in Dock order),
    /// then any other running app not already pinned. Pinned apps that
    /// aren't open carry `running: false` so the client can dim them; the
    /// frontmost running app is flagged `active`. Tapping a dimmed pinned
    /// app launches it (openApp both launches and activates).
    func snapshot() -> [RunningApp] {
        let frontId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // bundle id -> running app, for O(1) "is it open / frontmost" lookups.
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        var runningById: [String: NSRunningApplication] = [:]
        for app in running {
            if let b = app.bundleIdentifier, runningById[b] == nil { runningById[b] = app }
        }

        var seen = Set<String>()
        var result: [RunningApp] = []

        // 1) Pinned Dock apps, in Dock order.
        for pinned in pinnedApps() where seen.insert(pinned.id).inserted {
            result.append(
                RunningApp(
                    id: pinned.id,
                    name: pinned.name,
                    icon: AppLauncher.iconDataURL(bundleId: pinned.id)
                        ?? runningById[pinned.id]?.icon.flatMap { Self.encode($0) },
                    running: runningById[pinned.id] != nil,
                    active: pinned.id == frontId
                )
            )
        }

        // 2) Anything else currently running, ordered by launch time.
        let others = running.sorted {
            ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast)
        }
        for app in others {
            guard let bundleId = app.bundleIdentifier, seen.insert(bundleId).inserted
            else { continue }
            let name = app.localizedName ?? AppLauncher.displayName(bundleId: bundleId) ?? bundleId
            result.append(
                RunningApp(
                    id: bundleId,
                    name: name,
                    icon: icon(for: app, bundleId: bundleId),
                    running: true,
                    active: bundleId == frontId
                )
            )
        }
        return result
    }

    /// The Dock's pinned applications, in order, read from the current user's
    /// `com.apple.dock` preferences (`persistent-apps`). Each tile carries a
    /// file URL (and, on newer macOS, the bundle id directly); we resolve a
    /// bundle id and a display label from it. Folders / stacks live under
    /// `persistent-others` and are intentionally skipped.
    private func pinnedApps() -> [(id: String, name: String)] {
        // Read fresh — the Dock rewrites this on every pin/reorder.
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        guard let raw = CFPreferencesCopyAppValue(
            "persistent-apps" as CFString, "com.apple.dock" as CFString
        ) as? [[String: Any]] else { return [] }

        var out: [(id: String, name: String)] = []
        for entry in raw {
            guard let tile = entry["tile-data"] as? [String: Any] else { continue }
            var bundleId = tile["bundle-identifier"] as? String
            let label = tile["file-label"] as? String
            if bundleId == nil,
               let fileData = tile["file-data"] as? [String: Any],
               let urlString = fileData["_CFURLString"] as? String,
               let url = URL(string: urlString) {
                bundleId = Bundle(url: url)?.bundleIdentifier
            }
            guard let id = bundleId else { continue }
            let name = label ?? AppLauncher.displayName(bundleId: id) ?? id
            out.append((id: id, name: name))
        }
        return out
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
