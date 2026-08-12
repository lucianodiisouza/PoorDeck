import AppKit
import SwiftUI

@main
struct PoorDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(appDelegate.server)
                .environmentObject(appDelegate.updateChecker)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        // Opened on demand from the menu ("Open configuration…"). Built
        // once at scene-construction time (not lazily) so the closure
        // captures a stable reference to the AppDelegate and SwiftUI
        // doesn't have to re-resolve nested-type metadata on every reopen.
        Window("PoorDeck", id: WindowID.config) {
            ConfigViewHost()
                .environmentObject(appDelegate.server)
                .environmentObject(appDelegate.permissions)
        }
        .windowResizability(.contentSize)
    }
}

/// Tiny stand-in so the Window scene's content closure is a single,
/// non-nested-type view — avoids a `ConfigView.Section` metadata crash
/// when the body is rebuilt by SwiftUI on macOS 14.2 with a Section enum
/// nested inside the view type.
private struct ConfigViewHost: View {
    @EnvironmentObject private var server: Server
    @EnvironmentObject private var permissions: Permissions

    var body: some View {
        ConfigView()
            .environmentObject(server)
            .environmentObject(permissions)
    }
}

enum WindowID {
    static let config = "config"
}

/// The persistent menu-bar icon. Besides drawing the glyph, it captures the
/// scene's `openWindow` action into `WindowCoordinator` so non-View code (the
/// file-open handler in `AppDelegate`) can bring the config window forward the
/// same way the menu's "Open configuration…" item does.
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "square.grid.3x3.fill")
            .onAppear { WindowCoordinator.shared.register(openWindow) }
    }
}

/// Bridges AppKit callbacks to SwiftUI window opening. Holds the `openWindow`
/// action once a scene has provided it; a request that arrives first (e.g. a
/// `.pdpack` opened on cold launch, before the menu-bar label appears) is
/// remembered and replayed the moment the action registers.
@MainActor
final class WindowCoordinator {
    static let shared = WindowCoordinator()
    private init() {}

    private var openWindow: OpenWindowAction?
    private var pendingConfig = false

    /// Called by the menu-bar label once SwiftUI hands it the action.
    func register(_ action: OpenWindowAction) {
        openWindow = action
        if pendingConfig {
            pendingConfig = false
            openConfig()
        }
    }

    /// Bring the config window to the front, creating it if needed. Defers if
    /// the action isn't available yet.
    func openConfig() {
        guard let openWindow else {
            pendingConfig = true
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: WindowID.config)
    }
}

/// Starts the server eagerly at launch so a client can pair immediately.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let server = Server()
    let permissions = Permissions()
    let updateChecker = UpdateChecker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under XCTest the app is only a test host — don't bind the network
        // port or hit the update endpoint, so the suite stays hermetic.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        server.start()
        updateChecker.check()
    }

    /// Finder double-click / "Open with PoorDeck" on a `.pdpack` (declared in
    /// CFBundleDocumentTypes) routes here. Each file is decoded and its pages
    /// appended to the shared store, matching the in-app import button.
    func application(_ application: NSApplication, open urls: [URL]) {
        var importedAny = false
        for url in urls {
            do {
                let pack = try PackCodec.decode(Data(contentsOf: url))
                ConfigurationStore.shared.importPages(pack.pages)
                importedAny = true
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn't import “\(url.lastPathComponent)”"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
        // Surface the freshly imported pages so the import isn't a silent
        // background action on this menu-bar-only app.
        if importedAny {
            WindowCoordinator.shared.openConfig()
        }
    }
}
