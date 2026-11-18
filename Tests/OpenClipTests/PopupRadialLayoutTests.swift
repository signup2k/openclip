import XCTest
import AppKit
import SwiftUI
@testable import Core
@testable import OpenClip

@MainActor
final class PopupRadialLayoutTests: XCTestCase {
    override func setUp() async throws {
        TestIsolation.reset()
    }

    func testPagesPreserveOrderWithAtMostEightTargets() {
        for count in [0, 1, 8, 9, 17, 40] {
            let items = Array(0..<count)
            let pages = PopupRadialLayout.pages(for: items)
            XCTAssertFalse(pages.isEmpty, "An empty catalog still needs its search hub")
            XCTAssertEqual(pages.flatMap { $0 }, items)
            XCTAssertTrue(pages.allSatisfy { $0.count <= 8 })
        }
    }

    func testNeutralHubAndTransparentCornersHaveNoAction() {
        let layout = PopupRadialLayout(itemCount: 8)
        XCTAssertNil(layout.itemIndex(at: layout.center))
        XCTAssertNil(layout.itemIndex(at: CGPoint(x: layout.center.x, y: layout.center.y - layout.innerRadius + 1)))
        XCTAssertNil(layout.itemIndex(at: .zero))
        XCTAssertNil(layout.itemIndex(at: CGPoint(x: layout.diameter, y: layout.diameter)))
        XCTAssertEqual(layout.itemIndex(at: CGPoint(x: layout.center.x, y: layout.center.y - layout.innerRadius - 1)), 0)
    }

    /// Drawing and global hover use different APIs. Compare them throughout the ring so a
    /// mirrored angle or wrong winding cannot highlight one action while clicking another.
    func testDrawnSectorsAgreeWithPointerHitTesting() throws {
        for count in 1...8 {
            for scale: CGFloat in [0.85, 1, 1.22] {
                let layout = PopupRadialLayout(itemCount: count, scale: scale)
                let paths = (0..<count).map {
                    PopupRadialSector(index: $0, itemCount: count,
                                      innerRadiusRatio: layout.innerRadius / layout.outerRadius)
                        .path(in: CGRect(x: 0, y: 0, width: layout.diameter, height: layout.diameter))
                }
                for degrees in stride(from: 0.37, to: 360.0, by: 7) {
                    let angle = degrees * .pi / 180
                    for radius in [layout.innerRadius + 1, (layout.innerRadius + layout.outerRadius) / 2, layout.outerRadius - 1] {
                        let point = CGPoint(x: layout.center.x + radius * cos(angle),
                                            y: layout.center.y + radius * sin(angle))
                        let index = try XCTUnwrap(layout.itemIndex(at: point))
                        XCTAssertTrue(paths[index].contains(point), "count \(count), angle \(degrees), scale \(scale)")
                        XCTAssertEqual(paths.filter { $0.contains(point) }.count, 1, "Clickable sectors must not overlap")
                    }
                }
            }
        }
    }

    func testFirstFrameAndLateResizesStayClampedAtEveryCorner() async throws {
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let store = MemorySettingsStore()
        store.set(.popupLayout, value: "radial")
        let controller = PopupWindowController(settingsStore: store)
        controller.isOnboardingVisible = true
        defer { controller.hide() }
        for x in [screen.minX + 1, screen.maxX - 1] {
            for y in [screen.minY + 1, screen.maxY - 1] {
                let context = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
                                               cursorPosition: CGPoint(x: x, y: y), timestamp: Date(), appPolicy: .default)
                controller.show(for: context)
                let panel = try XCTUnwrap(controller.panel)
                let expected = PopupPositioner.placeAroundCursor(context.cursorPosition, popupSize: PopupMetrics.radialPanelSize(for: 3), screenBounds: screen)
                XCTAssertEqual(panel.frame, expected, "The first frame must already use the final radial size")
                try await Task.sleep(for: .milliseconds(60))
                XCTAssertEqual(panel.frame, expected)
                panel.setFrame(CGRect(x: screen.maxX + 50, y: screen.maxY + 50, width: 400, height: 400), display: false)
                XCTAssertEqual(panel.frame, expected, "A late hosting-view resize must not move the disk off-screen")
            }
        }
    }

    func testLiveRadialHoverResolvesAllSectorsAndClearsInHub() async throws {
        let store = MemorySettingsStore()
        store.set(.popupLayout, value: "radial")
        let hover = PopupHoverState()
        hover.usesGlobalMouseMonitoring = true
        var hoveredID: String?
        let actions = Self.actions
        let view = PopupView(actions: actions, context: Self.context, hoverState: hover, settingsStore: store,
                             onResult: { _ in }, onHoveredActionChanged: { hoveredID = $0?.id })
        let panel = PopupPanel()
        let host = PopupPanel.ContentView(rootView: view)
        panel.contentView = host
        panel.setFrame(CGRect(x: 300, y: 300, width: 176, height: 176), display: false)
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))

        let layout = PopupRadialLayout(itemCount: actions.count)
        for index in actions.indices {
            let point = layout.labelPosition(for: index)
            hover.location = CGPoint(x: point.x + PopupMetrics.popupShadowInset, y: point.y + PopupMetrics.popupShadowInset)
            try await Task.sleep(for: .milliseconds(15))
            XCTAssertEqual(hoveredID, actions[index].id)
        }
        hover.location = CGPoint(x: 88, y: 88)
        try await Task.sleep(for: .milliseconds(15))
        XCTAssertNil(hoveredID)
        XCTAssertFalse(host.isMousePoint(CGPoint(x: 20, y: 20), in: host.bounds))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Radial menu with eight actions"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSearchAndContentReturnToOriginalRadialPlacement() async throws {
        let store = MemorySettingsStore()
        store.set(.popupLayout, value: "radial")
        let mode = PopupModeStore()
        let panel = PopupPanel()
        panel.contentView = PopupPanel.ContentView(rootView: PopupView(
            actions: Self.actions, context: Self.context, settingsStore: store, modeStore: mode, onResult: { _ in }))
        let original = CGRect(x: 250, y: 250, width: 176, height: 176)
        panel.setFrame(original, display: false)
        panel.radialActionFrame = original
        mode.mode = .search
        let expanded = CGRect(x: 220, y: 210, width: 312, height: 280)
        panel.setFrame(expanded, display: false)
        XCTAssertEqual(panel.frame, expanded)
        mode.mode = .actions
        panel.setFrame(CGRect(x: 220, y: 258, width: 176, height: 176), display: false)
        XCTAssertEqual(panel.frame, original)

        mode.mode = .content
        panel.setFrame(expanded, display: false)
        XCTAssertEqual(panel.frame, expanded)
        mode.mode = .actions
        panel.setFrame(expanded, display: false)
        XCTAssertEqual(panel.frame, original)
    }

    static func click(_ point: CGPoint, in host: NSView, panel: NSWindow) {
        let contentPoint = CGPoint(x: point.x, y: host.isFlipped ? point.y : host.bounds.height - point.y)
        let windowPoint = host.convert(contentPoint, to: nil)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: windowPoint, modifierFlags: [], timestamp: 0,
                                      windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: windowPoint, modifierFlags: [], timestamp: 0.01,
                                    windowNumber: panel.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        // Queue mouse-up before dispatching down because native button tracking can consume it
        // synchronously. These events are confined to the test panel, never posted system-wide.
        NSApplication.shared.postEvent(up, atStart: true)
        panel.sendEvent(down)
    }

    func testRightClickOnlyRunsWhenReleasedInThePressedSector() async throws {
        let store = MemorySettingsStore()
        store.set(.popupLayout, value: "radial")
        let registry = ActionRegistry(settingsStore: store)
        let coordinator = ActionCoordinator(registry: registry, settingsStore: store)
        let probe = RadialClickProbe()
        for index in 0..<2 {
            coordinator.register(action: RadialTestAction(id: "action.\(index)", title: "Action \(index)", icon: .symbol("star"),
                                                         onPerform: { context in probe.performed.append((index, context.isSecondaryClick)) }))
        }
        let controller = PopupWindowController(settingsStore: store, actionCoordinator: coordinator)
        controller.show(for: Self.context.selection)
        controller.removeMonitors()
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        let host = try XCTUnwrap(panel.contentView)
        try await Task.sleep(for: .milliseconds(80))
        let page = try XCTUnwrap(controller.modeStore.radialPage)
        let layout = page.layout
        let inset = PopupMetrics.popupShadowInset

        func send(_ type: NSEvent.EventType, at point: CGPoint) throws {
            let contentPoint = CGPoint(x: point.x + inset, y: point.y + inset)
            let local = host.isFlipped ? contentPoint : CGPoint(x: contentPoint.x, y: host.bounds.height - contentPoint.y)
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: host.convert(local, to: nil),
                                                       modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                                       context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
            controller.handleEvent(event)
        }

        let first = layout.labelPosition(for: 0)
        controller.updatePopupHover(at: CGPoint(x: panel.frame.minX + first.x + inset, y: panel.frame.maxY - first.y - inset))
        for missedRelease in [layout.center, layout.labelPosition(for: 1)] {
            try send(.rightMouseDown, at: first)
            try send(.rightMouseUp, at: missedRelease)
        }
        await Task.yield()
        XCTAssertTrue(probe.performed.isEmpty)

        try send(.rightMouseDown, at: first)
        try send(.rightMouseUp, at: first)
        await Task.yield()
        XCTAssertEqual(probe.performed.count, 1)
        XCTAssertEqual(probe.performed.first?.0, 0)
        XCTAssertEqual(probe.performed.first?.1, true)
    }

    func testPageControlsReachLaterActionsWithoutMovingTheDisk() async throws {
        let store = MemorySettingsStore()
        store.set(.popupLayout, value: "radial")
        let probe = RadialClickProbe()
        let actions = (0..<10).map { index in
            RadialTestAction(id: "action.\(index)", title: "Action \(index)", icon: .symbol("star"),
                             onPerform: { context in probe.performed.append((index, context.isSecondaryClick)) })
        }
        let panel = PopupPanel()
        let host = PopupPanel.ContentView(rootView: PopupView(
            actions: actions, context: Self.context, settingsStore: store, onResult: { _ in }))
        panel.contentView = host
        let frame = CGRect(x: 300, y: 300, width: 176, height: 176)
        panel.setFrame(frame, display: false)
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(80))

        Self.click(CGPoint(x: 102, y: 102), in: host, panel: panel) // Next page, inside the hub
        try await Task.sleep(for: .milliseconds(30))
        Self.click(CGPoint(x: 88, y: 46), in: host, panel: panel)
        try await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(probe.performed.last?.0, 8)
        Self.click(CGPoint(x: 88, y: 130), in: host, panel: panel)
        try await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(probe.performed.last?.0, 9)
        XCTAssertEqual(panel.frame, frame)
        Self.click(CGPoint(x: 74, y: 102), in: host, panel: panel) // Previous page
        try await Task.sleep(for: .milliseconds(30))
        Self.click(CGPoint(x: 88, y: 46), in: host, panel: panel)
        try await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(probe.performed.last?.0, 0)
        XCTAssertEqual(panel.frame, frame)
    }

    func testCompletionsUseRadialPagesAndReportTheVisibleCandidate() async throws {
        let store = MemorySettingsStore()
        store.set(.popupLayout, value: "radial")
        let hover = PopupHoverState()
        hover.usesGlobalMouseMonitoring = true
        var hoveredTitle: String?
        var pastedWord: String?
        let panel = PopupPanel()
        let host = PopupPanel.ContentView(rootView: PopupView(
            actions: Self.actions + [RadialCompletionProvider()], context: Self.context,
            hoverState: hover, settingsStore: store,
            onResult: { if case .paste(let word) = $0 { pastedWord = word } },
            onHoveredActionChanged: { hoveredTitle = $0?.title }))
        panel.contentView = host
        panel.setFrame(CGRect(x: 300, y: 300, width: 176, height: 176), display: false)
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(80))
        Self.click(CGPoint(x: 102, y: 102), in: host, panel: panel)
        try await Task.sleep(for: .milliseconds(30))
        hover.location = CGPoint(x: 88, y: 46)
        try await Task.sleep(for: .milliseconds(15))
        XCTAssertEqual(hoveredTitle, "Candidate 8", "Right-click must resolve the candidate from the visible page")
        Self.click(CGPoint(x: 88, y: 46), in: host, panel: panel)
        try await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(pastedWord, "Candidate 8")
        Self.click(CGPoint(x: 88, y: 65), in: host, panel: panel) // Back to actions
        try await Task.sleep(for: .milliseconds(30))
        hover.location = CGPoint(x: 88, y: 47)
        try await Task.sleep(for: .milliseconds(15))
        XCTAssertEqual(hoveredTitle, "Copy")
    }

    private static var context: ActionContext {
        ActionContext(selection: SelectionContext(
            text: "OpenClip", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 400, y: 400), timestamp: Date(), appPolicy: .default), modifiers: [])
    }

    private static var actions: [any Action] {
        [
            RadialTestAction(id: "copy", title: "Copy", icon: .symbol("doc.on.doc")),
            RadialTestAction(id: "search", title: "Search", icon: .symbol("magnifyingglass")),
            RadialTestAction(id: "translate", title: "Translate", icon: .symbol("character.bubble")),
            RadialTestAction(id: "format", title: "Format", icon: .symbol("textformat")),
            RadialTestAction(id: "share", title: "Share", icon: .symbol("square.and.arrow.up")),
            RadialTestAction(id: "calculate", title: "Calculate", icon: .symbol("equal.circle")),
            RadialTestAction(id: "custom", title: "Custom", icon: .text("Custom text")),
            RadialTestAction(id: "ai", title: "AI Tools", icon: .symbol("sparkles"))
        ]
    }
}

private struct RadialTestAction: Action {
    let id: String
    let title: String
    let icon: ActionIcon
    var onPerform: (@MainActor @Sendable (ActionContext) -> Void)? = nil
    var source: ActionChrome.Source = .builtin
    var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: source) }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult {
        onPerform?(context)
        return .none
    }
}

@MainActor
private final class RadialClickProbe {
    var performed: [(Int, Bool)] = []
    var secondary = false
}

private struct RadialCompletionProvider: WordCompletionProviding {
    var id: String { "test.completions" }
    var title: String { "Completions" }
    var icon: ActionIcon { .symbol("text.cursor") }
    var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .provideCompletions, source: .builtin) }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func fetchCompletions(for text: String) -> [String] { (0..<9).map { "Candidate \($0)" } }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
