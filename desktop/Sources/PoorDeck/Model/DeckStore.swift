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

    /// Resolve the current layout into the shape clients render: bake each
    /// button's transient `icon` from the right source. Icon data isn't held
    /// in the persisted JSON — only the user's `customIcon` is; the app's own
    /// icon is resolved lazily here.
    ///
    /// Resolution per button, into `icon`:
    ///   • `iconOverride` on  → the user's `customIcon` (their art wins; nil
    ///     leaves `icon` empty so the client draws the SF-symbol / label).
    ///   • otherwise, `openApp`/app-bound → the app's own icon, falling back
    ///     to `customIcon` when the app isn't installed on this Mac.
    ///   • otherwise → `customIcon` (custom art on a non-app button).
    func resolvedLayout() -> Layout {
        var l = layout
        for p in l.pages.indices {
            for b in l.pages[p].buttons.indices {
                let btn = l.pages[p].buttons[b]
                if btn.iconOverride == true {
                    l.pages[p].buttons[b].icon = btn.customIcon
                } else if let bundleId = btn.action.bundleId {
                    l.pages[p].buttons[b].icon =
                        AppLauncher.iconDataURL(bundleId: bundleId) ?? btn.customIcon
                } else {
                    l.pages[p].buttons[b].icon = btn.customIcon
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
