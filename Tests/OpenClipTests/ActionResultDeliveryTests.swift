import XCTest
import AppKit
import Core
@testable import OpenClip

final class ActionResultDeliveryTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    /// Asserts `result` equals `expected` by pattern matching (ActionResult is not Equatable).
    private func assertCase(_ result: ActionResult, _ expected: ActionResult, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        switch (result, expected) {
        case (.paste(let a), .paste(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.copy(let a), .copy(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.preview(let a), .preview(let b)), (.text(let a), .text(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.cut(let a), .cut(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.openURL(let a), .openURL(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.success, .success), (.none, .none): XCTAssertTrue(true, message, file: file, line: line)
        default: XCTFail(message.isEmpty ? "unexpected result \(result)" : "\(message): unexpected result \(result)", file: file, line: line)
        }
    }

    // MARK: - Primary/secondary selection

    func testSecondaryWithoutDeclaredSecondaryCopiesPaste() {
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: true, delivery: .none)
        assertCase(r, .copy("a"))
    }

    func testSecondaryUsesDeclaredSecondary() {
        let d = ActionDelivery(secondary: .openURL(URL(string: "https://alt")!))
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: true, delivery: d)
        assertCase(r, .openURL(URL(string: "https://alt")!))
    }

    // MARK: - Probe applies to whichever result is chosen

    func testProbeAppliesToDeclaredPasteSecondary() {
        let d = ActionDelivery(secondary: .paste("a"))
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: false, delivery: d)
        assertCase(r, .copy("a"))   // declared paste still downgrades when target can't paste
    }

    func testProbeAppliesToPrimary() {
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .primary, canPaste: false, delivery: .none)
        assertCase(r, .copy("a"))
    }

    // MARK: - Rich content delivery (pasteContent/copyContent)

    private func assertPayload(_ result: ActionResult, _ expected: ActionResult, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        switch (result, expected) {
        case (.pasteContent(let a), .pasteContent(let b)), (.copyContent(let a), .copyContent(let b)):
            XCTAssertEqual(a.plainText, b.plainText, message, file: file, line: line)
            XCTAssertEqual(a.html, b.html, message, file: file, line: line)
            XCTAssertEqual(a.rtf, b.rtf, message, file: file, line: line)
        default:
            XCTFail(message.isEmpty ? "unexpected result \(result)" : "\(message): unexpected result \(result)", file: file, line: line)
        }
    }

    private var richPayload: RichPasteboardPayload {
        RichPasteboardPayload(plainText: "hi", rtf: nil, html: "<b>hi</b>")
    }

    func testProbeDowngradesRichPasteWhenTargetCannotPaste() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .pasteContent(richPayload), clickIntent: .primary, canPaste: false, delivery: .none)
        assertPayload(r, .copyContent(richPayload))
        XCTAssertEqual(toast?.message, String(localized: "Copied"))
    }

    func testSecondaryClickOnRichPasteDerivesCopyContent() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .pasteContent(richPayload), clickIntent: .secondary, canPaste: true, delivery: .none)
        assertPayload(r, .copyContent(richPayload))
        XCTAssertEqual(toast?.message, String(localized: "Copied"))
    }

    // MARK: - Toast

    func testDefaultToastOnNativeCopy() {
        let (_, toast) = ActionResultDelivery.resolve(raw: .copy("a"), clickIntent: .primary, canPaste: true, delivery: .none)
        XCTAssertEqual(toast?.message, String(localized: "Copied"))
        XCTAssertEqual(toast?.style, .success)
    }

    func testDeclaredPrimaryToastOverridesDefault() {
        let t = StatusFeedback(message: "Saved", style: .info)
        let (_, toast) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .primary, canPaste: true, delivery: ActionDelivery(primaryToast: t))
        XCTAssertEqual(toast, t)
    }

    func testDeclaredSecondaryToastUsed() {
        let t = StatusFeedback(message: "Copied alt", style: .success)
        let (_, toast) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: true, delivery: ActionDelivery(secondaryToast: t))
        XCTAssertEqual(toast, t)
    }

    // MARK: - Implicit returned text (.text) + user preference

    func testTextWithPastePreferencePastesWhenCanPaste() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .primary, canPaste: true, delivery: .none, preference: .paste)
        assertCase(r, .paste("hello"))
        XCTAssertNil(toast, "an honored paste fires no companion toast")
    }

    func testTextWithPastePreferenceCopiesWhenCannotPaste() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .primary, canPaste: false, delivery: .none, preference: .paste)
        assertCase(r, .copy("hello"))
        XCTAssertEqual(toast?.message, String(localized: "Copied"), "a paste context delivered as a copy fires the default Copied toast")
    }

    func testTextWithCopyPreferenceCopiesWithToast() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .primary, canPaste: true, delivery: .none, preference: .copy)
        assertCase(r, .copy("hello"))
        XCTAssertEqual(toast?.message, String(localized: "Copied"), "a delivered copy outcome fires the default Copied toast")
    }

    func testTextWithPreviewPreferenceStaysText() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .primary, canPaste: true, delivery: .none, preference: .preview)
        assertCase(r, .text("hello"))
        XCTAssertNil(toast)
    }

    func testTextNilPreferencePrimaryDefaultsToPaste() {
        let (r, _) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .primary, canPaste: true, delivery: .none)
        assertCase(r, .paste("hello"))
    }

    func testDeclaredSecondaryWinsOverTextPreference() {
        let d = ActionDelivery(secondary: .openURL(URL(string: "https://alt")!))
        let (r, _) = ActionResultDelivery.resolve(raw: .text("a"), clickIntent: .secondary, canPaste: true, delivery: d, preference: .preview)
        assertCase(r, .openURL(URL(string: "https://alt")!))
    }

    // MARK: - Explicit preview

    @MainActor
    func testExplicitPreviewShowsCardWithPastePreference() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "paste")
        let controller = shownController(resultHandler: handler, pasteProbe: FixedProbe(result: true), appPolicy: .default, settingsStore: store)
        defer { controller.hide() }
        controller.deliverResult(.preview("译文"))
        let deadline = Date().addingTimeInterval(3)
        while controller.modeStore.mode != .content && Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(handler.results.isEmpty)
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.modeStore.mode, .content)
    }

    @MainActor
    func testAsyncPasteDowngradesAfterKeyboardOrMouseInteraction() async throws {
        for index in 0..<4 {
            let handler = RecordingHandler()
            let controller = shownController(resultHandler: handler, pasteProbe: FixedProbe(result: true), appPolicy: .default)
            controller.frontmostApplicationProvider = { nil }
            let snapshot = controller.deliverySnapshot()
            var changed = [UInt32](repeating: 0, count: 4)
            changed[index] = 1
            controller.pasteInteractionStampProvider = { changed }
            controller.deliverResult(.paste("translated"), delivery: snapshot)
            assertCase(try await awaitDelivery(from: handler), .copy("translated"))
        }
    }

    // MARK: - Controller wiring: the delivery inputs must be snapshotted before hide() clears them

    @MainActor
    private func awaitDelivery(from handler: RecordingHandler) async throws -> ActionResult {
        let deadline = Date().addingTimeInterval(3.0)
        while handler.results.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertFalse(handler.results.isEmpty, "effect delivery never reached the handler")
        return handler.results.first!
    }

    /// Polls `toast.isLoading` until it flips false (the loading toast fades once the action's
    /// result lands) or the deadline passes — a state-based wait instead of a fixed sleep, so the
    /// assertion isn't flaky on slow machines.
    @MainActor
    private func awaitLoadingFade(toast: ToastPanelController) async {
        let deadline = Date().addingTimeInterval(3.0)
        while toast.isLoading && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// Polls the toast until it shows `message` or the deadline passes — waits for an action's
    /// async `perform` to settle a `.toast` before the test proceeds.
    @MainActor
    private func awaitToastMessage(_ toast: ToastPanelController, _ message: String) async {
        let deadline = Date().addingTimeInterval(3.0)
        while toast.currentFeedback?.message != message && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    @MainActor
    private func shownController(resultHandler: ActionResultHandler,
                                 pasteProbe: PasteAvailabilityProbing,
                                 appPolicy: AppPolicyContext,
                                 toastController: ToastPanelController = ToastPanelController(),
                                 settingsStore: SettingsStore = MemorySettingsStore()) -> PopupWindowController {
        let controller = PopupWindowController(resultHandler: resultHandler, pasteProbe: pasteProbe, toastController: toastController, settingsStore: settingsStore)
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 300, y: 300),
            timestamp: Date(),
            appPolicy: appPolicy
        )
        controller.startTestSession(for: context)
        controller.pasteInteractionStampProvider = { [0, 0, 0, 0] }
        return controller
    }

    /// Regression: a `.paste` result dismisses the popup, and `hide()` clears the live session
    /// context. The denyPaste policy must be captured BEFORE that hide — otherwise the Terminal
    /// escape hatch silently pastes instead of copying. The policy answers inside the unified
    /// decision (no probe consulted), so the "would happily paste" probe is overridden by the rule.
    @MainActor
    func testDeliverResultAppliesDenyPasteDespiteDismissingHide() async throws {
        let handler = RecordingHandler()
        // Probe would happily paste; the denyPaste policy alone must force a copy.
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: AppPolicyContext(denyPaste: true))
        defer { controller.hide() }

        controller.deliverResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
    }

    /// A nil delivery context (an explicit user request, e.g. the AI card's Paste button) must never
    /// be re-decided — even when the probe would say paste is unavailable.
    @MainActor
    func testNilDeliveryPassesPasteThroughUntouched() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: false),
                                         appPolicy: .default)
        defer { controller.hide() }

        controller.handleActionResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .paste("hello"))
    }

    // MARK: - Implicit .text delivery wiring (defaults preserved)

    /// Default settings (primary = paste): an implicit `.text` result delivers a paste and dismisses
    /// the popup — identical to today's string-return behavior.
    @MainActor
    func testTextDeliversPasteAndDismissesWithDefaultSettings() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        controller.deliverResult(.text("hello"))

        assertCase(try await awaitDelivery(from: handler), .paste("hello"))
        XCTAssertFalse(controller.isVisible, "a .text result with a paste preference must dismiss like a paste today")
    }

    /// Default primary = paste + cannot paste → copy with the default "Copied" toast.
    @MainActor
    func testTextDeliversCopyAndCopiedToastWhenCannotPaste() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: false),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.text("hello"))

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
        XCTAssertEqual(toast.currentFeedback?.message, String(localized: "Copied"))
    }

    /// A secondary click with the default secondary = copy: `.text` copies without a toast.
    @MainActor
    func testTextSecondaryCopiesWithDefaultSettings() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        let stub = TextStubAction()
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
        XCTAssertFalse(controller.isVisible)
    }

    // MARK: - Builtin explicit paste/copy never governed by the picker (controller level)

    /// Builtins author explicit outcomes (Copy/Cut/Paste/Calculate/Completion). Even with the
    /// primary picker set to `.preview`, an explicit `.paste` must be delivered as authored (probe
    /// still applies) and dismiss — never routed to the AI result card. Guards the spec's "the
    /// picker never fights an explicit effect" contract at the controller seam, where the `.text`
    /// preview branch could otherwise shadow a future regression.
    @MainActor
    func testExplicitPasteDeliversNotPreviewedWithPreviewPreference() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         settingsStore: store)
        defer { controller.hide() }

        controller.deliverResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .paste("hello"))
        XCTAssertFalse(controller.isVisible, "an explicit paste must dismiss like a paste today")
        XCTAssertEqual(controller.modeStore.mode, .actions, "an explicit paste must never open the preview card")
        XCTAssertNil(controller.modeStore.resultCard)
    }

    // MARK: - Preview routing (implicit .text → AI result card)

    /// Preview preference on a primary click keeps the popup open and renders the returned text in
    /// the native AI result card (content mode) with the performing action's title — no effect is
    /// delivered to the handler.
    @MainActor
    func testTextPreviewKeepsPopupOpenAndShowsCard() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         settingsStore: store)
        defer { controller.hide() }
        controller.pendingActionTitle = "My Action"

        controller.deliverResult(.text("hello"))

        let deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.mode != .content && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(handler.results.isEmpty, "preview must not deliver any effect")
        XCTAssertTrue(controller.isVisible, "preview keeps the popup open")
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "hello")
        XCTAssertEqual(controller.modeStore.resultCard?.title, "My Action")
        XCTAssertFalse(controller.modeStore.resultCard?.isError ?? true)
    }

    /// Preview with cannot-paste hides the card's Paste button (modeStore.canPaste == false).
    @MainActor
    func testTextPreviewHidesPasteWhenCannotPaste() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: false),
                                         appPolicy: .default,
                                         settingsStore: store)
        defer { controller.hide() }
        controller.pendingActionTitle = "My Action"

        controller.deliverResult(.text("hello"))

        let deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.canPaste != false && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(controller.modeStore.canPaste, false, "preview card must gate Paste on the probe answer")
    }

    /// Esc collapses the preview card back to the actions bar (exitContent) without hiding the popup.
    @MainActor
    func testTextPreviewEscCollapsesToBar() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         settingsStore: store)
        defer { controller.hide() }
        controller.pendingActionTitle = "My Action"

        controller.deliverResult(.text("hello"))

        var deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.mode != .content && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        controller.exitContent()

        deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.mode != .actions && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }

        XCTAssertEqual(controller.modeStore.mode, .actions)
        XCTAssertNil(controller.modeStore.resultCard)
        XCTAssertTrue(controller.isVisible, "collapsing the card never hides the popup")
    }

    /// A loading action with preview preference: the spinner hides and the popup re-shows as a
    /// content-mode card using the original selection.
    @MainActor
    func testLoadingTextPreviewReshowsPopupAsCard() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast,
                                         settingsStore: store)
        defer { controller.hide(); toast.hide() }

        controller.runLoadingAction(SlowTextStubAction(text: "loaded"), with: controllerCurrentContext(controller), isSecondaryClick: false)
        XCTAssertTrue(toast.isLoading, "spinner should be visible immediately")

        let deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.mode != .content && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }

        XCTAssertFalse(toast.isLoading, "the spinner must hide when the preview card re-shows")
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "loaded")
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Slow Text")
        XCTAssertTrue(controller.isVisible, "the popup must re-show as the preview card")
        XCTAssertTrue(handler.results.isEmpty)
    }

    // MARK: - Preview routing review follow-ups (declared secondary + pending-state leak)

    /// The right-click perform path (runAction) snapshots the action's declared delivery into its
    /// own DeliveryContext and must not leave `pendingActionTitle`/`pendingDelivery` behind for a
    /// later completion-paste `deliverResult` — the preview card's title comes from the snapshotted
    /// context, and the completion paste must fire no stale declared toast.
    @MainActor
    func testRunActionPreviewDoesNotLeakDeclaredDeliveryOntoCompletionPaste() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let toast = ToastPanelController(autoDismissNanoseconds: 60_000_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast,
                                         settingsStore: store)
        defer { controller.hide(); toast.hide() }

        let declared = StatusFeedback(message: "Saved", style: .info)
        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(primaryToast: declared), performResult: .text("a"))
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: false)

        let deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.mode != .content && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Declared", "the preview card must show the performing action's title")
        XCTAssertNil(controller.pendingActionTitle, "runAction must not leave pendingActionTitle behind")
        XCTAssertNil(controller.pendingDelivery, "runAction must not leave pendingDelivery behind")

        controller.deliverResult(.paste("word"))

        assertCase(try await awaitDelivery(from: handler), .paste("word"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(toast.currentFeedback, "the completion paste must not fire a stale declared toast")
    }

    // MARK: - Toast routing: paste→copy downgrade shows "Copied"; native copy shows nothing

    /// When resultHandler.handle throws an error, the "Copied" success toast is NOT shown (an error status is shown instead).
    @MainActor
    func testDeliveryFailureDoesNotShowCopiedToast() async throws {
        let handler = FailingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: false),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.paste("hello"))

        let deadline = Date().addingTimeInterval(3.0)
        while toast.currentFeedback == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertNotEqual(toast.currentFeedback?.message, String(localized: "Copied"))
        XCTAssertEqual(toast.currentFeedback?.style, .error)
    }

    // MARK: - Loading (slow-action) early-close flow

    @MainActor
    private func controllerCurrentContext(_ controller: PopupWindowController) -> ActionContext {
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 300, y: 300),
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: context, modifiers: [])
    }

    /// When a loading action returns a toast declaring `keepVisible: true`, the settled toast must
    /// still auto-dismiss because the popup was already closed when loading started.
    @MainActor
    func testLoadingActionKeepVisibleToastAutoDismisses() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 30_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.runLoadingAction(KeepVisibleToastLoadingAction(), with: controllerCurrentContext(controller), isSecondaryClick: false)
        XCTAssertTrue(toast.isLoading, "spinner should be visible immediately")
        await awaitLoadingFade(toast: toast)
        XCTAssertEqual(toast.currentFeedback?.message, "Formatted")
        XCTAssertFalse(toast.isLoading)
        let deadline = Date().addingTimeInterval(3.0)
        while toast.isShowing && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertFalse(toast.isShowing, "settled loading toast with keepVisible: true must auto-dismiss")
    }

    /// Clicking cancel (or calling cancelActiveTasks) while a loading action is running
    /// cancels the active task and hides the toast without showing an error banner.
    @MainActor
    func testLoadingActionCancellationDismissesToastWithoutError() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.runLoadingAction(SlowStubAction(), with: controllerCurrentContext(controller), isSecondaryClick: false)
        XCTAssertTrue(toast.isLoading, "spinner should be visible immediately")

        // Cancel the active tasks (same callback triggered when user clicks the loading toast)
        controller.cancelActiveTasks()

        XCTAssertFalse(toast.isLoading, "toast should immediately stop loading")
        XCTAssertFalse(toast.isShowing, "toast should be hidden")
        XCTAssertNil(controller.activeLoadingTask, "activeLoadingTask must be nil after cancellation")

        // Wait slightly to ensure no error toast or result leaks
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(toast.currentFeedback, "no error toast should be surfaced on cancellation")
        XCTAssertTrue(handler.results.isEmpty, "no result should be delivered")
    }

    @MainActor
    func testSupersededActionKeepsTheNextLoadingToastVisible() async {
        let toast = ToastPanelController()
        let controller = shownController(resultHandler: RecordingHandler(), pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default, toastController: toast)
        defer { controller.hide() }
        let context = controllerCurrentContext(controller)
        controller.runLoadingAction(SlowStubAction(), with: context, isSecondaryClick: false)
        let oldTask = controller.activeLoadingTask

        controller.startTestSession(for: context.selection)
        controller.runLoadingAction(SlowStubAction(), with: context, isSecondaryClick: false)
        await oldTask?.value

        XCTAssertTrue(toast.isLoading)
        XCTAssertTrue(toast.isShowing)
    }

    // MARK: - Secondary-click threading: runAction must propagate the click intent into the action context

    /// A right-click (secondary click) on an action must reach `perform` as
    /// `context.isSecondaryClick == true`, so Define returns `.copyDefinition` instead of opening
    /// Dictionary.
    @MainActor
    func testRunActionThreadsSecondaryClickIntoActionContext() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        let probe = SecondaryClickProbeAction()
        controller.runAction(probe, with: controllerCurrentContext(controller), isSecondaryClick: true)

        _ = try await awaitDelivery(from: handler)
        XCTAssertEqual(probe.lastPerformContext?.isSecondaryClick, true, "secondary click must reach the action context")
    }

    // MARK: - Declared delivery wiring: runAction must snapshot the action's delivery and render its toast

    /// An action declaring a distinct secondary outcome + secondary toast: a secondary (right-click)
    /// perform must deliver the declared secondary and surface the declared toast — the controller
    /// snapshots `action.delivery` and renders the resolved tuple's toast.
    @MainActor
    func testRunActionDeliversDeclaredSecondaryAndToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        let url = URL(string: "https://alt")!
        let declared = StatusFeedback(message: "Copied alt", style: .success)
        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(secondary: .openURL(url), secondaryToast: declared))
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .openURL(url))
        XCTAssertEqual(toast.currentFeedback, declared, "the declared secondary toast must surface for a secondary click")
    }

    // MARK: - One toast per run: a script toast wins over the delivery companion

    /// A top-level sequence carrying a script toast suppresses the delivery companion for its
    /// effects: even with a declared primary toast snapshotted onto the delivery, a `.copy` effect
    /// must not surface the declared toast — the script toast wins (one toast per run).
    @MainActor
    func testScriptToastWinsOverDeclaredToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 60_000_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        let scriptToast = StatusFeedback(message: "saved", style: .info)
        controller.pendingDelivery = ActionDelivery(primaryToast: StatusFeedback(message: "declared", style: .info))
        controller.deliverResult(.sequence([.toast(scriptToast), .copy("x")]))

        assertCase(try await awaitDelivery(from: handler), .copy("x"))
        XCTAssertEqual(toast.currentFeedback, scriptToast,
                       "the script toast must win over the declared delivery companion")
    }

    // MARK: - Async delivery context

    @MainActor
    func testAsyncActionCompletingAfterHidePreservesDeliveryPolicyAndContext() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: AppPolicyContext(denyPaste: true))
        let action = SlowPasteStubAction(text: "delayed")
        let context = controller.currentActionContext!

        controller.runAction(action, with: context, isSecondaryClick: false)
        // Dismiss popup while action is executing
        controller.hide()

        let delivered = try await awaitDelivery(from: handler)
        // Must still be .copy because the snapshotted policy had denyPaste, even though hide() was called
        assertCase(delivered, .copy("delayed"))
    }

    @MainActor
    func testAsyncActionDowngradesPasteToCopyWhenTargetAppIsNoLongerActive() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)

        let targetApp = NSWorkspace.shared.runningApplications.first!
        controller.previousFrontmostApp = targetApp

        // When action completes, frontmost application is different (user switched apps)
        let otherApp = NSWorkspace.shared.runningApplications.first { $0.processIdentifier != targetApp.processIdentifier }!
        controller.frontmostApplicationProvider = { otherApp }

        let action = SlowPasteStubAction(text: "unsafe paste")
        let context = controllerCurrentContext(controller)

        controller.runAction(action, with: context, isSecondaryClick: false)

        let delivered = try await awaitDelivery(from: handler)
        // Must downgrade to .copy to avoid pasting into the wrong application
        assertCase(delivered, .copy("unsafe paste"))
        await awaitToastMessage(toast, String(localized: "Copied"))
    }

    func testKeepVisibleToastInSequenceForcesPopupOpen() {
        let seq = ActionResult.sequence([.toast(.init(message: "working", style: .info, keepVisible: true)), .copy("x")])
        XCTAssertFalse(seq.dismissesPopup)
        let dismiss = ActionResult.sequence([.toast(.init(message: "done", style: .success)), .copy("x")])
        XCTAssertTrue(dismiss.dismissesPopup)
    }
}

/// A slow action returning `.paste` after a short delay to model asynchronous background execution.
private final class SlowPasteStubAction: Action, @unchecked Sendable {
    let id = "stub.slowpaste"
    let title = "Slow Paste"
    let icon: ActionIcon = .symbol("sparkles")
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    private let text: String
    init(text: String = "loaded paste") { self.text = text }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        try await Task.sleep(nanoseconds: 30_000_000)
        return .paste(text)
    }
}

/// Records every effect the handler is asked to deliver. @MainActor-isolated, matching the
/// `ActionResultHandler` protocol's main-actor methods.
@MainActor
private final class RecordingHandler: ActionResultHandler, Sendable {
    func pasteText(_ text: String, checking isAllowed: (() -> Bool)?) -> Bool {
        guard isAllowed?() ?? true else { return false }
        results.append(.paste(text))
        return true
    }

    private(set) var results: [ActionResult] = []

    func handle(_ result: ActionResult, in view: NSView?) async throws {
        results.append(result)
    }

    func handleWithoutDismissal(_ result: ActionResult, in view: NSView?) async {
        results.append(result)
    }
}

@MainActor
private final class FailingHandler: ActionResultHandler, Sendable {
    func pasteText(_ text: String, checking isAllowed: (() -> Bool)?) -> Bool { false }

    struct TestError: LocalizedError {
        var errorDescription: String? { "Delivery failed" }
    }
    func handle(_ result: ActionResult, in view: NSView?) async throws {
        throw TestError()
    }
    func handleWithoutDismissal(_ result: ActionResult, in view: NSView?) async {}
}

private struct FixedProbe: PasteAvailabilityProbing {
    let result: Bool?

    func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool? {
        result
    }
}

/// A `showsLoading` action whose perform resolves after a short delay to a description-free
/// `.success` (e.g. Apple Music's empty-stdout AppleScript).
private final class SlowStubAction: Action {
    let id = "stub.slow"
    let title = "Slow"
    let icon: ActionIcon = .symbol("play")
    var chrome: ActionChrome { ActionChrome(source: .builtin, showsLoading: true) }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        try await Task.sleep(nanoseconds: 30_000_000)
        return .success
    }
}

/// A `showsLoading` action that declares its own loading toast text.
/// A `showsLoading` action that returns a toast with `keepVisible: true`.
private final class KeepVisibleToastLoadingAction: Action {
    let id = "stub.keepvisible"
    let title = "Format"
    let icon: ActionIcon = .symbol("text.alignleft")
    var chrome: ActionChrome { ActionChrome(source: .builtin, showsLoading: true) }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        try await Task.sleep(nanoseconds: 20_000_000)
        return .toast(StatusFeedback(message: "Formatted", style: .success, keepVisible: true))
    }
}

/// Records the `ActionContext` handed to `perform` so tests can assert the click intent
/// (isSecondaryClick) threaded through the controller's run path. Mutable state lives in a
/// synchronous lock-protected box so the Sendable `Action` conformance stays race-free.
private final class SecondaryClickProbeAction: Action, @unchecked Sendable {
    let id = "stub.secondary"
    let title = "SecondaryClickProbe"
    let icon: ActionIcon = .symbol("hand.point.right")
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    private let captured = LockedContextBox()
    var lastPerformContext: ActionContext? { captured.value }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        captured.set(context)
        return .copyDefinition(context.selection.text)
    }
}

/// An action carrying a declared `delivery` (secondary outcome + per-click toasts). Its default
/// perform returns a plain `.paste`, so a secondary click derives the declared secondary rather
/// than copying; `performResult` lets tests exercise non-paste results too.
private final class DeclaredDeliveryStub: Action, @unchecked Sendable {
    let id = "stub.declared"
    let title = "Declared"
    let icon: ActionIcon = .symbol("arrow.turn.down.right")
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    var delivery: ActionDelivery? { declaredDelivery }
    private let declaredDelivery: ActionDelivery
    let performResult: ActionResult
    init(delivery: ActionDelivery, performResult: ActionResult = .paste("hello")) {
        self.declaredDelivery = delivery
        self.performResult = performResult
    }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult { performResult }
}

/// An action whose perform returns implicitly returned text (a `.text` result), like the JS string
/// return / AppleScript output / shell stdout / text snippet runtimes.
private final class TextStubAction: Action, @unchecked Sendable {
    let id = "stub.text"
    let title = "Text Action"
    let icon: ActionIcon = .symbol("text.alignleft")
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    private let result: ActionResult
    init(result: ActionResult = .text("hello")) { self.result = result }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult { result }
}

/// A `showsLoading` action returning `.text` after a short delay (loading + preview re-show path).
private final class SlowTextStubAction: Action, @unchecked Sendable {
    let id = "stub.slowtext"
    let title = "Slow Text"
    let icon: ActionIcon = .symbol("text.alignleft")
    var chrome: ActionChrome { ActionChrome(source: .builtin, showsLoading: true) }
    private let text: String
    init(text: String = "loaded") { self.text = text }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        try await Task.sleep(nanoseconds: 30_000_000)
        return .text(text)
    }
}

/// Lock-protected capture box for the context an action performed with (synchronous accessors, so
/// it stays callable from an async `perform`).
private final class LockedContextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: ActionContext?
    func set(_ value: ActionContext) {
        lock.lock(); defer { lock.unlock() }
        storage = value
    }
    var value: ActionContext? {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
