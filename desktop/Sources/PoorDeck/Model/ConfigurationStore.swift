import Combine
import Foundation

/// Owns the editable `Layout` and persists it as JSON in
/// `~/Library/Application Support/PoorDeck/layout.json`.
///
/// On first launch the file doesn't exist — we fall back to the bundled
/// seed and write it out so subsequent runs see the same shape.
///
/// Mutations are exposed as discrete verbs (`addPage`, `updateButton`, …)
/// rather than a free-form `setLayout`, so the editor UI drives the
/// authoritative state and the store is the one place that decides what
/// "valid" means.
///
/// Each mutation is followed by `save()` and fires `onChange` so the
/// server can fan the new layout out to connected clients.
@MainActor
final class ConfigurationStore: ObservableObject {

    static let shared = ConfigurationStore()

    /// The current layout. Mutating this directly is a bug — go through the
    /// `add*` / `update*` / `delete*` methods below, which persist + notify.
    @Published private(set) var layout: Layout

    /// Fired after every persisted mutation. The server uses this to push
    /// the new layout to connected clients.
    var onChange: (() -> Void)?

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        self.fileURL = Self.layoutFileURL()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.layout = Self.loadOrSeed(from: fileURL,
                                      encoder: encoder,
                                      decoder: decoder)
    }

    // MARK: Persistence

    private static func layoutFileURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("PoorDeck", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("layout.json")
    }

    /// Load the layout from disk; if anything goes wrong, return the seed
    /// and overwrite the file with it so the next run starts from a known
    /// state.
    private static func loadOrSeed(from url: URL,
                                   encoder: JSONEncoder,
                                   decoder: JSONDecoder) -> Layout {
        if let data = try? Data(contentsOf: url),
           var layout = try? decoder.decode(Layout.self, from: data) {
            // Migration: ensure the live Dock page exists on layouts saved
            // before it was introduced, without disturbing the user's other
            // pages. Append it once, then persist so this is a no-op next run.
            if !layout.pages.contains(where: { $0.id == "dock" }) {
                layout.pages.append(Page(id: "dock", name: "Dock", columns: 4, buttons: []))
                if let migrated = try? encoder.encode(layout) {
                    try? migrated.write(to: url, options: .atomic)
                }
            }
            return layout
        }
        let seed = makeSeed()
        if let data = try? encoder.encode(seed) {
            try? data.write(to: url, options: .atomic)
        }
        return seed
    }

    /// Atomic save: write to a temp file in the same directory, then rename
    /// over the target. Avoids a half-written file if the process is killed
    /// mid-save.
    private func save() {
        do {
            let data = try encoder.encode(layout)
            let tmp = fileURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            // Replace atomically. If fileURL doesn't exist yet, FileManager
            // needs to know it's OK to create it.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: fileURL)
            }
        } catch {
            NSLog("PoorDeck: failed to save layout: \(error)")
        }
    }

    // MARK: Mutations

    /// Append a new page. Caller picks the id; the store doesn't second-guess.
    func addPage(id: String, name: String, columns: Int = 3) {
        let page = Page(id: id, name: name, columns: columns, buttons: [])
        layout.pages.append(page)
        commit()
    }

    /// Update an existing page's editable fields. No-op if the page
    /// is not found. Each parameter is optional — pass only the ones
    /// that changed.
    func updatePage(
        id: String,
        name: String? = nil,
        columns: Int? = nil,
        columnsPortrait: Int? = nil,
        columnsLandscape: Int? = nil,
        orientationLock: OrientationLock?? = nil
    ) {
        guard let i = layout.pages.firstIndex(where: { $0.id == id }) else { return }
        if let name { layout.pages[i].name = name }
        if let columns { layout.pages[i].columns = columns }
        if let columnsPortrait { layout.pages[i].columnsPortrait = columnsPortrait }
        if let columnsLandscape { layout.pages[i].columnsLandscape = columnsLandscape }
        if let orientationLock { layout.pages[i].orientationLock = orientationLock }
        commit()
    }

    /// Remove a page. The volume page (id "p4") is intentionally not
    /// deletable from the editor — the per-app volume list is wired into
    /// the client as a special view and dropping it would just confuse
    /// users. Other pages are free game.
    func deletePage(id: String) {
        guard id != "p4" else { return }
        layout.pages.removeAll { $0.id == id }
        commit()
    }

    /// Insert or update a button in a page. For new buttons, generates a
    /// unique id from the label if the caller didn't pick one.
    @discardableResult
    func upsertButton(pageId: String, button: DeckButton) -> Bool {
        guard let pi = layout.pages.firstIndex(where: { $0.id == pageId }) else { return false }
        var btn = button
        if btn.id.isEmpty {
            btn.id = Self.uniqueButtonId(prefix: btn.label, in: layout)
        }
        if let bi = layout.pages[pi].buttons.firstIndex(where: { $0.id == btn.id }) {
            // Preserve the existing icon when the bundleId is unchanged —
            // editing a button shouldn't make us re-resolve the icon from
            // disk on every keystroke.
            let existing = layout.pages[pi].buttons[bi]
            if existing.icon != nil, existing.action.bundleId == btn.action.bundleId {
                btn.icon = existing.icon
            }
            layout.pages[pi].buttons[bi] = btn
        } else {
            layout.pages[pi].buttons.append(btn)
        }
        commit()
        return true
    }

    /// Append the pages from an imported pack, giving each a fresh unique page
    /// id and de-duplicating button ids against everything already present, so
    /// an import never collides with the user's existing pages or buttons.
    /// Returns the ids of the pages that were added (so the UI can select one).
    @discardableResult
    func importPages(_ pages: [Page]) -> [String] {
        var takenButtonIds = Set(layout.pages.flatMap { $0.buttons.map(\.id) })
        var addedPageIds: [String] = []
        for (offset, incoming) in pages.enumerated() {
            var page = incoming
            page.id = "imp\(Int(Date().timeIntervalSince1970))-\(offset)"
            page.buttons = page.buttons.map { button in
                var b = button
                b.id = Self.disambiguate(id: b.id.isEmpty ? "btn" : b.id,
                                         against: takenButtonIds)
                takenButtonIds.insert(b.id)
                return b
            }
            layout.pages.append(page)
            addedPageIds.append(page.id)
        }
        commit()
        return addedPageIds
    }

    /// Return `id` if free, else `id-2`, `id-3`, … until one isn't taken.
    private static func disambiguate(id: String, against taken: Set<String>) -> String {
        guard taken.contains(id) else { return id }
        var n = 2
        var candidate = "\(id)-\(n)"
        while taken.contains(candidate) {
            n += 1
            candidate = "\(id)-\(n)"
        }
        return candidate
    }

    func deleteButton(pageId: String, buttonId: String) {
        guard let pi = layout.pages.firstIndex(where: { $0.id == pageId }) else { return }
        layout.pages[pi].buttons.removeAll { $0.id == buttonId }
        commit()
    }

    /// Apply an in-place edit to the theme. The editor's color pickers and
    /// radius slider funnel every change through here, so each tweak persists
    /// and broadcasts to connected clients just like a page/button edit.
    func updateTheme(_ transform: (inout Theme) -> Void) {
        transform(&layout.theme)
        commit()
    }

    /// Discard any unsaved in-memory state and reload from disk. Used by
    /// the editor's "Revert" button.
    func reload() {
        layout = Self.loadOrSeed(from: fileURL,
                                 encoder: encoder,
                                 decoder: decoder)
        commit()
    }

    // MARK: Helpers

    private func commit() {
        save()
        onChange?()
    }

    /// Generate a button id that doesn't collide with existing buttons.
    /// Uses a deterministic prefix so the same label always produces the
    /// same id (and ids survive a save/reload round trip).
    private static func uniqueButtonId(prefix: String, in layout: Layout) -> String {
        let base = prefix.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let stem = base.isEmpty ? "btn" : base
        var id = stem
        var n = 1
        let taken = Set(layout.pages.flatMap { $0.buttons.map(\.id) })
        while taken.contains(id) {
            n += 1
            id = "\(stem)-\(n)"
        }
        return id
    }

    // MARK: Seed

    private static func makeSeed() -> Layout {
        func btn(_ label: String, _ bundleId: String, _ symbol: String) -> DeckButton {
            DeckButton(id: bundleId, label: label, icon: nil, symbol: symbol,
                       action: Action(kind: .openApp, bundleId: bundleId, shortcut: nil,
                                      target: nil))
        }
        func key(_ id: String, _ label: String, _ keyName: String,
                 _ modifiers: [Shortcut.Modifier], app: String? = nil) -> DeckButton {
            DeckButton(id: id, label: label, icon: nil, symbol: "keyboard",
                       action: Action(kind: .keyShortcut, bundleId: app,
                                      shortcut: Shortcut(key: keyName, modifiers: modifiers),
                                      target: nil))
        }
        func volume(_ id: String, _ label: String, _ symbol: String) -> DeckButton {
            DeckButton(id: id, label: label, icon: nil, symbol: symbol,
                       action: Action(kind: .volume, bundleId: nil,
                                      shortcut: nil, target: .system))
        }
        func media(_ id: String, _ label: String, _ symbol: String,
                   _ key: MediaKey) -> DeckButton {
            DeckButton(id: id, label: label, icon: nil, symbol: symbol,
                       action: Action(kind: .media, bundleId: nil, shortcut: nil,
                                      target: nil, mediaKey: key))
        }

        let page1 = Page(id: "p1", name: "Apps", columns: 3, buttons: [
            btn("Safari", "com.apple.Safari", "safari"),
            btn("Notes", "com.apple.Notes", "note.text"),
            btn("Calendar", "com.apple.iCal", "calendar"),
            btn("Music", "com.apple.Music", "music.note"),
            btn("Terminal", "com.apple.Terminal", "terminal"),
            btn("Finder", "com.apple.finder", "folder"),
        ])
        let page2 = Page(id: "p2", name: "More", columns: 3, buttons: [
            btn("Settings", "com.apple.systempreferences", "gearshape"),
            btn("Mail", "com.apple.mail", "envelope"),
            btn("Messages", "com.apple.MobileSMS", "message"),
        ])
        let page3 = Page(id: "p3", name: "Keys", columns: 3, buttons: [
            key("copy", "Copy", "c", [.command]),
            key("paste", "Paste", "v", [.command]),
            key("new-tab", "New Tab", "t", [.command], app: "com.apple.Safari"),
            key("claude-accept", "Claude ⌘↵", "return", [.command], app: "com.anthropic.claudefordesktop"),
            key("screenshot", "Screenshot", "4", [.command, .shift]),
            key("spotlight", "Spotlight", "space", [.command]),
        ])
        let page4 = Page(id: "p4", name: "Media", columns: 3, buttons: [
            media("media-prev", "Previous", "backward.end.fill", .previous),
            media("media-playpause", "Play / Pause", "playpause.fill", .playPause),
            media("media-next", "Next", "forward.end.fill", .next),
            media("media-voldown", "Vol Down", "speaker.wave.1.fill", .volumeDown),
            media("media-mute", "Mute", "speaker.slash.fill", .mute),
            media("media-volup", "Vol Up", "speaker.wave.3.fill", .volumeUp),
        ])
        let page5 = Page(id: "p5", name: "Volume", columns: 2, buttons: [
            volume("vol-master", "System", "speaker.wave.2.fill"),
            volume("vol-mute", "Mute", "speaker.slash.fill"),
        ])
        // The Dock page has no static buttons — the client detects its stable
        // id ("dock") and renders the live running-apps list the server pushes.
        let dock = Page(id: "dock", name: "Dock", columns: 4, buttons: [])
        return Layout(pages: [page1, page2, page3, page4, page5, dock], theme: .dark)
    }
}
