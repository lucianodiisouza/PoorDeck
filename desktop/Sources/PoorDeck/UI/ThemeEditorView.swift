import AppKit
import SwiftUI

/// Theme editor: four color pickers (background / surface / text / accent) and
/// a corner-radius slider, with a live preview. Each change goes through
/// `ConfigurationStore.updateTheme`, so it persists and broadcasts to every
/// connected client immediately.
struct ThemeEditorView: View {
    @ObservedObject var store: ConfigurationStore

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            form
                .frame(width: 280)
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(24)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Theme").font(.title3.bold())

            colorField("Background", hex: store.layout.theme.background) { hex in
                store.updateTheme { $0.background = hex }
            }
            colorField("Surface", hex: store.layout.theme.surface) { hex in
                store.updateTheme { $0.surface = hex }
            }
            colorField("Text", hex: store.layout.theme.text) { hex in
                store.updateTheme { $0.text = hex }
            }
            colorField("Accent", hex: store.layout.theme.accent) { hex in
                store.updateTheme { $0.accent = hex }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Corner radius")
                    Spacer()
                    Text("\(store.layout.theme.radius) px")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(store.layout.theme.radius) },
                    set: { newValue in
                        store.updateTheme { $0.radius = Int(newValue.rounded()) }
                    }
                ), in: 0...32, step: 1)
            }

            Spacer()

            Button("Restore dark defaults") {
                store.updateTheme { $0 = .dark }
            }
        }
    }

    /// Color picker driven by hex strings (so it round-trips through the
    /// Codable `Theme`). `ColorPicker` wants a `Color`, so we parse the hex,
    /// bind the picker, and emit the hex back on change.
    private func colorField(_ label: String,
                            hex: String,
                            onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline)
            HStack(spacing: 8) {
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { Color(hex: hex) ?? .black },
                        set: { newValue in onChange(newValue.toHex() ?? hex) }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 32, height: 22)
                Text(hex)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Preview

    private var preview: some View {
        let t = store.layout.theme
        return VStack(alignment: .leading, spacing: 12) {
            Text("Preview").font(.subheadline).foregroundStyle(.secondary)
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    previewTile(label: "Safari", symbol: "safari", t: t)
                    previewTile(label: "Notes", symbol: "note.text", t: t)
                    previewTile(label: "Music", symbol: "music.note", t: t)
                }
                HStack(spacing: 12) {
                    previewTile(label: "Terminal", symbol: "terminal", t: t)
                    previewTile(label: "Finder", symbol: "folder", t: t)
                    previewTile(label: "Mail", symbol: "envelope", t: t)
                }
            }
            .padding(16)
            .background(Color(hex: t.background) ?? .black)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private func previewTile(label: String, symbol: String, t: Theme) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(Color(hex: t.accent) ?? .blue)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color(hex: t.text) ?? .white)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(Color(hex: t.surface) ?? .gray)
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(t.radius)))
    }
}

// MARK: - Hex <-> Color helpers

extension Color {
    /// Parse `#rrggbb` (the on-disk shape). Returns nil for anything we don't
    /// recognize so the picker falls back to black rather than silently
    /// corrupting the theme.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    /// Round-trip back to `#rrggbb` for storage, in the sRGB color space so the
    /// values match the hex we parsed.
    func toHex() -> String? {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
