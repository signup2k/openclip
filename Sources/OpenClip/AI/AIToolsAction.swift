// AIToolsAction.swift
// OpenClip
//
// The "AI Tools" provider-settings row in Preferences. Popup/search exclude this launcher;
// enabled AI presets appear directly instead. Its enable state is single-sourced to
// `AIServiceManager.isAIEnabled`, which the AI-tab and Actions-tab toggles share.
import Foundation
import Core

public struct AIToolsAction: Action {
    public init() {}

    public var id: String { "builtin.aiTools" }
    public var title: String { String(localized: "AI Tools") }
    public var icon: ActionIcon { .symbol(Constants.defaultAIIconSymbol) }
    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin, launchesAI: true)
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        AIServiceManager.shared.isAIEnabled
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .success
    }
}
