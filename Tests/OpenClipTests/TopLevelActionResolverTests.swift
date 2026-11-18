// TopLevelActionResolverTests.swift
// OpenClipTests
//
// Unit tests for pure TopLevelActionResolver.
import XCTest
@testable import Core

final class TopLevelActionResolverTests: XCTestCase {
    private struct DummyAction: Action, Sendable {
        let id: String
        let title: String
        let icon: ActionIcon
        let chrome: ActionChrome

        init(
            id: String,
            title: String = "Test Action",
            icon: ActionIcon = .symbol("sparkles"),
            chrome: ActionChrome
        ) {
            self.id = id
            self.title = title
            self.icon = icon
            self.chrome = chrome
        }

        func isEnabled(for context: ActionContext) -> Bool { true }
        func perform(_ context: ActionContext) async throws -> ActionResult { .none }
    }

    func testResolvesCustomGroupsAsSingleItemsAndOmitsMembers() {
        let groupAction = CustomGroupAction(
            id: "vgroup.clipboard",
            title: "Clipboard",
            iconName: "folder",
            memberActionIDs: ["builtin.copy", "builtin.paste"]
        )
        let copyAction = DummyAction(
            id: "builtin.copy",
            title: "Copy",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
        )
        let pasteAction = DummyAction(
            id: "builtin.paste",
            title: "Paste",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
        )
        let standaloneAction = DummyAction(
            id: "builtin.upper",
            title: "Uppercase",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
        )

        let actions: [any Action] = [groupAction, copyAction, pasteAction, standaloneAction]
        let customGroupMemberIDs: Set<String> = ["builtin.copy", "builtin.paste"]

        let items = TopLevelActionResolver.resolveTopLevelItems(
            from: actions,
            customGroupMemberIDs: customGroupMemberIDs,
            disabledActionIDs: [],
            isAIEnabled: true
        )

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].id, "vgroup.clipboard")
        XCTAssertEqual(items[0].title, "Clipboard")
        XCTAssertTrue(items[0].isGroup)
        XCTAssertTrue(items[0].isEnabled)

        XCTAssertEqual(items[1].id, "builtin.upper")
        XCTAssertEqual(items[1].title, "Uppercase")
        XCTAssertFalse(items[1].isGroup)
        XCTAssertTrue(items[1].isEnabled)
    }

    func testOmitsAIPresetsAndResolvesAIToolsLauncher() {
        let aiPreset = DummyAction(
            id: "ai.preset.summarize",
            title: "Summarize",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .ai)
        )
        let aiLauncher = DummyAction(
            id: "builtin.ai",
            title: "AI Tools",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin, launchesAI: true)
        )
        let copyAction = DummyAction(
            id: "builtin.copy",
            title: "Copy",
            chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
        )

        let actions: [any Action] = [aiPreset, aiLauncher, copyAction]

        let itemsEnabled = TopLevelActionResolver.resolveTopLevelItems(
            from: actions,
            customGroupMemberIDs: [],
            disabledActionIDs: [],
            isAIEnabled: true
        )

        XCTAssertEqual(itemsEnabled.count, 2)
        XCTAssertEqual(itemsEnabled[0].id, "builtin.ai")
        XCTAssertTrue(itemsEnabled[0].isAI)
        XCTAssertTrue(itemsEnabled[0].isEnabled)
        XCTAssertEqual(itemsEnabled[1].id, "builtin.copy")

        let itemsDisabled = TopLevelActionResolver.resolveTopLevelItems(
            from: actions,
            customGroupMemberIDs: [],
            disabledActionIDs: [],
            isAIEnabled: false
        )

        XCTAssertEqual(itemsDisabled[0].id, "builtin.ai")
        XCTAssertFalse(itemsDisabled[0].isEnabled)
    }
}
