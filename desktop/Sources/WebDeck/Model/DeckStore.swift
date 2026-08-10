import Foundation

/// Holds the deck configuration. For the spike this is a seeded, in-memory
/// layout of a few real apps across two pages (enough to prove tap-to-open and
/// swipe-between-pages). Later this becomes the editable, persisted config
/// driven by the desktop UI.
@MainActor
final class DeckStore {
    static let shared = DeckStore()

    private(set) var layout: Layout

    private init() {
        self.layout = DeckStore.seed()
    }

    /// Resolve the current layout with fresh app icons baked in as data URLs.
    /// Icons are resolved lazily here rather than stored so we don't hold image
    /// data in the model.
    func resolvedLayout() -> Layout {
        var l = layout
        for p in l.pages.indices {
            for b in l.pages[p].buttons.indices {
                if let bundleId = l.pages[p].buttons[b].action.bundleId,
                   l.pages[p].buttons[b].icon == nil {
                    l.pages[p].buttons[b].icon = AppLauncher.iconDataURL(bundleId: bundleId)
                }
            }
        }
        return l
    }

    func button(id: String) -> DeckButton? {
        for page in layout.pages {
            if let b = page.buttons.first(where: { $0.id == id }) { return b }
        }
        return nil
    }

    // MARK: Seed

    private static func seed() -> Layout {
        func btn(_ label: String, _ bundleId: String, _ symbol: String) -> DeckButton {
            DeckButton(id: bundleId, label: label, icon: nil, symbol: symbol,
                       action: Action(kind: .openApp, bundleId: bundleId))
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

        return Layout(pages: [page1, page2], theme: .dark)
    }
}
