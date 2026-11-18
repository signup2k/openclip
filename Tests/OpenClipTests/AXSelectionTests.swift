import XCTest
import ApplicationServices
import CoreGraphics
@testable import OpenClip

final class AXSelectionTests: XCTestCase {
    func testSelectedTextMarkerRangeFallsBackToWebAreaWhenFocusedElementExposesNoMarker() {
        let focusedEl = AXUIElementCreateApplication(100)
        let webAreaEl = AXUIElementCreateApplication(200)
        let dummyFocusedMarker = "focused-marker-range" as NSString
        let dummyWebMarker = "webarea-marker-range" as NSString

        // Case 1: Focused element exposes marker range -> returns focused element's range
        let fromFocused = AXElementInspector.selectedTextMarkerRange(
            focusedElement: focusedEl,
            webArea: webAreaEl,
            read: { element, _ in
                if CFEqual(element, focusedEl) { return dummyFocusedMarker }
                if CFEqual(element, webAreaEl) { return dummyWebMarker }
                return nil
            }
        )
        XCTAssertEqual(fromFocused as? NSString, dummyFocusedMarker)

        // Case 2: Focused element returns nil, webArea exposes marker range -> falls back to webArea
        let fromWebArea = AXElementInspector.selectedTextMarkerRange(
            focusedElement: focusedEl,
            webArea: webAreaEl,
            read: { element, _ in
                if CFEqual(element, webAreaEl) { return dummyWebMarker }
                return nil
            }
        )
        XCTAssertEqual(fromWebArea as? NSString, dummyWebMarker)

        // Case 3: Both yield nil -> returns nil
        let fromNeither = AXElementInspector.selectedTextMarkerRange(
            focusedElement: focusedEl,
            webArea: webAreaEl,
            read: { _, _ in nil }
        )
        XCTAssertNil(fromNeither)
    }

    private func nativeTarget(
        selectedText: String? = nil,
        value: String? = nil,
        selectedTextRange: AnyObject? = nil,
        bounds: CGRect? = nil
    ) -> AXElementInspector.Target {
        AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: nil,
            role: "AXTextField",
            subRole: nil,
            parentRoles: [],
            containedInRoles: [],
            webArea: nil,
            selectedText: selectedText,
            selectedTextMarkerRange: nil,
            value: value,
            selectedTextRange: selectedTextRange,
            bounds: bounds
        )
    }

    private func cfRangeBox(location: Int, length: Int) -> AnyObject {
        var range = CFRange(location: location, length: length)
        return AXValueCreate(.cfRange, &range)!
    }

    func testReadFallsBackToValueAndSelectedTextRangeSubstring() {
        let bounds = CGRect(x: 5, y: 6, width: 40, height: 4)
        let result = AXTextControlStrategy.read(from: nativeTarget(
            selectedText: "",
            value: "The quick brown fox",
            selectedTextRange: cfRangeBox(location: 4, length: 5),
            bounds: bounds
        ))

        XCTAssertEqual(result?.text, "quick")
        XCTAssertEqual(result?.bounds, bounds)
    }

    func testReadTreatsRangeOffsetsAsUTF16CodeUnits() {
        // "e\u{0301}" is 2 UTF-16 code units but 1 Character; a range selecting just it is
        // location 0, length 2. Character-based offsets would over-read into the trailing "x".
        let bounds = CGRect(x: 1, y: 2, width: 30, height: 4)
        let result = AXTextControlStrategy.read(from: nativeTarget(
            selectedText: "",
            value: "e\u{0301}x",
            selectedTextRange: cfRangeBox(location: 0, length: 2),
            bounds: bounds
        ))

        XCTAssertEqual(result?.text, "e\u{0301}")
        XCTAssertEqual(result?.bounds, bounds)
    }

    private func webTarget(
        webArea: AXUIElement? = nil,
        selectedText: String? = nil,
        selectedTextMarkerRange: AnyObject? = nil,
        bounds: CGRect? = nil
    ) -> AXElementInspector.Target {
        AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: webArea,
            role: "AXWebArea",
            subRole: nil,
            parentRoles: [],
            containedInRoles: [],
            webArea: webArea,
            selectedText: selectedText,
            selectedTextMarkerRange: selectedTextMarkerRange,
            value: nil,
            selectedTextRange: nil,
            bounds: bounds
        )
    }

    func testReadFallsBackToSelectedTextWhenMarkerRangeIsNotAnAXMarker() {
        // The marker range is a plain object, never a real AXTextMarkerRange — the live
        // AXStringForTextMarkerRange conversion cannot run against it, so the strategy must
        // fall back to selectedText.
        let bounds = CGRect(x: 1, y: 2, width: 80, height: 20)
        let result = AXWebAreaStrategy.read(from: webTarget(
            webArea: AXUIElementCreateSystemWide(),
            selectedText: "selected web text",
            selectedTextMarkerRange: "not-a-marker" as NSString,
            bounds: bounds
        ))

        XCTAssertEqual(result?.text, "selected web text")
        XCTAssertEqual(result?.bounds, bounds)
    }
}
