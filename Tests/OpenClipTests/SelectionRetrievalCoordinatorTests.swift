import XCTest
import ApplicationServices
import CoreGraphics
@testable import Core
@testable import OpenClip

final class SelectionRetrievalCoordinatorTests: XCTestCase {

    private static func textFieldTarget(
        selectedText: String? = nil,
        role: String = "AXTextField",
        bounds: CGRect? = nil
    ) -> AXElementInspector.Target {
        AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: nil,
            role: role,
            subRole: nil,
            parentRoles: [],
            containedInRoles: [],
            webArea: nil,
            selectedText: selectedText,
            selectedTextMarkerRange: nil,
            value: nil,
            selectedTextRange: nil,
            bounds: bounds
        )
    }

    private static func webAreaTarget(selectedText: String) -> AXElementInspector.Target {
        AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: nil,
            role: "AXWebArea",
            subRole: nil,
            parentRoles: ["AXGroup"],
            containedInRoles: ["AXGroup"],
            webArea: nil,
            selectedText: selectedText,
            selectedTextMarkerRange: nil,
            value: nil,
            selectedTextRange: nil,
            bounds: nil
        )
    }

    func testBrowserAddressSelectionNeverCopiesForRetrievalOrEnrichment() async {
        for mode: SelectionRetrievalMode in [.axWebArea, .browserScript, .axTextControl] {
            let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
                inspect: { Self.textFieldTarget(selectedText: "https://example.com") },
                copyCapture: { _ in XCTFail("Address selection must not touch the clipboard"); return nil })
            let result = await coordinator.retrieve(for: AppIdentity(bundleIdentifier: "com.google.Chrome"),
                policy: AppPolicyContext(retrievalMode: mode), cursor: .arrow)
            XCTAssertEqual(result?.text, "https://example.com")
        }
    }

    func testBrowserAddressCaretDoesNotCopyOrReadPage() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget() },
            copyCapture: { _ in XCTFail("An address caret is not a selection"); return nil })
        let result = await coordinator.retrieve(for: AppIdentity(bundleIdentifier: "com.google.Chrome"),
            policy: AppPolicyContext(retrievalMode: .axWebArea), cursor: .unknown)
        XCTAssertNil(result)
    }

    func testSingleClickOnPageNeverReadsOldSelectionOrCopies() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.webAreaTarget(selectedText: "previous selection") },
            copyCapture: { _ in XCTFail("Ordinary clicks must never copy"); return nil })
        let result = await coordinator.retrieve(for: AppIdentity(bundleIdentifier: "com.google.Chrome"),
            policy: AppPolicyContext(retrievalMode: .axWebArea), cursor: .unknown, nativeSelectionOnly: true)
        XCTAssertNil(result)
    }

    // MARK: - Gate

    func testGateSkipsButtonRole() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: "button text", role: "AXButton") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl, gate: .default)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
    }

    func testGateAllowsButtonRoleInsideWebArea() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: {
                AXElementInspector.Target(
                    focusedApp: nil,
                    focusedElement: nil,
                    role: "AXButton",
                    subRole: nil,
                    parentRoles: ["AXWebArea"],
                    containedInRoles: ["AXWebArea"],
                    webArea: nil,
                    selectedText: "button text inside web",
                    selectedTextMarkerRange: nil,
                    value: nil,
                    selectedTextRange: nil,
                    bounds: nil
                )
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl, gate: .default)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "button text inside web")
    }

    func testDisallowedCursorBlocksRetrieval() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: "blocked") }
        )
        let policy = AppPolicyContext(
            retrievalMode: .axTextControl,
            gate: SelectionGatePolicy(allowedCursors: [.beam])
        )
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .arrow
        )
        XCTAssertNil(result)
    }

    // MARK: - Modes

    func testAXTextControlReturnsTextFromFixtureTarget() async {
        let bounds = CGRect(x: 1, y: 2, width: 30, height: 4)
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: "hello", bounds: bounds) }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "hello")
        XCTAssertEqual(result?.bounds, bounds)
    }

    func testAXWebAreaSettleRetryReInspectsUntilTextSettles() async {
        final class InspectCallCount: @unchecked Sendable { var value = 0 }
        let calls = InspectCallCount()
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: {
                calls.value += 1
                if calls.value <= 2 {
                    return Self.webAreaTarget(selectedText: "")
                }
                return Self.webAreaTarget(selectedText: "settled web text")
            },
            copyCapture: { _ in nil }
        )
        let policy = AppPolicyContext(retrievalMode: .axWebArea)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "settled web text")
        XCTAssertGreaterThan(calls.value, 2)
    }

    func testBrowserModeNilFallsBackToKeyboardCopy() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.webAreaTarget(selectedText: "") },
            copyCapture: { _ in TextResult(text: "copy fallback") }
        )
        let policy = AppPolicyContext(retrievalMode: .axWebArea)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Safari"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "copy fallback")
    }

    // MARK: - Copy modes

    func testMenuCopyProceedsWithoutConfirmedSelection() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in TextResult(text: "captured via menu copy") }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy, gate: .default)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "captured via menu copy")
    }

    func testMenuCopyStartsAtMenuCopyEvenWhenAXTextAvailable() async {
        // A menu-copy rule starts the chain at menu copy, so it never performs the AX text strategy
        // above it — even when the target happens to expose AX text.
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: "ax text") },
            copyCapture: { _ in TextResult(text: "captured via menu copy") }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "captured via menu copy")
    }

    func testKeyboardCopyHasNoFallbackBelowIt() async {
        // keyboard-copy is the terminal strategy in the chain, so a failed keyboard copy does not
        // fall through to menu copy.
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in
                counter.calls += 1
                return nil
            }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.microsoft.VSCode"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
        XCTAssertEqual(counter.calls, 1)
    }

    func testMenuCopyHasNoFallbackToKeyboardCopy() async {
        // menu-copy is strict for terminals and does not fall through to keyboard-copy, avoiding double timeouts.
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in
                counter.calls += 1
                return nil
            }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.mitchellh.ghostty"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
        XCTAssertEqual(counter.calls, 1)
    }

    // MARK: - Select-all (⌘A) gating for copy modes

    func testSelectAllMenuCopySkippedOnNonTextElementWithoutSelection() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: "row text", role: "AXTable") },
            copyCapture: { _ in TextResult(text: "should not copy") }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.mail"),
            policy: policy,
            cursor: .unknown,
            isSelectAll: true
        )
        XCTAssertNil(result)
    }

    func testSelectAllDoesNotGateNonCopyModes() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: "selected text") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown,
            isSelectAll: true
        )
        XCTAssertEqual(result?.text, "selected text")
    }

    // MARK: - Fallback cascade

    func testAXTextControlFallsBackToCopyWhenAXReadIsEmpty() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: nil, role: "AXTextArea") },
            copyCapture: { _ in TextResult(text: "copied fallback") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "copied fallback")
    }

    // MARK: - Blank-text filtering

    func testRetrieveRejectsWhitespaceOnlyCopyCapture() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: nil, role: "AXTextArea") },
            copyCapture: { _ in TextResult(text: "  ") }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy, gate: .lenient)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
    }

    func testStrictlyNativeAppDoesNotFallbackToKeyboardCopy() async throws {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in
                counter.calls += 1
                return TextResult(text: "unexpected copy")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let nativeBundleID = try XCTUnwrap(DefaultAppRules.nativeApps.first)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: nativeBundleID),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
        XCTAssertEqual(counter.calls, 0)
    }

    func testNativeAppWithEmbeddedWebAreaCascadesToWebArea() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.webAreaTarget(selectedText: "mail web body") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.mail"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "mail web body")
    }

    // MARK: - Rich-content enrichment

    func testTextOnlyWebAreaWinEnrichesFromPasteboardCapture() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.webAreaTarget(selectedText: "rich selection") },
            copyCapture: { _ in TextResult(text: "rich selection", html: "<b>rich</b> selection") }
        )
        let policy = AppPolicyContext(retrievalMode: .axWebArea)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.google.Chrome"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "rich selection")
        XCTAssertEqual(result?.html, "<b>rich</b> selection")
    }

    func testEnrichmentDoesNotReplaceSelectionWithDifferentClipboardText() async {
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.webAreaTarget(selectedText: "selected text") },
            copyCapture: { _ in TextResult(text: "new user copy", html: "<b>new user copy</b>") }
        )
        let result = await coordinator.retrieve(for: AppIdentity(bundleIdentifier: "com.google.Chrome"),
                                                policy: AppPolicyContext(retrievalMode: .axWebArea), cursor: .unknown)
        XCTAssertEqual(result?.text, "selected text")
        XCTAssertNil(result?.html)
    }

    func testCancelledInspectNeverFallsThroughToCopy() async {
        let started = expectation(description: "inspect started")
        let gate = DispatchSemaphore(value: 0)
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },inspect: {
            started.fulfill()
            gate.wait()
            return Self.textFieldTarget()
        }, copyCapture: { _ in
            XCTFail("Cancelled retrieval must not copy")
            return nil
        })
        let task = Task {
            await coordinator.retrieve(for: AppIdentity(bundleIdentifier: "com.test.app"),
                                       policy: AppPolicyContext(retrievalMode: .keyboardCopy), cursor: .unknown)
        }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        gate.signal()
        let result = await task.value
        XCTAssertNil(result)
    }

    func testWebSettleExhaustionFallsBackToCopyOnce() async {
        actor Counter {
            var calls = 0
            func increment() { calls += 1 }
        }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.webAreaTarget(selectedText: "") },
            copyCapture: { _ in
                await counter.increment()
                return TextResult(text: "fallback")
            }
        )
        let result = await coordinator.retrieve(for: AppIdentity(bundleIdentifier: "com.google.Chrome"),
                                                policy: AppPolicyContext(retrievalMode: .axWebArea), cursor: .unknown)
        XCTAssertEqual(result?.text, "fallback")
        let count = await counter.calls
        XCTAssertEqual(count, 1)
    }

    func testNativeAppTextOnlyWinDoesNotFireCopyCapture() async throws {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: "native text") },
            copyCapture: { _ in
                counter.calls += 1
                return TextResult(text: "unexpected", html: "<b>unexpected</b>")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let nativeBundleID = try XCTUnwrap(DefaultAppRules.nativeApps.first)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: nativeBundleID),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "native text")
        XCTAssertNil(result?.html)
        XCTAssertEqual(counter.calls, 0)
    }

    // MARK: - Inspect concurrency gate

    /// Regression: the permit was released only when the underlying blocking inspect returned,
    /// so one slow/hung app kept every subsequent popup missing for seconds. The permit must free
    /// at the caller's watchdog deadline even while that worker is still parked.
    func testInspectPermitFreesAtWatchdogDeadlineWhileWorkerStillHung() async {
        // Worker #1 parks far past axReadTimeout (0.5s): its caller gets nil from the watchdog
        // while the AX queue thread stays blocked on the semaphore.
        let zombieUnblock = DispatchSemaphore(value: 0)
        defer { zombieUnblock.signal() }
        let hungCoordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: {
                zombieUnblock.wait()
                return Self.textFieldTarget(selectedText: "zombie")
            }
        )
        // A fresh coordinator shares the process-wide gate — proving the permit crossed instances.
        let freshCoordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: "fresh") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)

        let hungResult = await hungCoordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(hungResult, "watchdog must return nil for the hung read")

        // The deadline already settled the hung call; a new retrieval must proceed immediately.
        let freshStart = Date()
        let freshResult = await freshCoordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertLessThan(Date().timeIntervalSince(freshStart), Constants.axReadTimeout,
                          "new read must not wait behind the abandoned hung worker")
        XCTAssertEqual(freshResult?.text, "fresh",
                       "permit must be usable again right after the watchdog deadline")

        zombieUnblock.signal() // release the abandoned AX worker thread
    }

    /// Four blocked Edit ▸ Copy presses must not keep `inspectGate` full.
    /// After `axReadTimeout`, a new inspect must succeed.
    func testFourHungMenuCopyPressesDoNotPermanentlyLockOutInspect() async {
        let starts = PressStartSignal()
        let zombieUnblock = DispatchSemaphore(value: 0)
        defer {
            for _ in 0..<Constants.axMaxConcurrentInspects { zombieUnblock.signal() }
        }

        let hungCoordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { trigger in
                await MainActor.run { trigger(Date().addingTimeInterval(Constants.axReadTimeout), { true }) }
                return nil
            },
            menuPress: { _, _, _ in
                starts.signal()
                zombieUnblock.wait()
            }
        )
        let freshCoordinator = SelectionRetrievalCoordinator(inputRevision: { [] },
            inspect: { Self.textFieldTarget(selectedText: "fresh") }
        )
        let menuPolicy = AppPolicyContext(retrievalMode: .menuCopy)
        let inspectPolicy = AppPolicyContext(retrievalMode: .axTextControl)

        var hungTasks: [Task<TextResult?, Never>] = []
        for index in 1...Constants.axMaxConcurrentInspects {
            hungTasks.append(Task {
                await hungCoordinator.retrieve(
                    for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
                    policy: menuPolicy,
                    cursor: .unknown
                )
            })
            await starts.waitUntil(index)
        }

        let overflowStart = Date()
        let overflow = await freshCoordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: inspectPolicy,
            cursor: .unknown
        )
        XCTAssertNil(overflow, "saturated gate must skip inspect while four hung presses hold permits")
        XCTAssertLessThan(Date().timeIntervalSince(overflowStart), 0.3,
                          "the overflow read must fail fast, not queue")

        try? await Task.sleep(nanoseconds: UInt64((Constants.axReadTimeout + 0.1) * 1_000_000_000))

        let recoveredStart = Date()
        let recovered = await freshCoordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: inspectPolicy,
            cursor: .unknown
        )
        XCTAssertLessThan(Date().timeIntervalSince(recoveredStart), Constants.axReadTimeout,
                          "inspect must not stay locked out after press watchdogs fire")
        XCTAssertEqual(recovered?.text, "fresh")

        for task in hungTasks { _ = await task.value }
    }
}

/// Counts started menu presses.
/// Tests start one blocked `.menuCopy` retrieve at a time.
/// This keeps inspect permits and press permits from overlapping.
private final class PressStartSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func signal() {
        lock.lock()
        count += 1
        let n = count
        let ready = waiters.filter { n >= $0.0 }
        waiters.removeAll { $0.0 <= n }
        lock.unlock()
        ready.forEach { $0.1.resume() }
    }

    func waitUntil(_ target: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if count >= target {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append((target, continuation))
            lock.unlock()
        }
    }
}
