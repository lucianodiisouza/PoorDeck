import AppKit
import SwiftUI

@main
struct PoorDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(appDelegate.server)
        } label: {
            Image(systemName: "square.grid.3x3.fill")
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

/// Starts the server eagerly at launch so a client can pair immediately.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let server = Server()
    let permissions = Permissions()

    func applicationDidFinishLaunching(_ notification: Notification) {
        server.start()
    }
}
