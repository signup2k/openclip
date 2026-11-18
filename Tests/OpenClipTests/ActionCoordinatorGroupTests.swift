import XCTest
@testable import Core

@MainActor
final class ActionCoordinatorGroupTests: XCTestCase {
    private var settingsStore: MemorySettingsStore!
    private var coordinator: ActionCoordinator!
    private var registry: ActionRegistry!

    override func setUp() {
        super.setUp()
        settingsStore = MemorySettingsStore()
        registry = ActionRegistry(settingsStore: settingsStore)
        coordinator = ActionCoordinator(registry: registry, settingsStore: settingsStore)
        coordinator.register(action: DummyAction(id: "action.1", title: "Action 1"))
        coordinator.register(action: DummyAction(id: "action.2", title: "Action 2"))
        coordinator.register(action: DummyAction(id: "action.3", title: "Action 3"))
        coordinator.register(action: DummyAction(id: "action.4", title: "Action 4"))
        coordinator.register(action: DummyAction(id: "action.5", title: "Action 5"))
    }

    func testCreateGroupRemovesMembersFromExistingGroupsWithoutDisbanding() {
        // Create Group 1 with actions 1, 2, 3
        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2", "action.3"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 1)
        let group1ID = coordinator.actionGroupDefs[0].id

        // Create Group 2 with action 1 and 4 -> action 1 moves to Group 2; Group 1 retains 2, 3
        coordinator.createGroup(title: "Group 2", iconName: "folder.fill", memberActionIDs: ["action.1", "action.4"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 2)
        XCTAssertEqual(coordinator.actionGroupDefs.first(where: { $0.id == group1ID })?.memberActionIDs, ["action.2", "action.3"])

        // Create Group 3 with action 2 and 3 -> Group 1 is now empty but remains
        coordinator.createGroup(title: "Group 3", iconName: "star", memberActionIDs: ["action.2", "action.3"])
        XCTAssertEqual(coordinator.actionGroupDefs.count, 3)
        XCTAssertEqual(coordinator.actionGroupDefs.first(where: { $0.id == group1ID })?.memberActionIDs, [])
    }

    func testLoadGroupDefsPreservesAllGroupMembersEvenIfTemporarilyUnregistered() throws {
        let defA = ActionGroupDef(id: "vgroup.a", title: "Group A", iconName: "folder", memberActionIDs: ["action.1", "action.2", "nonexistent.1"])
        let defB = ActionGroupDef(id: "vgroup.b", title: "Group B", iconName: "folder", memberActionIDs: ["action.3", "nonexistent.2"])
        let data = try ActionGroupDef.encode([defA, defB])
        settingsStore.set(.actionGroups, value: data)

        coordinator.loadGroupDefs()

        XCTAssertEqual(coordinator.actionGroupDefs.count, 2)
        XCTAssertEqual(coordinator.actionGroupDefs[0].id, "vgroup.a")
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.1", "action.2", "nonexistent.1"])
        XCTAssertEqual(coordinator.actionGroupDefs[1].id, "vgroup.b")
        XCTAssertEqual(coordinator.actionGroupDefs[1].memberActionIDs, ["action.3", "nonexistent.2"])
    }

    func testAddToGroupInsertsAtIndex() {
        coordinator.createGroup(title: "Group 1", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        let groupID = coordinator.actionGroupDefs[0].id

        coordinator.addToGroup(actionID: "action.3", groupID: groupID, atIndex: 1)
        XCTAssertEqual(coordinator.actionGroupDefs[0].memberActionIDs, ["action.1", "action.3", "action.2"])
    }

    func testCoordinatorPreventsIneligibleActionsFromEnteringGroup() {
        let aiTools = DummyAction(
            id: "builtin.ai_tools",
            title: "AI Tools",
            chrome: ActionChrome(popupBehavior: .perform, launchesAI: true)
        )
        let wordCompletion = DummyAction(
            id: "builtin.completion",
            title: "Word Completion",
            chrome: ActionChrome(popupBehavior: .provideCompletions)
        )
        let aiPreset = DummyAction(
            id: "preset.proofread",
            title: "Proofread",
            chrome: ActionChrome(popupBehavior: .perform, source: .ai)
        )
        coordinator.register(action: aiTools)
        coordinator.register(action: wordCompletion)
        coordinator.register(action: aiPreset)

        // Try creating group with ineligible actions
        coordinator.createGroup(
            title: "Mixed Group",
            iconName: "folder",
            memberActionIDs: ["action.1", "builtin.ai_tools", "builtin.completion", "preset.proofread"]
        )
        let group = coordinator.actionGroupDefs.first(where: { $0.title == "Mixed Group" })
        XCTAssertNotNil(group)
        XCTAssertEqual(group?.memberActionIDs, ["action.1"])

        guard let groupID = group?.id else { return }

        // Try adding AI tools
        coordinator.addToGroup(actionID: "builtin.ai_tools", groupID: groupID)
        XCTAssertFalse(coordinator.actionGroupDefs[0].memberActionIDs.contains("builtin.ai_tools"))

        // Try adding word completion
        coordinator.addToGroup(actionID: "builtin.completion", groupID: groupID)
        XCTAssertFalse(coordinator.actionGroupDefs[0].memberActionIDs.contains("builtin.completion"))

        // Try adding AI preset
        coordinator.addToGroup(actionID: "preset.proofread", groupID: groupID)
        XCTAssertFalse(coordinator.actionGroupDefs[0].memberActionIDs.contains("preset.proofread"))

        // Try adding another group into this group
        coordinator.createGroup(title: "Other Group", iconName: "folder", memberActionIDs: ["action.2"])
        let otherGroupID = coordinator.actionGroupDefs.first(where: { $0.title == "Other Group" })!.id
        coordinator.addToGroup(actionID: otherGroupID, groupID: groupID)
        XCTAssertFalse(coordinator.actionGroupDefs.first(where: { $0.id == groupID })!.memberActionIDs.contains(otherGroupID))
    }

    func testUpdateGroupRetainsUnregisteredExistingMember() {
        coordinator.createGroup(title: "Retain Test", iconName: "folder", memberActionIDs: ["action.1", "action.2"])
        guard let groupID = coordinator.actionGroupDefs.first?.id else { return XCTFail() }

        // Unregister action.1 (e.g. extension unloaded or disabled)
        coordinator.unregister(actionID: "action.1")
        XCTAssertFalse(coordinator.actions.contains(where: { $0.id == "action.1" }))

        // Update the group (e.g. renaming or reordering with action.1 still in member list)
        coordinator.updateGroup(
            groupID: groupID,
            title: "Retain Test Renamed",
            iconName: "folder",
            memberActionIDs: ["action.2", "action.1"]
        )

        // Verify that action.1 is retained even though it is currently unregistered
        let group = coordinator.actionGroupDefs.first(where: { $0.id == groupID })
        XCTAssertNotNil(group)
        XCTAssertEqual(group?.memberActionIDs, ["action.2", "action.1"])
        XCTAssertEqual(group?.title, "Retain Test Renamed")
    }
}

private struct DummyAction: Action, Sendable {
    let id: String
    let title: String
    var icon: ActionIcon { .symbol("star") }
    var chrome: ActionChrome

    init(id: String, title: String, chrome: ActionChrome = ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)) {
        self.id = id
        self.title = title
        self.chrome = chrome
    }

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
