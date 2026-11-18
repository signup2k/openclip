// OnboardingWindowControllerTests.swift
// OpenClip
//
// Regression: borderless windows cannot become key by default, which made every
// TextField/SecureField in the onboarding (AI API key step) unusable on first launch.
import XCTest
import SwiftUI
@testable import OpenClip

@MainActor
final class OnboardingWindowControllerTests: XCTestCase {

    func testSandboxTextViewCoordinatorInvokesOnSelection() {
        var selectionFired = false
        let textView = NSTextView()
        textView.string = "Hello World"
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        let coordinator = SandboxTextView.Coordinator(onSelection: {
            selectionFired = true
        })

        let notification = Notification(name: NSTextView.didChangeSelectionNotification, object: textView, userInfo: nil)
        coordinator.textViewDidChangeSelection(notification)

        XCTAssertTrue(selectionFired)
    }
}
