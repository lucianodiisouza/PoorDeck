import SwiftUI

/// The Pages tab: a three-pane editor — page list (left), button grid for
/// the selected page (center), and the form for the selected button (right).
///
/// All edits are committed through the `ConfigurationStore`, which persists
/// each change to disk and fires `onChange`, so the server pushes the new
/// layout to connected clients automatically. No explicit "Save" button.
struct LayoutEditorView: View {
    @ObservedObject var store: ConfigurationStore
    @EnvironmentObject private var server: Server
    @State private var selectedPageId: String?
    @State private var selectedButtonId: String?
    @State private var hoveredPageId: String?

    var body: some View {
        HStack(spacing: 0) {
            pageList
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.vertical, 4)
                .padding(.leading, 4)

            buttonGrid
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 4)
                .padding(.horizontal, 4)

            Group {
                if currentButton != nil, let pageId = currentPage?.id {
                    buttonForm
                } else {
                    hintPane
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxHeight: .infinity)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.vertical, 4)
            .padding(.trailing, 4)
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
        let isHovered = hoveredPageId == page.id
        return Button {
            selectedPageId = page.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 16)
                Text(page.name)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(page.buttons.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.18)
                          : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            // Make the whole padded row a hit target, not just the text.
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredPageId = hovering ? page.id : (hoveredPageId == page.id ? nil : hoveredPageId)
        }
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

    // MARK: Canvas (device preview)

    @State private var device: DevicePreview.DeviceFamily = .phone
    @State private var portrait: Bool = true
    @State private var followDevice: Bool = false
    @State private var showGridOptions = false

    private var buttonGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let page = currentPage {
                pageHeader(for: page)

                Divider()
                    .opacity(0.4)

                DevicePreview(
                    page: pageWithIcons(page),
                    device: $device,
                    portrait: $portrait,
                    followDevice: $followDevice,
                    selectedButtonId: selectedButtonId,
                    onSelect: { id in selectedButtonId = id }
                )
            } else {
                ContentUnavailableShim("No page selected",
                                       "Select a page on the left, or add one.")
            }
        }
    }

    /// Canvas header: an editable page title on the left, the primary
    /// "Add button" action on the right, and a compact settings row
    /// beneath it (visible column count + a "Grid options" popover for the
    /// advanced per-orientation overrides and orientation lock).
    private func pageHeader(for page: Page) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                TextField("Page name", text: Binding(
                    get: { page.name },
                    set: { store.updatePage(id: page.id, name: $0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .bold))
                .frame(maxWidth: 320, alignment: .leading)

                Spacer(minLength: 12)

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
                    Label("Add Button", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            HStack(spacing: 10) {
                columnsControl(for: page)
                gridOptionsButton(for: page)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
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

    /// The one column control people reach for every time: a labeled
    /// stepper that stays on the primary settings row. The advanced
    /// per-orientation overrides live behind the "Grid options" popover.
    private func columnsControl(for page: Page) -> some View {
        HStack(spacing: 8) {
            Text("Columns")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            counter(value: page.columns) { store.updatePage(id: page.id, columns: $0) }
        }
    }

    /// Trigger for the advanced layout options. Shows an accent dot when
    /// any override or the orientation lock is active, so a user can tell
    /// something is set without opening the popover.
    private func gridOptionsButton(for page: Page) -> some View {
        let isActive = page.columnsPortrait != nil
            || page.columnsLandscape != nil
            || page.orientationLock != nil
        return Button {
            showGridOptions.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                Text("Grid options")
                    .font(.system(size: 12, weight: .medium))
                if isActive {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .popover(isPresented: $showGridOptions, arrowEdge: .bottom) {
            gridOptionsPopover(for: page)
        }
    }

    /// Advanced layout settings, given room to breathe: per-orientation
    /// column overrides and the orientation lock, each with a full label.
    private func gridOptionsPopover(for page: Page) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Per-orientation columns")
                    .font(.system(size: 13, weight: .semibold))
                Text("Override the column count for one orientation. Off means it follows the default above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            overrideRow(
                title: "Portrait",
                value: page.columnsPortrait,
                fallback: page.columns,
                onEnable: { store.updatePage(id: page.id, columnsPortrait: page.columns) },
                onChange: { store.updatePage(id: page.id, columnsPortrait: $0) },
                onDisable: { store.updatePage(id: page.id, columnsPortrait: nil) }
            )
            overrideRow(
                title: "Landscape",
                value: page.columnsLandscape,
                fallback: page.columns,
                onEnable: { store.updatePage(id: page.id, columnsLandscape: page.columns) },
                onChange: { store.updatePage(id: page.id, columnsLandscape: $0) },
                onDisable: { store.updatePage(id: page.id, columnsLandscape: nil) }
            )

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Orientation lock")
                    .font(.system(size: 13, weight: .semibold))
                Text("Force the client to hold one orientation, ignoring the device sensor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("", selection: Binding<OrientationLock?>(
                    get: { page.orientationLock },
                    set: { store.updatePage(id: page.id, orientationLock: .some($0)) }
                )) {
                    Text("Free").tag(OrientationLock?.none)
                    Text("Portrait").tag(OrientationLock?.some(.portrait))
                    Text("Landscape").tag(OrientationLock?.some(.landscape))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(18)
        .frame(width: 300)
    }

    /// One override row in the Grid options popover: a full-width label,
    /// and either a live counter (+ clear) when set, or a "Default (N)"
    /// button that turns the override on.
    @ViewBuilder
    private func overrideRow(
        title: String,
        value: Int?,
        fallback: Int,
        onEnable: @escaping () -> Void,
        onChange: @escaping (Int) -> Void,
        onDisable: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            if let v = value {
                counter(value: v, onChange: onChange)
                Button(action: onDisable) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Clear the \(title.lowercased()) override")
            } else {
                Button("Default (\(fallback))", action: onEnable)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    /// Compact "− N +" counter. Used for the default columns and the
    /// per-orientation overrides; a stepper's native chevrons are
    /// too tall for an inline toolbar, and they don't line up
    /// across rows the way a hand-rolled counter does.
    @ViewBuilder
    private func counter(value: Int, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 0) {
            Button { onChange(max(1, value - 1)) } label: {
                Image(systemName: "minus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(value <= 1)
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(minWidth: 22, alignment: .center)
            Button { onChange(min(8, value + 1)) } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(value >= 8)
        }
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.15))
        )
    }

    /// Resolve the page's buttons to a copy with icons filled in from the
    /// running apps' icon cache. Without this, the canvas falls back to SF
    /// Symbols for every cell because the persisted `Layout` doesn't carry
    /// the resolved icon data URLs.
    private func pageWithIcons(_ page: Page) -> Page {
        let resolved = DeckStore.shared.resolvedLayout()
        guard let resolvedPage = resolved.pages.first(where: { $0.id == page.id }) else {
            return page
        }
        // Merge: use the resolved buttons' icons when the source button
        // exists in both, but keep the editor's live page as the source of
        // truth for everything else (label, action, symbol, order).
        let iconByID = Dictionary(uniqueKeysWithValues:
            resolvedPage.buttons.map { ($0.id, $0.icon) }
        )
        return Page(
            id: page.id,
            name: page.name,
            columns: page.columns,
            columnsPortrait: page.columnsPortrait,
            columnsLandscape: page.columnsLandscape,
            orientationLock: page.orientationLock,
            buttons: page.buttons.map { btn in
                var copy = btn
                if copy.icon == nil { copy.icon = iconByID[btn.id] ?? nil }
                return copy
            }
        )
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
