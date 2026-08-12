import AppKit
import SwiftUI

/// The menu-bar dropdown: server status at a glance, plus the entry point into
/// the configuration window and quit.
struct MenuView: View {
    @EnvironmentObject private var server: Server
    @EnvironmentObject private var updateChecker: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // A newer GitHub release is pinned to the very top so it's the
            // first thing seen when the menu opens.
            if let release = updateChecker.available {
                updateBanner(release)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(server.isRunning ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(server.isRunning ? "Server running" : "Starting…")
                    .font(.headline)
            }

            if server.isRunning {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Label(server.pairingURL, systemImage: "link")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button(action: copyURL) {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(didCopy ? Color.green : Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .help(didCopy ? "Copied!" : "Copy address")
                    }
                    Label("\(server.clientCount) client\(server.clientCount == 1 ? "" : "s") connected",
                          systemImage: "iphone")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }

            Divider()

            menuItem("Open configuration…", systemImage: "slider.horizontal.3") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: WindowID.config)
            }

            menuItem("Quit PoorDeck", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { updateChecker.check() }
    }

    /// A tappable notice that opens the release page in the browser.
    private func updateBanner(_ release: UpdateChecker.Release) -> some View {
        Button {
            NSWorkspace.shared.open(release.htmlURL)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Update available")
                        .font(.subheadline.bold())
                    Text("Version \(release.version) is ready on GitHub")
                        .font(.caption)
                        .opacity(0.9)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    /// A full-width menu row: the button fills the popover width and highlights
    /// across the whole row, so every item shares the same hit target.
    private func menuItem(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func copyURL() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(server.pairingURL, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
    }
}
