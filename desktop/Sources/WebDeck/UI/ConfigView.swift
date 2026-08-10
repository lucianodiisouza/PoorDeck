import SwiftUI

/// The configuration window opened from the menu bar. For the spike it shows the
/// pairing panel (QR + URL) and the current status. The page/button/theme
/// editors land here next.
struct ConfigView: View {
    @EnvironmentObject private var server: Server
    @EnvironmentObject private var permissions: Permissions

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            Divider()
            pairingPanel
        }
        .frame(width: 720, height: 460)
        // Re-check the Accessibility grant whenever the window regains focus,
        // so granting it in System Settings reflects here without a relaunch.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WebDeck")
                .font(.title2.bold())
            Text("Configuration")
                .foregroundStyle(.secondary)

            Spacer().frame(height: 20)

            Label("Pairing", systemImage: "qrcode")
                .font(.headline)
            Label("Pages", systemImage: "square.grid.2x2")
                .foregroundStyle(.secondary)
            Label("Themes", systemImage: "paintpalette")
                .foregroundStyle(.secondary)

            Spacer()

            accessibilityStatus
            audioStatus

            HStack(spacing: 6) {
                Circle()
                    .fill(server.isRunning ? .green : .orange)
                    .frame(width: 7, height: 7)
                Text(server.isRunning ? "Running" : "Starting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 200, alignment: .leading)
    }

    /// Per-permission status block: a checkmark/triangle row plus either a
    /// "granted" caption or a brief explanation + Grant / Settings buttons.
    private func permissionRow(
        granted: Bool,
        title: String,
        grantedCaption: String,
        deniedCaption: String,
        grant: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: granted
                      ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(granted ? .green : .orange)
                Text(title)
                    .font(.caption.bold())
            }
            Text(granted ? grantedCaption : deniedCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !granted {
                HStack(spacing: 8) {
                    Button("Grant…", action: grant)
                        .controlSize(.small)
                    Button("Settings", action: openSettings)
                        .controlSize(.small)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var accessibilityStatus: some View {
        permissionRow(
            granted: permissions.accessibilityGranted,
            title: "Accessibility",
            grantedCaption: "Keyboard shortcuts enabled",
            deniedCaption: "Needed for keyboard-shortcut buttons",
            grant: permissions.requestAccessibility,
            openSettings: permissions.openAccessibilitySettings
        )
    }

    private var audioStatus: some View {
        permissionRow(
            granted: permissions.audioGranted,
            title: "Audio capture",
            grantedCaption: "Per-app volume control enabled",
            deniedCaption: "Needed to control the volume of each app individually",
            grant: permissions.requestAudio,
            openSettings: permissions.openAudioSettings
        )
    }

    private var pairingPanel: some View {
        VStack(spacing: 18) {
            Text("Scan to pair")
                .font(.title3.bold())

            if let image = QRCode.image(from: server.pairingURL) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .frame(width: 220, height: 220)
                    .overlay(Text("No network").foregroundStyle(.secondary))
            }

            VStack(spacing: 4) {
                Text("or open in a browser on the same Wi-Fi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(server.pairingURL)
                    .font(.system(.title3, design: .monospaced))
                    .textSelection(.enabled)
            }

            Label("\(server.clientCount) connected", systemImage: "iphone")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
