import XCTest
@testable import PoorDeck

/// Round-trip coverage for the shareable-pack codec: a pack authored from live
/// pages should survive encode → decode with its buttons, actions, and — most
/// importantly — its embedded artwork intact, so someone importing a `.pdpack`
/// gets exactly what the author saw.
///
/// Host-based test target: `@testable import PoorDeck` reuses the app module, so
/// `PackCodec` (a `@MainActor` enum) and the `Codable` wire types are the real
/// ones. The whole case runs on the main actor to satisfy that isolation.
@MainActor
final class PackCodecTests: XCTestCase {

    // MARK: Fixtures

    /// A keyboard-shortcut button with custom art and the override on — the
    /// DaVinci-Resolve-set shape (no bundle id, its own icon).
    private func shortcutButton(id: String, label: String, key: String) -> DeckButton {
        DeckButton(
            id: id,
            label: label,
            // A transient resolved icon that must NOT ship inside a pack.
            icon: "data:image/png;base64,TRANSIENT",
            customIcon: "data:image/png;base64,CUSTOM_\(id)",
            iconOverride: true,
            symbol: "keyboard",
            action: Action(kind: .keyShortcut, bundleId: nil,
                           shortcut: Shortcut(key: key, modifiers: [.command]),
                           target: nil)
        )
    }

    private func samplePages() -> [Page] {
        [Page(id: "resolve-color", name: "Resolve — Color", columns: 3, buttons: [
            shortcutButton(id: "wipe", label: "Wipe", key: "w"),
            shortcutButton(id: "grab", label: "Grab Still", key: "g"),
        ])]
    }

    // MARK: Tests

    func testRoundTripPreservesButtonsAndArt() throws {
        let pack = PackCodec.makePack(name: "Resolve Pack",
                                      pages: samplePages(),
                                      author: "luc",
                                      summary: "color page")
        let data = try PackCodec.encode(pack)
        let decoded = try PackCodec.decode(data)

        XCTAssertEqual(decoded.format, Pack.currentFormat)
        XCTAssertEqual(decoded.name, "Resolve Pack")
        XCTAssertEqual(decoded.author, "luc")
        XCTAssertEqual(decoded.summary, "color page")
        XCTAssertEqual(decoded.pages.count, 1)

        let page = try XCTUnwrap(decoded.pages.first)
        XCTAssertEqual(page.name, "Resolve — Color")
        XCTAssertEqual(page.columns, 3)
        XCTAssertEqual(page.buttons.map(\.id), ["wipe", "grab"])

        let wipe = page.buttons[0]
        XCTAssertEqual(wipe.label, "Wipe")
        XCTAssertEqual(wipe.customIcon, "data:image/png;base64,CUSTOM_wipe")
        XCTAssertEqual(wipe.iconOverride, true)
        XCTAssertEqual(wipe.action.kind, .keyShortcut)
        XCTAssertEqual(wipe.action.shortcut?.key, "w")
        XCTAssertEqual(wipe.action.shortcut?.modifiers, [.command])
    }

    func testExportDropsTransientIconButKeepsCustomArt() throws {
        let pack = PackCodec.makePack(name: "P", pages: samplePages())
        let button = try XCTUnwrap(pack.pages.first?.buttons.first)
        XCTAssertNil(button.icon,
                     "the transient resolved icon must not be baked into a pack")
        XCTAssertEqual(button.customIcon, "data:image/png;base64,CUSTOM_wipe",
                       "the author's custom art must travel with the pack")
    }

    func testDecodeRejectsForeignJSON() {
        let foreign = Data(#"{"format":"something-else/v9","name":"x","pages":[]}"#.utf8)
        XCTAssertThrowsError(try PackCodec.decode(foreign)) { error in
            guard case PackCodec.PackError.unrecognizedFormat = error else {
                return XCTFail("expected unrecognizedFormat, got \(error)")
            }
        }
    }

    func testEmbedBakesAppIconIntoCustomArtFallback() throws {
        // An app button with no custom art should get the app's own icon baked
        // into customIcon on export, so it still renders on a Mac without that
        // app. Finder is present on every macOS, so this resolves in CI too.
        let page = Page(id: "apps", name: "Apps", columns: 3, buttons: [
            DeckButton(id: "finder", label: "Finder", icon: nil, customIcon: nil,
                       iconOverride: nil, symbol: "folder",
                       action: Action(kind: .openApp, bundleId: "com.apple.finder",
                                      shortcut: nil, target: nil))
        ])
        let pack = PackCodec.makePack(name: "Apps", pages: [page])
        let finder = try XCTUnwrap(pack.pages.first?.buttons.first)

        XCTAssertNil(finder.icon, "transient icon slot is always cleared on export")
        let art = try XCTUnwrap(finder.customIcon,
                                "Finder's icon should be baked into the pack")
        XCTAssertTrue(art.hasPrefix("data:image/"),
                      "baked icon should be a data URL, was \(art.prefix(24))")
    }
}
