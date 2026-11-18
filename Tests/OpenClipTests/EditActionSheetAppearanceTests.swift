import XCTest
@testable import OpenClip
@testable import Core

/// Regression coverage for the edit-actions sheet's appearance save logic: editing only the title
/// must never replace an action's real icon (package file / remote image / text glyph) with the
/// icon picker's placeholder, and legacy overrides written by that old bug heal on the next save.
@MainActor
final class EditActionSheetAppearanceTests: XCTestCase {
    private let localIcon = ActionIcon.local(URL(fileURLWithPath: "/tmp/pkg/icon.svg"))

    // MARK: - resolvedSymbolOverride

    func testTitleOnlyEditDoesNotClobberNonSymbolIcon() {
        // Non-symbol-representable icons leave the field empty ("untouched"); saving must not
        // invent a symbol override.
        XCTAssertNil(EditActionSheet.resolvedSymbolOverride(current: "", initial: "", stored: nil))
    }

    func testPickedReplacementSymbolWinsOverStoredOne() {
        XCTAssertEqual(
            EditActionSheet.resolvedSymbolOverride(current: "bolt.fill", initial: "heart.fill", stored: "heart.fill"),
            "bolt.fill"
        )
    }

    // MARK: - initialDisplayMode

    func testInitialDisplayModeStoredTextOverrideWins() {
        let override = ActionOverride(customIconSymbol: "doc.on.doc", customIconText: "Copy")
        XCTAssertEqual(EditActionSheet.initialDisplayMode(override: override, actionIcon: .text("Copy")), 1)
    }

    // MARK: - resolvedIconModeSymbolOverride (Show Icon mode on text-glyph builtins)

    func testShowIconModePersistsBuiltinPreferenceSymbolForTextGlyphBuiltins() {
        // Copy/Cut/Paste carry `.text` icons by default; switching them to Show Icon must persist
        // their hand-written preference symbol so popupIcon stops resolving the text glyph.
        XCTAssertEqual(
            EditActionSheet.resolvedIconModeSymbolOverride(displayMode: 0, current: "", initial: "", stored: nil, action: CopyAction()),
            "doc.on.doc"
        )
        XCTAssertEqual(
            EditActionSheet.resolvedIconModeSymbolOverride(displayMode: 0, current: "", initial: "", stored: nil, action: CutAction()),
            "scissors"
        )
        XCTAssertEqual(
            EditActionSheet.resolvedIconModeSymbolOverride(displayMode: 0, current: "", initial: "", stored: nil, action: PasteAction()),
            "doc.on.clipboard"
        )
    }

    func testShowTextModeDoesNotPersistBuiltinSymbolForTextGlyphBuiltins() {
        XCTAssertNil(
            EditActionSheet.resolvedIconModeSymbolOverride(displayMode: 1, current: "", initial: "", stored: nil, action: CopyAction())
        )
    }

    // MARK: - sanitizedStoredSymbol (legacy clobber healing)

    func testLegacyStarPlaceholderOnNonSymbolIconsIsTreatedAsAbsent() {
        XCTAssertNil(EditActionSheet.sanitizedStoredSymbol("star", actionIcon: localIcon))
        XCTAssertNil(EditActionSheet.sanitizedStoredSymbol("star", actionIcon: .text("⌘C")))
        XCTAssertNil(EditActionSheet.sanitizedStoredSymbol("star", actionIcon: .url(URL(string: "https://example.com/i.png")!)))
    }

    func testGenuineStarPickOnStarIconedActionIsKept() {
        XCTAssertEqual(EditActionSheet.sanitizedStoredSymbol("star", actionIcon: .symbol("star")), "star")
    }

    // MARK: - resolvedPreviewIcon (ActionAppearanceFields)

    private func preview(
        displayMode: Int,
        title: String = "",
        iconSymbol: String = "",
        initial: String = "",
        base: ActionIcon? = nil,
        textGlyphFallbackSymbol: String? = nil
    ) -> ActionIcon {
        ActionAppearanceFields.resolvedPreviewIcon(
            displayMode: displayMode,
            title: title,
            displayTextFallback: "Native Title",
            iconSymbol: iconSymbol,
            initialIconSymbol: initial,
            baseIcon: base,
            textGlyphFallbackSymbol: textGlyphFallbackSymbol
        )
    }

    func testShowTextModePreviewsEffectiveTitleInsteadOfIcon() {
        XCTAssertEqual(preview(displayMode: 1, title: "  Renamed  ", base: localIcon), .text("Renamed"))
    }

    func testShowIconModePreviewsBuiltinFallbackSymbolForTextGlyphIcons() {
        XCTAssertEqual(
            preview(displayMode: 0, base: .text("Copy"), textGlyphFallbackSymbol: "doc.on.doc"),
            .symbol("doc.on.doc")
        )
    }
}
