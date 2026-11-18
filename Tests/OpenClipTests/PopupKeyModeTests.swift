import XCTest
import AppKit
import Core
@testable import OpenClip

@MainActor
final class PopupKeyModeTests: XCTestCase {

    private func makeController() -> PopupWindowController {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard))
        controller.startTestSession(for: SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 400, y: 400),
            timestamp: Date(),
            appPolicy: .default
        ))
        return controller
    }

    func testKeyedPanelNeverStoresOpenClip() {
        let controller = makeController()
        defer { controller.hide() }
        XCTAssertNotEqual(controller.previousFrontmostApp?.bundleIdentifier, Bundle.main.bundleIdentifier,
                          "a session must never store OpenClip itself as the source app")
        let capturedAtShow = controller.previousFrontmostApp
        controller.enterSearch()
        controller.exitSearch()
        XCTAssertEqual(controller.previousFrontmostApp, capturedAtShow,
                       "only show(for:) captures the source app; enterSearch never re-captures")
        controller.hide()
        XCTAssertNil(controller.previousFrontmostApp, "hide() clears the session capture")
    }

    func testSearchPanelBecomesKeyAndReturnsToNonKey() {
        let panel = PopupPanel()
        XCTAssertFalse(panel.allowsKey)
        panel.allowsKey = true
        XCTAssertTrue(panel.canBecomeKey)
        panel.allowsKey = false
        XCTAssertFalse(panel.canBecomeKey)
    }

    func testSubBarEscapeInterception() {
        let controller = makeController()
        defer { controller.hide() }

        controller.modeStore.isSubBarActive = true
        guard let escEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ) else {
            XCTFail("Failed to construct Escape key event")
            return
        }

        // First Escape closes the sub-bar, but does not call hide()
        controller.handleEvent(escEvent)
        XCTAssertFalse(controller.modeStore.isSubBarActive, "Escape should close the sub-bar")
        XCTAssertTrue(controller.isVisible, "First Escape should keep popup visible")

        // Second Escape dismisses the popup (calling hide())
        controller.handleEvent(escEvent)
        XCTAssertFalse(controller.isVisible, "Second Escape should dismiss the popup")
    }

    func testDirectSearchSessionDismissesOnExitSearch() {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard))
        controller.startTestSession(
            for: SelectionContext(
                text: "hello world",
                sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
                cursorPosition: CGPoint(x: 400, y: 400),
                timestamp: Date(),
                appPolicy: .default
            ),
            initialMode: .search
        )

        XCTAssertTrue(controller.openedDirectlyInSearch, "Direct search start must set openedDirectlyInSearch")
        XCTAssertEqual(controller.modeStore.mode, .search)
        XCTAssertTrue(controller.isVisible)

        controller.exitSearch()
        XCTAssertFalse(controller.isVisible, "exitSearch on a direct search session must dismiss completely")
        XCTAssertFalse(controller.openedDirectlyInSearch, "hide() must clear openedDirectlyInSearch")
    }
}
