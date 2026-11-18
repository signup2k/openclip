import XCTest
import AppKit
import SwiftUI
@testable import Core
@testable import OpenClip

@MainActor
final class PopupPanelTests: XCTestCase {
    /// Diagnostic: after the real preview path shows the card (panel frame grew), is the card
    /// CONTENT actually drawn, or does the window show stale bar pixels until a hover-state change
    /// forces a redraw? Renders the hosting view to a bitmap and counts non-transparent pixels in
    /// the card-body region (below the header, above the footer).
    @MainActor
    func testPreviewCardBodyIsActuallyDrawn() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            pasteProbe: AICardFixedProbe(result: true),
            settingsStore: store
        )
        let context = SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200),
            timestamp: Date(),
            appPolicy: .default
        )
        controller.show(for: context)
        defer { controller.hide() }
        let panel = try visiblePanel(of: controller)

        let barFrame = panel.frame
        XCTAssertGreaterThan(barFrame.height, 0)

        controller.pendingActionTitle = "Summarize"
        let responseBody = (1...20).map { "line \($0) of a long response body" }.joined(separator: "\n")
        controller.deliverResult(.text(responseBody))

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if panel.frame.height > barFrame.height + 100 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        XCTAssertGreaterThan(panel.frame.height, barFrame.height + 100,
                             "panel did not grow through the real preview path")

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Summarize")
        XCTAssertEqual(controller.modeStore.resultCard?.text, responseBody)
        XCTAssertNotNil(panel.contentView)
    }

    // MARK: - AI streaming session isolation

    private func makeSessionController() -> (PopupWindowController, SelectionContext) {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            pasteProbe: AICardFixedProbe(result: true),
            settingsStore: MemorySettingsStore()
        )
        let context = SelectionContext(
            text: "session text",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 100, y: 100),
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        return (controller, context)
    }

    /// Regression: a stream that outlived its popup kept delivering chunks through the shared
    /// mode store — flipping a NEW selection's popup into content mode and re-sticking
    /// isProcessingAI after hide() cleared it. Session-stamped deliveries must be dropped.
    func testStaleSessionAIChunkCannotHijackCurrentSession() {
        let (controller, _) = makeSessionController()
        let staleSession = controller.aiSessionID

        controller.hide() // dismiss mid-stream ends the session…

        // …but the zombie stream keeps delivering under the OLD token:
        controller.showResultCard(text: "old chunks", isError: false, title: "Old", isStreaming: true, session: staleSession)
        XCTAssertFalse(controller.modeStore.isProcessingAI,
                       "stale processing flag must not stick into the next session")
        XCTAssertEqual(controller.modeStore.mode, .actions,
                       "stale chunk must not flip the popup into content mode")
        XCTAssertNil(controller.modeStore.resultCard,
                     "stale chunk must not populate the result card")

        // The live session still works normally.
        let live = controller.aiSessionID
        controller.showResultCard(text: "fresh", isError: false, title: "New", isStreaming: true, session: live)
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "fresh")
    }

    /// Regression: cancellation was tied to SwiftUI view teardown, which races (or misses) when
    /// the panel is reused across sessions. hide() must cancel the registered stream itself.
    func testHideCancelsRegisteredStreamingTask() {
        let (controller, _) = makeSessionController()

        let task = Task { @MainActor in
            _ = try? await Task.sleep(nanoseconds: 10_000_000_000) // would outlive the session
        }
        // Registration seam is exactly what PopupView hands the controller at spawn.
        controller.activeStreamingTask = task

        controller.hide()

        XCTAssertTrue(task.isCancelled, "hide() must cancel the session's streaming task")
        XCTAssertNil(controller.activeStreamingTask)
    }

    /// Paste availability is probed by the trigger site before selection retrieval and handed to
    /// show(for:pasteAvailable:) — a confirmed cannot-paste must land on `modeStore.canPaste ==
    /// false` synchronously so the card hides its Paste button and the bar/search hide Paste + Cut
    /// on the first frame (no async flash).
    func testPasteAvailabilityGatesBarAndCardSynchronously() {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            pasteProbe: AICardFixedProbe(result: false)
        )
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 100, y: 100),
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context, pasteAvailable: false)
        defer { controller.hide() }

        XCTAssertEqual(controller.modeStore.canPaste, false,
                       "confirmed cannot-paste must gate Paste/Cut from the first frame")
    }

    /// Paste availability tracks the target app's focus context, so it must never be cached per
    /// app: a re-show in the same app applies the freshly-probed value each time.
    func testPasteAvailabilityIsNotCachedAcrossShows() {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            pasteProbe: AICardFixedProbe(result: false)
        )
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 100, y: 100),
            timestamp: Date(),
            appPolicy: .default
        )

        controller.startTestSession(for: context, pasteAvailable: false)
        XCTAssertEqual(controller.modeStore.canPaste, false)
        controller.hide()

        controller.startTestSession(for: context, pasteAvailable: true)
        XCTAssertEqual(controller.modeStore.canPaste, true,
                       "a focus-context change in the same app must apply the fresh probe result")
        controller.hide()
    }

    /// The transparent shadow ring around the bar must be outside the clickable region, so clicks
    /// in the visible shadow fall through to the app underneath instead of being swallowed by the
    /// panel frame (which previously made dismissal impossible there).
    func testShadowRingIsOutsideClickableRegion() {
        let bounds = NSRect(x: 0, y: 0, width: 200, height: 80)
        let inset = PopupMetrics.popupShadowInset

        // Center of the content area: belongs to the popup.
        XCTAssertTrue(PopupPanel.ContentView.isInsideClickableRegion(
            point: NSPoint(x: bounds.midX, y: bounds.midY), bounds: bounds))
        // Just inside the shadow ring boundary (16pt from each edge): still the popup's.
        XCTAssertTrue(PopupPanel.ContentView.isInsideClickableRegion(
            point: NSPoint(x: inset + 1, y: inset + 1), bounds: bounds))
        // Inside the ring itself (e.g. 4pt from the corner): NOT the popup's — click-through.
        XCTAssertFalse(PopupPanel.ContentView.isInsideClickableRegion(
            point: NSPoint(x: 4, y: 4), bounds: bounds))
        XCTAssertFalse(PopupPanel.ContentView.isInsideClickableRegion(
            point: NSPoint(x: inset - 1, y: bounds.midY), bounds: bounds))
    }

    /// The live panel's root view must apply the same rule: points in the shadow ring report as
    /// non-mouse points so the window server routes those clicks to windows below.
    func testLiveContentViewExcludesShadowRingFromHitTesting() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150))
        defer { controller.hide() }
        let panel = try visiblePanel(of: controller)
        let contentView = try XCTUnwrap(panel.contentView as? PopupPanel.ContentView,
                                        "popup must mount PopupPanel.ContentView as its root")
        let bounds = contentView.bounds

        XCTAssertTrue(contentView.isMousePoint(NSPoint(x: bounds.midX, y: bounds.midY), in: bounds),
                      "content-area point must hit-test to the popup")
        XCTAssertFalse(contentView.isMousePoint(NSPoint(x: 2, y: 2), in: bounds),
                       "shadow-ring point must not hit-test to the popup (click-through)")
    }

    private func shownPanel(for cursor: CGPoint, monitorEvents: Bool = false) -> PopupWindowController {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            settingsStore: MemorySettingsStore()
        )
        let context = SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: cursor,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.show(for: context)
        if !monitorEvents {
            // Layout tests exercise the mounted panel without live input or workspace dismissal.
            controller.removeMonitors()
        }
        return controller
    }

    private func visiblePanel(of controller: PopupWindowController) throws -> PopupPanel {
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(panel.isVisible)
        return panel
    }

    private func pump(_ duration: TimeInterval = 2.0) {
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    }

    /// Deterministic paste-availability fake (never blocks, ignores the app argument).
    private struct AICardFixedProbe: PasteAvailabilityProbing {
        let result: Bool?

        func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool? {
            result
        }
    }

    /// Polls until the panel height settles at a value strictly greater than the bar height (i.e.
    /// the search palette has rendered and resized the panel), or the timeout elapses.
    private func waitForSearchResize(_ panel: PopupPanel, barHeight: CGFloat, timeout: TimeInterval = 3.0) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if panel.frame.height > barHeight + 1 { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }

    /// Polls until the panel shrinks back to the bar height (search palette collapsed), or the
    /// timeout elapses.
    private func waitForSearchCollapse(_ panel: PopupPanel, barHeight: CGFloat, timeout: TimeInterval = 3.0) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if panel.frame.height <= barHeight + 1 { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }

    /// Results below the field (popup near top of screen): entering search mode must keep the
    /// panel's TOP edge fixed and grow downward so the field doesn't jump.
    func testSearchModeKeepsTopEdgeFixedForResultsBelow() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel(of: controller)

        XCTAssertFalse(controller.modeStore.searchResultsAbove)
        let barFrame = panel.frame
        XCTAssertGreaterThan(barFrame.height, 0)

        controller.enterSearch()
        waitForSearchResize(panel, barHeight: barFrame.height)
        let searchFrame = panel.frame

        XCTAssertTrue(panel.isVisible, "Search panel closed before completing layout")
        XCTAssertGreaterThan(searchFrame.height, barFrame.height)
        XCTAssertEqual(searchFrame.maxY, barFrame.maxY, accuracy: 1.0,
                       "popup top edge moved by \(searchFrame.maxY - barFrame.maxY)pt entering search mode")
    }

    /// Results ABOVE the field (popup near screen bottom): palette is [results, field], so the field
    /// sits at the palette bottom. The panel must anchor its BOTTOM edge and grow upward, keeping the
    /// field where the bar was.
    func testSearchModeKeepsBottomEdgeFixedForResultsAbove() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150))
        defer { controller.hide() }
        let panel = try visiblePanel(of: controller)

        XCTAssertTrue(controller.modeStore.searchResultsAbove)
        let barFrame = panel.frame
        XCTAssertGreaterThan(barFrame.height, 0)

        controller.enterSearch()
        waitForSearchResize(panel, barHeight: barFrame.height)
        let searchFrame = panel.frame

        XCTAssertTrue(panel.isVisible, "Search panel closed before completing layout")
        XCTAssertGreaterThan(searchFrame.height, barFrame.height)
        XCTAssertEqual(searchFrame.minY, barFrame.minY, accuracy: 1.0,
                       "popup bottom edge moved by \(searchFrame.minY - barFrame.minY)pt entering search mode")
    }

    /// The search field must become the first responder once the panel is key, so typing lands in
    /// the field (not the panel). Exercises both the direct (hotkey-equivalent) entry and a second
    /// entry after exit to catch re-entry timing.
    func testSearchModeMakesPanelKeyAndFieldFirstResponder() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel(of: controller)

        controller.enterSearch()
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if (panel.firstResponder is NSTextView) || (panel.firstResponder is NSTextField) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }

        XCTAssertTrue(panel.isKeyWindow, "panel should be key in search mode")
        let isTextInput = (panel.firstResponder is NSTextView) || (panel.firstResponder is NSTextField)
        XCTAssertTrue(isTextInput,
                      "search field should be first responder, got \(String(describing: panel.firstResponder))")

        // Exit and re-enter search: focus must be re-acquired.
        controller.exitSearch()
        pump(0.05)
        XCTAssertFalse(panel.canBecomeKey, "exit must restore the never-key invariant")

        controller.enterSearch()
        let reenterDeadline = Date().addingTimeInterval(2.0)
        while Date() < reenterDeadline {
            if (panel.firstResponder is NSTextView) || (panel.firstResponder is NSTextField) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        let isTextInputAgain = (panel.firstResponder is NSTextView) || (panel.firstResponder is NSTextField)
        XCTAssertTrue(isTextInputAgain,
                      "search field should be first responder after re-entry, got \(String(describing: panel.firstResponder))")
    }

    func testSetFrameRecenteringClampsToScreenRightEdgeWhenExpanding() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let panel = PopupPanel()
        let visibleFrame = screen.visibleFrame
        let padding = PopupMetrics.popupPadding

        // Narrow panel initially positioned against the right screen edge
        let initialWidth: CGFloat = 100
        let initialX = visibleFrame.maxX - initialWidth - padding
        panel.setFrame(NSRect(x: initialX, y: visibleFrame.midY, width: initialWidth, height: 50), display: false)
        XCTAssertEqual(panel.frame.maxX, visibleFrame.maxX - padding, "precondition: panel is flush with right padding edge")

        panel.recenterXOnResize = true

        // Expand width to 350 (e.g. closing word completions -> wide action bar)
        let expandedWidth: CGFloat = 350
        panel.setFrame(NSRect(x: initialX, y: visibleFrame.midY, width: expandedWidth, height: 50), display: false)

        XCTAssertLessThanOrEqual(panel.frame.maxX, visibleFrame.maxX - padding,
                                 "Expanded panel right edge (\(panel.frame.maxX)) exceeded screen right edge (\(visibleFrame.maxX - padding))")
        XCTAssertEqual(panel.frame.origin.x, visibleFrame.maxX - expandedWidth - padding,
                       "Expanded panel should be clamped flush with right edge")
    }

    func testEnterSearchHonorsButtonPlacementAndRestoresBar() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let cursor = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200)
        let controller = shownPanel(for: cursor)
        defer { controller.hide() }
        let panel = try visiblePanel(of: controller)

        let initialBarFrame = panel.frame
        let buttonWidth: CGFloat = 34
        let buttonLocalX = max(0, initialBarFrame.width - buttonWidth)
        let buttonLocalFrame = CGRect(x: buttonLocalX, y: 0, width: buttonWidth, height: 29)
        // Placement policy caps the palette at the bar's right edge and screen bounds.
        // The controller must apply that position even while resizing from the action bar.
        let expectedMidX = PopupPositioner.searchPaletteMidX(
            buttonScreenMidX: initialBarFrame.minX + buttonLocalFrame.midX,
            barMaxX: initialBarFrame.maxX,
            screenBounds: screen.visibleFrame
        )

        controller.enterSearch(buttonLocalFrame: buttonLocalFrame)
        waitForSearchResize(panel, barHeight: initialBarFrame.height)

        let searchFrame = panel.frame
        XCTAssertEqual(searchFrame.midX, expectedMidX, accuracy: 2.0,
                       "Search palette should honor button placement and edge constraints")

        controller.exitSearch()
        waitForSearchCollapse(panel, barHeight: initialBarFrame.height)
        XCTAssertEqual(panel.frame.midX, initialBarFrame.midX, accuracy: 2.0,
                       "Exiting search should restore the bar's horizontal position")
    }

    func testDistanceDismissalSuspendsWhileAIProcessing() throws {
        let controller = PopupWindowController()
        let panel = PopupPanel()
        let currentMouse = NSEvent.mouseLocation
        panel.setFrame(NSRect(x: currentMouse.x + PopupMetrics.popupDismissalDistance + 200,
                              y: currentMouse.y + PopupMetrics.popupDismissalDistance + 200,
                              width: 200, height: 50), display: false)
        controller.panel = panel
        let context = SelectionContext(
            text: "test",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        defer { controller.hide() }

        XCTAssertTrue(controller.isVisible)

        // When processing AI, distance auto-dismiss must be suspended
        controller.modeStore.isProcessingAI = true

        let farAwayLocation = CGPoint(x: panel.frame.maxX + PopupMetrics.popupDismissalDistance + 100,
                                      y: panel.frame.maxY + PopupMetrics.popupDismissalDistance + 100)
        let farEvent = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: farAwayLocation,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!

        controller.handleEvent(farEvent)
        XCTAssertTrue(controller.isVisible, "Popup must stay visible while AI is processing even when cursor moves far away")

        // When AI processing completes, distance dismissal re-engages
        controller.modeStore.isProcessingAI = false
        controller.handleEvent(farEvent)
        XCTAssertFalse(controller.isVisible, "Popup should dismiss when cursor moves far away and AI is not processing")
    }

    func testRunAIPresetToastDismissedOnHide() {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
                                               settingsStore: MemorySettingsStore())
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 50), display: false)
        controller.panel = panel

        let context = SelectionContext(
            text: "sample selection",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)

        controller.runAIPreset(prompt: "Translate", title: "Translate")
        XCTAssertTrue(controller.toastController.isLoading)

        controller.hide()
        XCTAssertFalse(controller.toastController.isLoading, "Loading toast must be dismissed on hide()")
    }

    func testRunAIPresetStreamsChunksAndTransitionsToResultCard() async {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
                                               settingsStore: MemorySettingsStore())
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 50), display: false)
        controller.panel = panel

        let mockProvider = MockStreamingAIProvider(chunks: ["Hello", " World", "!"])
        AIServiceManager.shared.providerOverride = mockProvider
        defer { AIServiceManager.shared.providerOverride = nil }

        let context = SelectionContext(
            text: "sample selection",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        defer { controller.hide() }

        controller.runAIPreset(prompt: "Translate", title: "Translate")
        XCTAssertTrue(controller.toastController.isLoading)

        // Wait for the streaming task to yield all chunks and complete
        let task = controller.activeStreamingTask
        _ = await task?.value

        XCTAssertFalse(controller.toastController.isLoading, "Loading toast must be dismissed after stream yields")
        XCTAssertEqual(controller.modeStore.mode, .content, "Mode should transition to .content result card")
        XCTAssertEqual(controller.modeStore.resultCard?.text, "Hello World!")
        XCTAssertEqual(controller.modeStore.resultCard?.isError, false)
        XCTAssertEqual(controller.modeStore.resultCard?.isStreaming, false)
    }

    func testAIResultKeepsCopyWhenSourceAppChangesDuringGeneration() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: pasteboard),
                                               pasteProbe: AICardFixedProbe(result: true),
                                               settingsStore: MemorySettingsStore())
        let source = MockPopupFrontmostApp(bundleID: "com.test.source", pid: 101)
        let other = MockPopupFrontmostApp(bundleID: "com.test.other", pid: 102)
        controller.frontmostApplicationProvider = { source }
        controller.pasteInteractionStampProvider = { [0, 0, 0, 0] }
        let selection = SelectionContext(text: "original selection", sourceApp: AppIdentity(bundleIdentifier: source.bundleIdentifier),
                                         cursorPosition: CGPoint(x: 300, y: 300), timestamp: Date(), appPolicy: .default)
        let manager = AIServiceManager.shared
        let previousProvider = manager.providerOverride
        manager.providerOverride = MockStreamingAIProvider(chunks: ["AI result"])
        defer {
            controller.hide()
            manager.providerOverride = previousProvider
        }
        controller.startTestSession(for: selection)
        controller.runAIPreset(prompt: "Explain", title: "Explain")
        controller.frontmostApplicationProvider = { other }
        await controller.activeStreamingTask?.value

        let host = try XCTUnwrap(controller.panel?.contentView as? PopupPanel.ContentView)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "AI result")
        XCTAssertEqual(controller.modeStore.canPaste, false)
        host.rootView.onCardEffect(.paste("AI result"))
        XCTAssertEqual(pasteboard.string(forType: .string), "original clipboard")
        XCTAssertEqual(controller.modeStore.mode, .content)
        host.rootView.onCardEffect(.copy("AI result"))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(pasteboard.string(forType: .string), "AI result")
    }

    func testDirectSearchRunsAIPreset() async throws {
        TestIsolation.reset()
        let manager = AIServiceManager.shared
        let previousProvider = manager.providerOverride
        let provider = MockStreamingAIProvider(chunks: ["Search result"])
        manager.providerOverride = provider
        defer { manager.providerOverride = previousProvider }

        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let coordinator = ActionCoordinator(registry: registry, settingsStore: store)
        coordinator.register(action: AIAction(presetID: "explain", title: "Explain"))
        let controller = PopupWindowController(settingsStore: store, actionCoordinator: coordinator)
        let selection = SelectionContext(text: "Selected with hotkey", sourceApp: AppIdentity(bundleIdentifier: "com.test"),
                                         cursorPosition: CGPoint(x: 300, y: 300), timestamp: Date(), appPolicy: .default)
        controller.show(for: selection, initialMode: .search)
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        let host = try XCTUnwrap(panel.contentView)
        try await Task.sleep(for: .milliseconds(80))

        let firstRowY = PopupMetrics.popupShadowInset + PopupMetrics.searchResultRowHeight / 2
            + (controller.modeStore.searchResultsAbove ? 0 : 36)
        PopupRadialLayoutTests.click(CGPoint(x: host.bounds.midX, y: firstRowY), in: host, panel: panel)
        try await Task.sleep(for: .milliseconds(25))
        await controller.activeStreamingTask?.value

        XCTAssertEqual(provider.lastText, selection.text)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "Search result")
    }

    func testEmptyAIResponseShowsLocalizedErrorCard() async {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
                                               settingsStore: MemorySettingsStore())
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 50), display: false)
        controller.panel = panel

        let mockProvider = MockStreamingAIProvider(chunks: [])
        AIServiceManager.shared.providerOverride = mockProvider
        defer { AIServiceManager.shared.providerOverride = nil }

        let context = SelectionContext(
            text: "sample selection",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        defer { controller.hide() }

        controller.runAIPreset(prompt: "Translate", title: "Translate")
        let task = controller.activeStreamingTask
        _ = await task?.value

        XCTAssertFalse(controller.toastController.isLoading)
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.isError, true)
        XCTAssertEqual(controller.modeStore.resultCard?.text, AIError.invalidResponse.errorDescription)
    }

    func testPopupRendersAndRunsAnAIPresetInBothLayouts() async throws {
        let manager = AIServiceManager.shared
        let previousProvider = manager.providerOverride
        let provider = MockStreamingAIProvider(chunks: ["Explanation result"])
        manager.providerOverride = provider
        defer { manager.providerOverride = previousProvider }

        let explainID = "ai.preset.explain"
        let preset = try XCTUnwrap(manager.preset(forActionID: explainID))
        let aiChrome = ActionChrome(source: .ai)
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let coordinator = ActionCoordinator(registry: registry, settingsStore: store)
        coordinator.register(action: AIToolsAction())
        coordinator.register(action: MockAction(
            id: explainID, shouldBeEnabled: true, chrome: aiChrome, title: "解释"
        ))
        coordinator.register(action: MockAction(
            id: "ai.preset.fix_code", shouldBeEnabled: false, chrome: aiChrome, title: "Fix Code"
        ))

        let screen = try XCTUnwrap(NSScreen.main)
        let selection = SelectionContext(
            text: "Explain this selection", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY),
            timestamp: Date(), appPolicy: .default
        )
        for layout in [PopupLayoutStyle.horizontal, .radial] {
            store.set(.popupLayout, value: layout.rawValue)
            let controller = PopupWindowController(pasteProbe: AICardFixedProbe(result: true),
                                                   settingsStore: store, actionCoordinator: coordinator)
            controller.show(for: selection)
            defer { controller.hide() }

            let panel = try XCTUnwrap(controller.panel)
            let host = try XCTUnwrap(panel.contentView)
            try await Task.sleep(for: .milliseconds(80))
            let inset = PopupMetrics.popupShadowInset
            let firstButton: CGPoint
            if layout == .radial {
                let radius = host.bounds.midX - inset
                firstButton = CGPoint(x: host.bounds.midX, y: host.bounds.midY - 0.7 * radius)
            } else {
                firstButton = CGPoint(x: inset + PopupMetrics.actionButtonWidth / 2, y: host.bounds.midY)
            }
            PopupRadialLayoutTests.click(firstButton, in: host, panel: panel)

            try await Task.sleep(for: .milliseconds(25))
            await controller.activeStreamingTask?.value
            XCTAssertEqual(provider.lastPrompt, preset.prompt)
            XCTAssertEqual(provider.lastText, selection.text)
            XCTAssertEqual(controller.modeStore.resultCard?.title, preset.title, layout.rawValue)
            XCTAssertEqual(controller.modeStore.resultCard?.text, "Explanation result")
        }
    }

    func testWorkspaceApplicationSwitchDismissesPopup() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY), monitorEvents: true)
        defer { controller.hide() }
        XCTAssertTrue(controller.isVisible)

        let switchedApp = MockPopupFrontmostApp(bundleID: "com.apple.Notes")
        let notif = Notification(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: switchedApp]
        )
        NSWorkspace.shared.notificationCenter.post(notif)
        XCTAssertFalse(controller.isVisible, "Popup must dismiss on Cmd+Tab / workspace app activation")
    }

    func testWorkspaceSpaceSwitchDismissesPopup() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY), monitorEvents: true)
        defer { controller.hide() }
        XCTAssertTrue(controller.isVisible)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        XCTAssertFalse(controller.isVisible, "Popup must dismiss on Mission Control active space change")
    }

    func testTrackpadScrollSensitivityThreshold() {
        let controller = PopupWindowController()
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 200, y: 200, width: 200, height: 50), display: false)
        controller.panel = panel
        let context = SelectionContext(
            text: "test",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        defer { controller.hide() }

        XCTAssertTrue(controller.isVisible)

        // Sub-threshold event: began phase with 3pt delta
        let cgBegan = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0)!
        cgBegan.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let eventBegan = NSEvent(cgEvent: cgBegan)!
        controller.handleEvent(eventBegan)
        XCTAssertTrue(controller.isVisible, "Sub-threshold scroll (3pt) should not dismiss popup")

        // Micro-jitter: changed phase with 4pt delta (accumulated 7pt < 12pt)
        let cgChanged = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 4, wheel2: 0, wheel3: 0)!
        cgChanged.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let eventChanged = NSEvent(cgEvent: cgChanged)!
        controller.handleEvent(eventChanged)
        XCTAssertTrue(controller.isVisible, "Accumulated micro-scroll (7pt) should not dismiss popup")

        // Exceeding threshold: changed phase with 6pt delta (accumulated 13pt >= 12pt)
        let cgDismiss = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 6, wheel2: 0, wheel3: 0)!
        cgDismiss.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let eventDismiss = NSEvent(cgEvent: cgDismiss)!
        controller.handleEvent(eventDismiss)
        XCTAssertFalse(controller.isVisible, "Accumulated scroll >= 12pt should dismiss popup")
    }
}

@MainActor
private final class MockStreamingAIProvider: AIProvider {
    let type: AIProviderType = .cloud
    let chunks: [String]
    let error: Error?
    private(set) var lastPrompt: String?
    private(set) var lastText: String?

    init(chunks: [String], error: Error? = nil) {
        self.chunks = chunks
        self.error = error
    }

    func process(prompt: String, text: String) async throws -> String {
        if let error { throw error }
        return chunks.joined()
    }

    func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        lastPrompt = prompt
        lastText = text
        return AsyncThrowingStream { continuation in
            let error = self.error
            let chunks = self.chunks
            Task {
                for chunk in chunks {
                    if Task.isCancelled { break }
                    continuation.yield(chunk)
                    // Small yield so MainActor turns process
                    await Task.yield()
                }
                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
        }
    }
}

private final class MockPopupFrontmostApp: NSRunningApplication {
    private let bundleID: String?
    private let pid: pid_t

    init(bundleID: String?, pid: pid_t = 0) {
        self.bundleID = bundleID
        self.pid = pid
        super.init()
    }

    override var bundleIdentifier: String? { bundleID }
    override var processIdentifier: pid_t { pid }
    override var isTerminated: Bool { false }
}
