import Foundation

/// Thin read-side view over `ConfigurationStore`. The store is the source
/// of truth for the editable `Layout`; this layer only adds the per-button
/// icon cache (icons are resolved lazily so we don't hold image data in
/// the persisted JSON) and a couple of lookup helpers used by the WebSocket
/// server.
@MainActor
final class DeckStore {
    static let shared = DeckStore()

    private let store: ConfigurationStore
    private(set) var layout: Layout

    private init() {
        self.store = ConfigurationStore.shared
        self.layout = store.layout
    }

    /// Subscribe to layout changes from the store. Used by `Server` to fan
    /// the updated layout out to every connected client when the editor
    /// persists a change.
    func onLayoutChange(_ handler: @escaping () -> Void) {
        store.onChange = handler
    }

    /// Refresh the cached layout snapshot from the store. Cheap; called
    /// after each store mutation.
    func refresh() {
        layout = store.layout
    }

    /// Resolve the current layout with fresh app icons baked in as data URLs.
    /// Icons are resolved lazily here rather than stored so we don't hold
    /// image data in the persisted JSON.
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
}
