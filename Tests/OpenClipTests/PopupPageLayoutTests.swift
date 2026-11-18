// PopupPageLayoutTests.swift
// OpenClipTests

import XCTest
import SwiftUI
@testable import OpenClip
@testable import Core

@MainActor
final class PopupPageLayoutTests: XCTestCase {
    private struct StubAction: Action, Sendable {
        let id: String
        let title: String
        let icon: ActionIcon
        var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin) }
        @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
        @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
    }

    func testComputePagesMultiPagePackingWithChevrons() {
        // 12 icon actions = 12 * 34 = 408pt > 340pt
        let actions = (0..<12).map {
            StubAction(id: "act.\($0)", title: "Action \($0)", icon: .symbol("star"))
        }

        let pages = PopupPageLayout.computePages(
            actions: actions,
            leadingWidth: 29.0, // completion chevron
            trailingWidth: 34.0, // search button
            maxBudget: 340.0
        )

        XCTAssertGreaterThan(pages.count, 1, "Must split across multiple pages when total width exceeds budget")
        let flat = pages.flatMap { $0.map(\.id) }
        XCTAssertEqual(flat, actions.map(\.id), "All actions must be preserved across pages without loss")
    }

    func testComputePagesWithWideTextActions() {
        let textActions = (0..<6).map {
            StubAction(id: "ai.\($0)", title: "Text Action \($0)", icon: .text("Very Long Action Label \($0)"))
        }

        let pages = PopupPageLayout.computePages(
            actions: textActions,
            leadingWidth: 0,
            trailingWidth: 0,
            maxBudget: 260.0 // Compact budget
        )

        XCTAssertGreaterThan(pages.count, 1)
        for page in pages {
            let width = PopupPageLayout.measuredBarWidth(
                actions: page,
                hasLeftChevron: true,
                hasRightChevron: true
            )
            XCTAssertLessThanOrEqual(width, 260.0 + 58.0)
        }
    }
}
