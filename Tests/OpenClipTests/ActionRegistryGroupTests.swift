import XCTest
@testable import Core

@MainActor
final class ActionRegistryGroupTests: XCTestCase {
    private var settingsStore: MemorySettingsStore!
    private var registry: ActionRegistry!

    override func setUp() {
        super.setUp()
        settingsStore = MemorySettingsStore()
        registry = ActionRegistry(settingsStore: settingsStore)
    }

    func testSubActionsPreservesCatalogSortOrderWhenMemberActionIDsDiffer() {
        let a1 = DummyAction(id: "action.1", title: "Action 1")
        let a2 = DummyAction(id: "action.2", title: "Action 2")
        let a3 = DummyAction(id: "action.3", title: "Action 3")
        registry.register(builtIns: [a1, a2, a3])

        // User explicit order: action.3 comes before action.1
        settingsStore.set(.actionOrder, value: ["action.3", "action.1", "action.2"])

        // Group definition has memberActionIDs in opposite order: action.1, action.3
        let def = ActionGroupDef(id: "vgroup.g1", title: "My Group", iconName: "folder", memberActionIDs: ["action.1", "action.3"])
        registry.setGroupDefs([def])

        guard let groupAction = registry.actions.first(where: { $0.id == "vgroup.g1" }) as? CustomGroupAction else {
            return XCTFail("Expected CustomGroupAction")
        }
        // Subactions in catalog should match catalog's sorted order: action.3, action.1
        let subActions = groupAction.subActions(in: registry.actions)
        XCTAssertEqual(subActions.map(\.id), ["action.3", "action.1"])
    }
}

private struct DummyAction: Action, Sendable {
    let id: String
    let title: String
    var icon: ActionIcon { .symbol("star") }
    var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin) }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
