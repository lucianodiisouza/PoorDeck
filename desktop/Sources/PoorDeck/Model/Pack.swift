import AppKit
import UniformTypeIdentifiers

/// A shareable set of deck pages — a "PoorDeck Pack". This is how someone
/// exports, say, their DaVinci Resolve keystroke page and hands it to another
/// user who imports it and gets the same buttons, labels, and artwork.
///
/// Packs are self-contained JSON: every icon travels inside as a data URL
/// (baked into `DeckButton.customIcon` on export), so a pack renders even on a
/// Mac that doesn't have the target app installed. `openApp` buttons still
/// carry their `bundleId`, so they light up for importers who *do* have the app.
struct Pack: Codable {
    /// Format tag + version, so a future reader can migrate or reject packs it
    /// doesn't understand.
    var format: String
    var name: String
    var author: String?
    var summary: String?
    /// The app this pack is built for, when it targets one (e.g. DaVinci
    /// Resolve). Informational — used for display and as a hint on import.
    var targetApp: TargetApp?
    var pages: [Page]

    struct TargetApp: Codable {
        var bundleId: String?
        var name: String?
    }

    static let currentFormat = "poordeck-pack/v1"
}

/// The document type used for pack files on disk (`.pdpack`). Derived from the
/// filename extension so it needs no Info.plist declaration; falls back to
/// plain JSON. Panels also allow `.json` so a pack saved that way still opens.
extension UTType {
    static let poorDeckPack = UTType(filenameExtension: "pdpack") ?? .json
}

@MainActor
enum PackCodec {
    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    /// Build a pack from the given pages, baking each button's on-deck icon
    /// into `customIcon` so the artwork survives on a machine without the
    /// source apps. The transient `icon` field is dropped (it's re-resolved on
    /// the importer's machine).
    static func makePack(name: String,
                         pages: [Page],
                         author: String? = nil,
                         summary: String? = nil,
                         targetApp: Pack.TargetApp? = nil) -> Pack {
        let embedded = pages.map { page -> Page in
            var p = page
            p.buttons = page.buttons.map { embedIcon(in: $0) }
            return p
        }
        return Pack(format: Pack.currentFormat,
                    name: name,
                    author: author,
                    summary: summary,
                    targetApp: targetApp,
                    pages: embedded)
    }

    /// Resolve a button's displayed icon and stash it in `customIcon` as a
    /// portable fallback, then clear the transient `icon`. Preserves an
    /// author's explicit override; otherwise leaves `iconOverride` unset so an
    /// importer who owns the app still sees the live app icon.
    private static func embedIcon(in button: DeckButton) -> DeckButton {
        var b = button
        if b.customIcon == nil {
            if let bundleId = b.action.bundleId {
                b.customIcon = AppLauncher.iconDataURL(bundleId: bundleId)
            }
        }
        b.icon = nil
        return b
    }

    /// Encode a pack to pretty JSON data (what gets written to the `.pdpack`).
    static func encode(_ pack: Pack) throws -> Data {
        try encoder.encode(pack)
    }

    /// Decode a pack from file data. Throws on malformed JSON or an unknown
    /// format tag.
    static func decode(_ data: Data) throws -> Pack {
        let pack = try JSONDecoder().decode(Pack.self, from: data)
        guard pack.format.hasPrefix("poordeck-pack/") else {
            throw PackError.unrecognizedFormat(pack.format)
        }
        return pack
    }

    enum PackError: LocalizedError {
        case unrecognizedFormat(String)
        var errorDescription: String? {
            switch self {
            case .unrecognizedFormat(let f):
                return "This file isn't a PoorDeck pack (format: \(f))."
            }
        }
    }

    // MARK: - Panels

    /// Save the given pages as a pack. Presents a save panel seeded with the
    /// suggested name; returns true if a file was written.
    @discardableResult
    static func exportWithPanel(name: String,
                                pages: [Page],
                                targetApp: Pack.TargetApp? = nil) -> Bool {
        let pack = makePack(name: name, pages: pages, targetApp: targetApp)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.poorDeckPack, .json]
        panel.nameFieldStringValue = "\(sanitize(name)).pdpack"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try encode(pack).write(to: url, options: .atomic)
            return true
        } catch {
            present(error: error, title: "Couldn't export pack")
            return false
        }
    }

    /// Present an open panel and return the decoded pack, or nil on cancel /
    /// error (errors are surfaced to the user).
    static func importWithPanel() -> Pack? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.poorDeckPack, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            present(error: error, title: "Couldn't import pack")
            return nil
        }
    }

    private static func sanitize(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? "PoorDeck Pack" : cleaned
    }

    private static func present(error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
