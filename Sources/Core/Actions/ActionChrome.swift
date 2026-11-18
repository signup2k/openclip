// ActionChrome.swift
// OpenClip
//
// Defines UI policy metadata structures through the Chrome Door, including badge types, row styles, popup behaviors, and action sources.
// Enables data-driven UI views to inspect action presentation rules without runtime type checking or string matching.
import Foundation

public struct ActionChrome: Codable, Sendable, Equatable {
    public enum Badge: Codable, Sendable, Equatable {
        case none
        case script
        case url
        case custom
        case extensionPkg(String)
    }

    public enum RowStyle: Codable, Sendable, Equatable {
        case standard
        case actionGroup
    }

    public enum PopupBehavior: Codable, Sendable, Equatable {
        case perform
        case showSubActions
        case provideCompletions
    }

    public enum Source: Codable, Sendable, Equatable {
        case builtin
        case custom
        case extensionPkg(packageID: String)
        /// Individual AI preset in Preferences, action search, and the popup when enabled.
        case ai
    }

    public let badge: Badge
    public let rowStyle: RowStyle
    public let popupBehavior: PopupBehavior
    public let source: Source
    /// True when the action reads or mutates the real text selection (e.g. Copy/Cut) and is
    /// therefore unsafe when the text came from the clipboard rather than a live selection.
    public let requiresLiveSelection: Bool
    /// Identifies the AI Tools settings row. The popup and search show individual presets.
    public let launchesAI: Bool
    /// True when the action is slow (e.g. an AppleScript that activates an app) and the popup
    /// should close immediately on click with a spinner toast until the result lands.
    public let showsLoading: Bool
    /// The loading toast's text when `showsLoading` (e.g. "Connecting to Music…"). When nil the
    /// presentation layer falls back to its default ("Opening <title>…").
    public let loadingMessage: String?

    public init(
        badge: Badge = .none,
        rowStyle: RowStyle = .standard,
        popupBehavior: PopupBehavior = .perform,
        source: Source = .builtin,
        requiresLiveSelection: Bool = false,
        launchesAI: Bool = false,
        showsLoading: Bool = false,
        loadingMessage: String? = nil
    ) {
        self.badge = badge
        self.rowStyle = rowStyle
        self.popupBehavior = popupBehavior
        self.source = source
        self.requiresLiveSelection = requiresLiveSelection
        self.launchesAI = launchesAI
        self.showsLoading = showsLoading
        self.loadingMessage = loadingMessage
    }
}
