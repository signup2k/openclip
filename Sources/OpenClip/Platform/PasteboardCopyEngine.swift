// PasteboardCopyEngine.swift
// OpenClip
//
// Standalone, testable clipboard capture engine: archives every pasteboard type, runs a copy
// trigger, polls for a changeCount advance with non-empty string content, then
// restores the original items tagged with the nspasteboard transient markers.
import AppKit
import Core

/// Corrected pasteboard copy capture: archive → trigger → poll → restore.
///
/// Drives the `.menuCopy` / `.keyboardCopy` retrieval modes via
/// `SelectionRetrievalCoordinator.defaultCopyCapture`, restoring only while no real input has intervened.
@MainActor
public struct PasteboardCopyEngine {
    // MainActor alone does not serialize transactions across polling awaits.
    private static var activePasteboards: Set<NSPasteboard.Name> = []

    /// HID counters exclude our session-tap synthetic copy. Real input invalidates restoration:
    /// in particular, a user copy must never be overwritten by an old clipboard snapshot.
    nonisolated public static func hardwareInputRevision() -> [UInt32] {
        [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].map {
            CGEventSource.counterForEventType(.hidSystemState, eventType: $0)
        }
    }

    public typealias CopyTrigger = @MainActor (Date, @escaping @Sendable () -> Bool) -> Void

    /// Runs `trigger` between archiving the pasteboard and polling for a change.
    ///
    /// - Parameters:
    ///   - pasteboard: The pasteboard to watch (defaults to the system general pasteboard).
    ///   - timeout: Maximum seconds to wait for the pasteboard changeCount to advance and yield text.
    ///     Defaults to a per-app profile: Safari gets a longer budget because its copy path is
    ///     observably slower to stabilize.
    ///   - trigger: Performs the actual copy (AX menu press or keyboard event).
    /// - Returns: The copied text plus HTML/RTF when the source app wrote those representations,
    ///   or `nil` when the changeCount never advances or the copied text is empty.
    public func capture(
        pasteboard: NSPasteboard = .general,
        timeout: TimeInterval? = nil,
        inputRevision: @MainActor () -> [UInt32] = PasteboardCopyEngine.hardwareInputRevision,
        trigger: CopyTrigger
    ) async -> TextResult? {
        let input = inputRevision()
        while Self.activePasteboards.contains(pasteboard.name) {
            do { try await Task.sleep(nanoseconds: 2_000_000) } catch { return nil }
            guard inputRevision() == input else { return nil }
        }
        guard !Task.isCancelled, inputRevision() == input else { return nil }
        Self.activePasteboards.insert(pasteboard.name)
        defer { Self.activePasteboards.remove(pasteboard.name) }

        let snapshot = PasteboardSnapshot.capture(pasteboard)
        let initialChangeCount = pasteboard.changeCount

        guard !Task.isCancelled, inputRevision() == input else { return nil }
        let resolvedTimeout = timeout ?? Self.pollingTimeout()
        let pollInterval: TimeInterval = 0.002
        let deadline = Date().addingTimeInterval(resolvedTimeout)
        let ended = CancellationFlag()
        return await withTaskCancellationHandler {
            defer { ended.set() }
            guard !Task.isCancelled else { return nil }
            trigger(deadline) { !ended.isSet && Date() < deadline }
            var result: TextResult?

            while Date() < deadline && !Task.isCancelled {
                guard inputRevision() == input else { return nil }
                if pasteboard.changeCount != initialChangeCount {
                    let observedChangeCount = pasteboard.changeCount
                    if let candidate = pasteboard.string(forType: .string),
                       TextSanitizer.isSubstantial(candidate) {
                        let html = pasteboard.string(forType: .html) ?? Self.htmlFromRTF(pasteboard)
                        let rtf = pasteboard.string(forType: .rtf)
                        guard pasteboard.changeCount == observedChangeCount else { continue }
                        result = TextResult(text: candidate, bounds: nil, html: html, rtf: rtf)
                        break
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }

            ended.set()

            // A real key cancels the monitor task even if a remapper/automation event does not
            // advance HID counters. Cancellation must also relinquish clipboard restoration.
            // Recheck after promised-data IPC, before writing any archived content back.
            guard !Task.isCancelled, inputRevision() == input else { return nil }
            guard let result else {
                if pasteboard.changeCount != initialChangeCount {
                    Log.selection.debug("Copy engine: no non-empty pasteboard text within deadline; restoring immediately")
                    snapshot.restore(to: pasteboard, transientMarkers: true)
                }
                return nil
            }

            snapshot.restore(to: pasteboard, transientMarkers: true)
            return Task.isCancelled ? nil : result
        } onCancel: {
            ended.set()
        }
    }

    /// Per-app copy polling timeout. Browsers (Chromium, Safari, Firefox, Arc) need more time
    /// for asynchronous multi-process IPC clipboard operations to stabilize; other apps resolve
    /// within the default budget.
    private static func pollingTimeout(for bundleID: String?) -> TimeInterval {
        guard let bundleID else { return Constants.pasteboardCopyTimeout }
        if isBrowser(bundleID) {
            return Constants.safariPasteboardCopyTimeout
        }
        return Constants.pasteboardCopyTimeout
    }

    private static func isBrowser(_ bundleID: String) -> Bool {
        DefaultAppRules.matchesAny(
            DefaultAppRules.safariGroup + DefaultAppRules.chromiumGroup + DefaultAppRules.firefoxGroup + DefaultAppRules.arcGroup,
            bundleID: bundleID
        )
    }

    private static func pollingTimeout() -> TimeInterval {
        pollingTimeout(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    /// Converts a pasteboard's RTF data into HTML. Apps that copy rich text without an HTML
    /// representation (e.g. Obsidian reading mode) expose the formatting only as RTF; the markdown
    /// converter consumes HTML, so normalize here via NSAttributedString rather than reading the
    /// raw RTF control codes as a string.
    private static func htmlFromRTF(_ pasteboard: NSPasteboard) -> String? {
        guard let rtfData = pasteboard.data(forType: .rtf),
              let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil),
              let htmlData = try? attributed.data(
                  from: NSRange(location: 0, length: attributed.length),
                  documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
              ) else { return nil }
        return String(data: htmlData, encoding: .utf8)
    }
}
