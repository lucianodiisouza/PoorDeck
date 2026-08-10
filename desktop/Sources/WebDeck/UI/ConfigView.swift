import SwiftUI

/// The configuration window opened from the menu bar. Hosts a sidebar
/// with section routing (Pairing / Pages / Permissions) and the matching
/// detail view.
struct ConfigView: View {
    @EnvironmentObject private var server: Server
    @EnvironmentObject private var permissions: Permissions
    @ObservedObject private var config = ConfigurationStore.shared

    enum Section: String, CaseIterable, Identifiable {
        case pairing = "Pairing"
        case pages = "Pages"
        case permissions = "Permissions"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .pairing: return "qrcode"
            case .pages: return "square.grid.2x2"
            case .permissions: return "lock.shield"
            }
        }
    }

    @State private var section: Section = .pairing

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 880, minHeight: 540)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WebDeck")
                    .font(.title2.bold())
                Text("Configuration")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 20)

            ForEach(Section.allCases) { s in
                Button {
                    section = s
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: s.icon)
                            .frame(width: 18)
                        Text(s.rawValue)
                            .fontWeight(section == s ? .semibold : .regular)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(section == s
                                  ? Color.accentColor.opacity(0.18)
                                  : Color.clear)
                    )
                    .foregroundStyle(section == s ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

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

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .pairing:
            pairingPanel
        case .pages:
            LayoutEditorView(store: config)
        case .permissions:
            permissionsPanel
        }
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

    private var permissionsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Permissions")
                .font(.title3.bold())

            Text("WebDeck needs two macOS grants. Open System Settings from the buttons below to flip the toggles after the fact.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(
                granted: permissions.accessibilityGranted,
                title: "Accessibility",
                grantedCaption: "Keyboard shortcuts enabled",
                deniedCaption: "Needed for keyboard-shortcut buttons (CGEvent posting).",
                grant: permissions.requestAccessibility,
                openSettings: permissions.openAccessibilitySettings
            )

            permissionRow(
                granted: permissions.audioGranted,
                title: "Audio capture",
                grantedCaption: "Per-app volume control enabled",
                deniedCaption: "Needed to control the volume of each app individually (process tap).",
                grant: permissions.requestAudio,
                openSettings: permissions.openAudioSettings
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: granted
                      ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(granted ? .green : .orange)
                    .font(.title3)
                Text(title)
                    .font(.headline)
            }
            Text(granted ? grantedCaption : deniedCaption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !granted {
                HStack(spacing: 8) {
                    Button("Grant…", action: grant)
                    Button("Open Settings", action: openSettings)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.08))
        )
    }
}
