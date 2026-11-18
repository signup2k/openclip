import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

final class ToastPanelControllerTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await MainActor.run {
            TestIsolation.reset()
            UserDefaults.standard.removeObject(forKey: SettingKey.popupScale.name)
            UserDefaults.standard.removeObject(forKey: SettingKey.popupTheme.name)
            UserDefaults.standard.removeObject(forKey: SettingKey.popupThemeColor.name)
            try XCTSkipUnless(NSScreen.main != nil, "no screen")
        }
    }

    /// When near screen boundaries, the toast stays clamped within the visible frame.
    @MainActor
    func testClampsToVisibleFrameWhenPopupNearEdge() throws {
        let visible = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let controller = ToastPanelController()
        let popup = NSRect(x: 300, y: visible.minY + 2, width: 200, height: 40)
        controller.show(StatusFeedback(message: "Copied", style: .success), anchorFrame: popup)
        XCTAssertEqual(controller.panelFrame.midX, popup.midX, accuracy: 1)
        XCTAssertGreaterThanOrEqual(controller.panelFrame.minY + PopupMetrics.toastShadowInset, visible.minY)
        controller.hide()
    }

    @MainActor
    func testAutoDismissAfterDuration() async throws {
        let controller = ToastPanelController(autoDismissNanoseconds: 5_000_000)
        controller.show(StatusFeedback(message: "Copied", style: .success))
        let deadline = Date().addingTimeInterval(2.0)
        while controller.isShowing && Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertFalse(controller.isShowing, "info toast should auto-dismiss")
    }

    /// Regression: the toast must scale with the user's Popup Scale preference, matching the popup
    /// bar it attaches to. `ToastView` reads `SettingKey.popupScale` via @AppStorage; a larger scale
    /// must produce a larger bubble (and vice-versa). The default level 3 must stay byte-identical
    /// to the legacy fixed layout (baseline 77×24), so only the relative growth is asserted.
    @MainActor
    func testToastScalesWithPopupScale() {
        let defaults = UserDefaults.standard
        let key = SettingKey.popupScale.name
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let controller = ToastPanelController()

        defaults.set(5, forKey: key)
        controller.show(StatusFeedback(message: "Copied", style: .success, symbolName: "checkmark"))
        let largeSize = controller.panelFrame.size
        controller.hide()

        defaults.set(1, forKey: key)
        controller.show(StatusFeedback(message: "Copied", style: .success, symbolName: "checkmark"))
        let smallSize = controller.panelFrame.size
        controller.hide()

        XCTAssertGreaterThan(largeSize.height, smallSize.height, "toast panel height must grow with popupScale")
        XCTAssertGreaterThan(largeSize.width, smallSize.width, "toast panel width must grow with popupScale")
    }

    @MainActor
    func testLoadingToastHasNoTimer() async throws {
        let controller = ToastPanelController(autoDismissNanoseconds: 5_000_000)
        controller.showLoading(message: "Opening…")
        try await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertTrue(controller.isShowing, "loading toast must not auto-dismiss")
        controller.hide()
    }

    @MainActor
    func testLoadingToastIsInteractiveAndTogglesIgnoresMouseEvents() {
        let controller = ToastPanelController()
        controller.showLoading(message: "Opening…", onCancel: {})
        XCTAssertFalse(controller.panelIgnoresMouseEvents, "loading toast with onCancel must accept mouse events")

        controller.swapTo(StatusFeedback(message: "Done", style: .info))
        XCTAssertTrue(controller.panelIgnoresMouseEvents, "settled toast must ignore mouse events")
        controller.hide()
        XCTAssertTrue(controller.panelIgnoresMouseEvents, "hidden toast must ignore mouse events")
    }
}
