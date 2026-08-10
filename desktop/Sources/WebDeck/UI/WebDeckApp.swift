import AppKit
import SwiftUI

@main
struct WebDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(appDelegate.server)
        } label: {
            Image(systemName: "square.grid.3x3.fill")
        }
        .menuBarExtraStyle(.window)

        // Opened on demand from the menu ("Open configuration…").
        Window("WebDeck", id: WindowID.config) {
            ConfigView()
                .environmentObject(appDelegate.server)
                .environmentObject(appDelegate.permissions)
        }
        .windowResizability(.contentSize)
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
