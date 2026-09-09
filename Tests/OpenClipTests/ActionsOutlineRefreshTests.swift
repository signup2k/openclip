import XCTest
import SwiftUI
@testable import Core
@testable import OpenClip

@MainActor
final class ActionsOutlineRefreshTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    private func makeCoordinator() -> ActionsOutlineCoordinator {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let actions = ActionCoordinator(registry: registry, settingsStore: store)
        actions.register(action: CopyAction())
        actions.register(action: PasteAction())
        return ActionsOutlineCoordinator(ActionsOutlineView(
            coordinator: actions,
            customizationManager: ActionCustomizationManager(settingsStore: store),
            selectedRowIDs: .constant([]),
            disabledActionIDs: .constant([]),
            disabledPackages: .constant([]),
            onEditGroup: { _ in },
            onCreateGroupFromSelection: {}
        ))
    }

    func testSelectionAndToggleChangesPreserveExistingNodes() throws {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator.rebuildTree())
        let node = try XCTUnwrap(coordinator.rootNodes.first)
        coordinator.parent = ActionsOutlineView(
            coordinator: coordinator.parent.coordinator,
            customizationManager: coordinator.parent.customizationManager,
            selectedRowIDs: .constant([node.id]),
            disabledActionIDs: .constant([node.id]),
            disabledPackages: .constant([]),
            onEditGroup: { _ in }, onCreateGroupFromSelection: {}
        )
        XCTAssertFalse(coordinator.rebuildTree(), "Navigation/toggle changes must not reload the outline")
        XCTAssertTrue(coordinator.rootNodes.first === node)
    }

    func testLiveAppearanceChangeInvalidatesCachedPresentation() {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator.rebuildTree())
        coordinator.parent.customizationManager.setOverride(for: "builtin.copy", title: "My Copy", symbol: "heart", text: nil)
        XCTAssertTrue(coordinator.rebuildTree(), "Compare against the previous render, not today's store twice")
        XCTAssertFalse(coordinator.rebuildTree())
    }

    func testRegistryChangesRebuildTheTree() {
        let coordinator = makeCoordinator()
        coordinator.rebuildTree()
        coordinator.parent.coordinator.unregister(actionID: "builtin.copy")
        XCTAssertTrue(coordinator.rebuildTree())
        XCTAssertFalse(coordinator.rootNodes.contains { $0.id == "builtin.copy" })
    }

    func testSameIDActionReplacementRefreshesDataWithoutReplacingNode() throws {
        let coordinator = makeCoordinator()
        let original = CustomAction(id: "personal.snippet", title: "Snippet", iconName: "text.alignleft", type: .textSnippet(template: "old"))
        coordinator.parent.coordinator.register(action: original)
        coordinator.rebuildTree()
        let node = try XCTUnwrap(coordinator.rootNodes.first { $0.id == original.id })
        let updated = CustomAction(id: original.id, title: original.title, iconName: original.iconName, type: .textSnippet(template: "new"))
        coordinator.parent.coordinator.register(action: updated)
        XCTAssertFalse(coordinator.rebuildTree())
        XCTAssertTrue(coordinator.rootNodes.first { $0.id == original.id } === node)
        XCTAssertEqual((node.action as? CustomAction)?.type, .textSnippet(template: "new"))
    }
}
