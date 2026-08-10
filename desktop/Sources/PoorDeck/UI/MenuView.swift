import SwiftUI

/// The menu-bar dropdown: server status at a glance, plus the entry point into
/// the configuration window and quit.
struct MenuView: View {
    @EnvironmentObject private var server: Server
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(server.isRunning ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(server.isRunning ? "Server running" : "Starting…")
                    .font(.headline)
            }

            if server.isRunning {
                VStack(alignment: .leading, spacing: 4) {
                    Label(server.pairingURL, systemImage: "link")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Label("\(server.clientCount) client\(server.clientCount == 1 ? "" : "s") connected",
                          systemImage: "iphone")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }

            Divider()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: WindowID.config)
            } label: {
                Label("Open configuration…", systemImage: "slider.horizontal.3")
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit PoorDeck", systemImage: "power")
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}
