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

    func testAIPresetsAreEditableTopLevelRows() {
        let coordinator = makeCoordinator()
        coordinator.parent.coordinator.register(action: AIToolsAction())
        coordinator.parent.coordinator.register(action: AIAction(presetID: "explain", title: "Explain"))
        coordinator.parent.coordinator.register(action: AIAction(presetID: "summarize", title: "Summarize"))
        coordinator.rebuildTree()
        let presets = coordinator.rootNodes.filter { $0.action.map(ActionIdentity.isAIPreset) == true }
        XCTAssertEqual(presets.map(\.id), ["ai.preset.explain", "ai.preset.summarize"])
        XCTAssertTrue(presets.allSatisfy { $0.children.isEmpty })
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
