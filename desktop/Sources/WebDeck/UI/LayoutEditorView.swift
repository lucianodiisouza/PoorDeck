import SwiftUI

/// The Pages tab: a three-pane editor — page list (left), button grid for
/// the selected page (center), and the form for the selected button (right).
///
/// All edits are committed through the `ConfigurationStore`, which persists
/// each change to disk and fires `onChange`, so the server pushes the new
/// layout to connected clients automatically. No explicit "Save" button.
struct LayoutEditorView: View {
    @ObservedObject var store: ConfigurationStore
    @State private var selectedPageId: String?
    @State private var selectedButtonId: String?

    var body: some View {
        HSplitView {
            HSplitView {
                pageList
                    .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)
                buttonGrid
                    .frame(minWidth: 380)
            }
            .frame(maxWidth: .infinity)

            if currentButton != nil, let pageId = currentPage?.id {
                buttonForm
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            } else {
                hintPane
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            }
        }
        .onAppear {
            if selectedPageId == nil {
                selectedPageId = store.layout.pages.first?.id
            }
        }
        .onChange(of: store.layout) { _, _ in
            // If the selected page disappeared (deleted), fall back to the
            // first remaining one. Same for the selected button.
            if let pid = selectedPageId, !store.layout.pages.contains(where: { $0.id == pid }) {
                selectedPageId = store.layout.pages.first?.id
                selectedButtonId = nil
            }
            if let bid = selectedButtonId,
               let pid = selectedPageId,
               let page = store.layout.pages.first(where: { $0.id == pid }),
               !page.buttons.contains(where: { $0.id == bid }) {
                selectedButtonId = nil
            }
        }
    }

    private var hintPane: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "square.and.pencil")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Select a button")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click any button in the grid to edit it.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: Page list

    private var pageList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pages")
                    .font(.headline)
                Spacer()
                Button {
                    let id = "p\(Int(Date().timeIntervalSince1970))"
                    let n = store.layout.pages.count + 1
                    store.addPage(id: id, name: "Page \(n)")
                    selectedPageId = id
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add page")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.layout.pages) { page in
                        pageRow(for: page)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    private func pageRow(for page: Page) -> some View {
        let isSelected = selectedPageId == page.id
        return Button {
            selectedPageId = page.id
        } label: {
            HStack {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 16)
                Text(page.name)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Spacer()
                Text("\(page.buttons.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if page.id != "p4" {
                Button(role: .destructive) {
                    store.deletePage(id: page.id)
                } label: {
                    Label("Delete page", systemImage: "trash")
                }
            } else {
                Text("The Volume page is built-in and can't be removed.")
            }
        }
    }

    // MARK: Button grid

    private var buttonGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let page = currentPage {
                HStack {
                    TextField("Page name", text: Binding(
                        get: { page.name },
                        set: { store.updatePage(id: page.id, name: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                    Stepper("Cols: \(page.columns)", value: Binding(
                        get: { page.columns },
                        set: { store.updatePage(id: page.id, columns: $0) }
                    ), in: 1...6)
                    .frame(maxWidth: 140)

                    Spacer()

                    Button {
                        let newButton = DeckButton(
                            id: "",
                            label: "New",
                            icon: nil,
                            symbol: "questionmark.square",
                            action: Action(kind: .none, bundleId: nil, shortcut: nil, target: nil)
                        )
                        store.upsertButton(pageId: page.id, button: newButton)
                        selectedButtonId = lastInsertedButtonId(in: page.id)
                    } label: {
                        Label("Add button", systemImage: "plus")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                ScrollView {
                    grid(for: page)
                        .padding(16)
                }
            } else {
                ContentUnavailableShim("No page selected",
                                       "Select a page on the left, or add one.")
            }
        }
    }

    @ViewBuilder
    private func grid(for page: Page) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: max(1, page.columns))
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(page.buttons) { button in
                cell(for: button)
            }
        }
    }

    @ViewBuilder
    private func cell(for button: DeckButton) -> some View {
        let isSelected = selectedButtonId == button.id
        Button {
            selectedButtonId = button.id
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.18))
                    if let icon = button.icon, let nsImage = Self.imageFromDataURL(icon) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    } else {
                        Image(systemName: Self.glyph(for: button))
                            .font(.system(size: 24))
                            .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    }
                }
                .frame(height: 60)
                Text(button.label)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                if let pid = currentPage?.id {
                    store.deleteButton(pageId: pid, buttonId: button.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Button form

    @ViewBuilder
    private var buttonForm: some View {
        if let button = currentButton, let pageId = currentPage?.id {
            ButtonForm(
                button: button,
                pageId: pageId,
                onChange: { updated in
                    store.upsertButton(pageId: pageId, button: updated)
                },
                onDelete: {
                    store.deleteButton(pageId: pageId, buttonId: button.id)
                }
            )
        } else {
            VStack {
                Spacer()
                Text("Select a button to edit")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Helpers

    private var currentPage: Page? {
        guard let id = selectedPageId else { return nil }
        return store.layout.pages.first { $0.id == id }
    }
    private var currentButton: DeckButton? {
        guard let pid = selectedPageId, let bid = selectedButtonId else { return nil }
        return store.layout.pages.first(where: { $0.id == pid })?.buttons.first(where: { $0.id == bid })
    }
    private func lastInsertedButtonId(in pageId: String) -> String? {
        store.layout.pages.first(where: { $0.id == pageId })?.buttons.last?.id
    }

    private static func glyph(for button: DeckButton) -> String {
        if let s = button.symbol, !s.isEmpty { return s }
        return button.action.kind == .none ? "questionmark.square" : "app.fill"
    }

    /// Decode a `data:image/png;base64,...` URL into an NSImage. Used for
    /// buttons whose `icon` was resolved by the AppLauncher cache.
    private static func imageFromDataURL(_ s: String) -> NSImage? {
        guard let comma = s.firstIndex(of: ","),
              let data = Data(base64Encoded: String(s[s.index(after: comma)...]))
        else { return nil }
        return NSImage(data: data)
    }
}

// MARK: - Button form

private struct ButtonForm: View {
    let button: DeckButton
    let pageId: String
    let onChange: (DeckButton) -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Button").font(.headline)
                    Spacer()
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }

                Group {
                    LabeledField(label: "Label") {
                        TextField("Label", text: binding(\.label))
                    }
                    LabeledField(label: "Symbol") {
                        TextField("SF Symbol name", text: bindingOptional(\.symbol, default: "app.fill"))
                    }
                    LabeledField(label: "Action") {
                        Picker("", selection: binding(\.action.kind)) {
                            Text("None").tag(Action.Kind.none)
                            Text("Open app").tag(Action.Kind.openApp)
                            Text("Keyboard shortcut").tag(Action.Kind.keyShortcut)
                            Text("Volume").tag(Action.Kind.volume)
                        }
                        .labelsHidden()
                    }
                }

                Divider()

                switch button.action.kind {
                case .none:
                    Text("This button does nothing on tap.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                case .openApp:
                    LabeledField(label: "Bundle id") {
                        TextField("com.example.app", text: bindingForBundleId())
                    }
                case .keyShortcut:
                    ShortcutEditor(button: button, onChange: onChange)
                case .volume:
                    Text("Controls the system master volume. The per-app volume list is live; this control stays a simple slider/mute pair.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .padding(16)
        }
    }

    // MARK: Bindings

    private func binding<V>(_ keyPath: WritableKeyPath<DeckButton, V>) -> Binding<V> {
        Binding(
            get: { button[keyPath: keyPath] },
            set: { onChange(button.with(keyPath, setTo: $0)) }
        )
    }

    /// `symbol` is optional, but the TextField wants a non-optional binding.
    /// Default to "app.fill" when the stored value is nil, and write back
    /// the literal default if the user clears the field (otherwise nil would
    /// be a confusing side-effect of pressing backspace).
    private func bindingOptional(_ keyPath: WritableKeyPath<DeckButton, String?>,
                                default fallback: String) -> Binding<String> {
        Binding(
            get: { button[keyPath: keyPath] ?? fallback },
            set: { newValue in
                onChange(button.with(keyPath, setTo: newValue.isEmpty ? nil : newValue))
            }
        )
    }

    private func defaulted(_ fallback: String) -> (String?) -> String {
        { $0 ?? fallback }
    }

    private func bindingForBundleId() -> Binding<String> {
        Binding(
            get: { button.action.bundleId ?? "" },
            set: { newValue in
                var updated = button
                updated.action.bundleId = newValue.isEmpty ? nil : newValue
                // Clear the cached icon so resolvedLayout re-fetches from
                // the new bundle on the next send.
                updated.icon = nil
                onChange(updated)
            }
        )
    }
}

private struct ShortcutEditor: View {
    let button: DeckButton
    let onChange: (DeckButton) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledField(label: "Key") {
                TextField("e.g. return, c, 4, space", text: Binding(
                    get: { button.action.shortcut?.key ?? "" },
                    set: { newKey in
                        var updated = button
                        var sc = updated.action.shortcut ?? Shortcut(key: newKey, modifiers: [])
                        sc.key = newKey
                        updated.action.shortcut = sc
                        onChange(updated)
                    }
                ))
            }
            LabeledField(label: "Modifiers") {
                ModifierChips(button: button, onChange: onChange)
            }
            LabeledField(label: "Activate app") {
                TextField("(optional) bundle id", text: Binding(
                    get: { button.action.bundleId ?? "" },
                    set: { newValue in
                        var updated = button
                        updated.action.bundleId = newValue.isEmpty ? nil : newValue
                        updated.icon = nil
                        onChange(updated)
                    }
                ))
            }
        }
    }
}

private struct ModifierChips: View {
    let button: DeckButton
    let onChange: (DeckButton) -> Void

    private let allModifiers: [(Shortcut.Modifier, String)] = [
        (.command, "⌘"),
        (.shift, "⇧"),
        (.option, "⌥"),
        (.control, "⌃"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(allModifiers, id: \.0) { (mod, glyph) in
                let isOn = (button.action.shortcut?.modifiers ?? []).contains(mod)
                Button {
                    var updated = button
                    var mods = updated.action.shortcut?.modifiers ?? []
                    if let i = mods.firstIndex(of: mod) { mods.remove(at: i) }
                    else { mods.append(mod) }
                    updated.action.shortcut = Shortcut(
                        key: updated.action.shortcut?.key ?? "",
                        modifiers: mods
                    )
                    onChange(updated)
                } label: {
                    Text(glyph)
                        .font(.system(size: 14, weight: .medium))
                        .frame(minWidth: 26, minHeight: 26)
                        .background(isOn ? Color.accentColor : Color.gray.opacity(0.15))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

/// Lightweight stand-in for `ContentUnavailableView`, which is macOS 14+;
/// this is small enough to inline so we can target 14.2 without bumping.
private struct ContentUnavailableShim: View {
    let title: String
    let message: String
    init(_ title: String, _ message: String) {
        self.title = title
        self.message = message
    }
    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(title).font(.title3).foregroundStyle(.secondary)
            Text(message).font(.callout).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - DeckButton mutation helper

private extension DeckButton {
    /// Functional setter — returns a copy with the writable key path
    /// updated. Keeps the form bindings terse.
    func with<V>(_ keyPath: WritableKeyPath<Self, V>, setTo value: V) -> Self {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }
}
