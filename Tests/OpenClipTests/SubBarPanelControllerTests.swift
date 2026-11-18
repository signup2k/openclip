// SubBarPanelControllerTests.swift
// OpenClipTests

import XCTest
import AppKit
import SwiftUI
@testable import OpenClip
@testable import Core

@MainActor
final class SubBarPanelControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    private struct TestAction: Action, Sendable {
        let id: String
        let title: String
        let icon: ActionIcon
        var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin) }
        @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
        @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
    }

    private func makeContext() -> ActionContext {
        let selection = SelectionContext(
            text: "test",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: selection)
    }

    func testIsOverContentExcludesShadowRing() {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .symbol("star"))

        let parentFrame = NSRect(x: 200, y: 300, width: 40, height: 29)
        controller.show(
            for: parent,
            parentIndex: 0,
            subActions: [sub1],
            parentButtonScreenFrame: parentFrame,
            searchResultsAbove: true,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )

        let frame = controller.panelFrame
        // Center of panel is interactive content
        let centerPoint = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertTrue(controller.isOverContent(centerPoint))

        // Extreme corner is inside frame but inside transparent shadow ring
        let cornerPoint = CGPoint(x: frame.minX + 2, y: frame.minY + 2)
        XCTAssertFalse(controller.isOverContent(cornerPoint))

        // Outside frame entirely is false
        let outsidePoint = CGPoint(x: frame.minX - 50, y: frame.minY - 50)
        XCTAssertFalse(controller.isOverContent(outsidePoint))

        controller.hide()
    }

    func testSubBarGraceRestartAfterHideAndDwellCancellation() async throws {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .symbol("star"))
        let buttonFrame = NSRect(x: 20000, y: 20000, width: 40, height: 29)

        func showSubBar() {
            controller.show(
                for: parent,
                parentIndex: 0,
                subActions: [sub1],
                parentButtonScreenFrame: buttonFrame,
                searchResultsAbove: true,
                effectiveTheme: "dark",
                effectiveColorScheme: .dark,
                scale: 1.0,
                context: makeContext(),
                presenter: ActionCustomizationManager.shared,
                onResult: { _ in },
                onRunAI: { _ in },
                onRunLoadingAction: { _ in },
                onWillPerformAction: { _ in },
                onActionPerformed: { _ in },
                onClickIntent: { .primary }
            )
        }

        // Test hide() cancellation:
        showSubBar()
        controller.startGrace()
        controller.hide() // Should cancel and clear graceTask
        XCTAssertFalse(controller.isShowing)

        // Show again and start grace
        showSubBar()
        XCTAssertTrue(controller.isShowing)
        controller.startGrace()
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertFalse(controller.isShowing)

        // Test startDwell() cancellation:
        showSubBar()
        controller.startGrace()
        // Calling startDwell when showing fast-switches and cancels grace
        controller.startDwell {
            showSubBar()
        }
        XCTAssertTrue(controller.isShowing)
        controller.startGrace()
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertFalse(controller.isShowing)
    }

    func testSubBarHoverLocationPublishedOnMouseMoveAndClearedOnHide() {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let subBar = SubBarPanelController()
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            subBarController: subBar
        )
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .symbol("star"))
        let buttonFrame = NSRect(x: 200, y: 300, width: 40, height: 29)

        subBar.show(
            for: parent,
            parentIndex: 0,
            subActions: [sub1],
            parentButtonScreenFrame: buttonFrame,
            searchResultsAbove: true,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )

        XCTAssertTrue(subBar.isShowing)

        // Mouse over center of sub-bar
        let center = CGPoint(x: subBar.panelFrame.midX, y: subBar.panelFrame.midY)
        controller.updateSubBarHover(at: center)
        XCTAssertNotNil(SubBarHoverState.shared.location, "SubBarHoverState location must be set when hovering over sub-bar")

        // Mouse moved far away
        let farAway = CGPoint(x: 10, y: 10)
        controller.updateSubBarHover(at: farAway)
        XCTAssertNil(SubBarHoverState.shared.location, "SubBarHoverState location must be nil when cursor is outside sub-bar")

        // Hide clears state
        subBar.hide()
        XCTAssertNil(SubBarHoverState.shared.location)
    }

    func testSubBarVerticalPositionFollowsMainBarAbove() {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .text("One"))

        let parentFrame = NSRect(x: 200, y: 300, width: 40, height: 29)

        // When mainBarAbove is true, sub-bar should be placed ABOVE the main bar's button
        controller.show(
            for: parent,
            parentIndex: 0,
            subActions: [sub1],
            parentButtonScreenFrame: parentFrame,
            searchResultsAbove: false, // even if searchResultsAbove is false, mainBarAbove takes precedence
            mainBarAbove: true,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )

        XCTAssertTrue(controller.isShowing)
        let shadowInset = PopupMetrics.popupShadowInset
        let contentMinY = controller.panelFrame.minY + shadowInset
        XCTAssertGreaterThanOrEqual(contentMinY, parentFrame.maxY, "Sub-bar visual content should sit above parent button")
        controller.hide()
    }
}
