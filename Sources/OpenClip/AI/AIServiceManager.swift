// AIServiceManager.swift
// OpenClip
//
// Manages AI service provider selection, API credentials, and invocation of AI text processing actions.
import Foundation
import os
import SwiftUI
import Core

extension Notification.Name {
    /// Posted by `AIServiceManager` after the AI preset list has been written, so observers
    /// (e.g. `AIActionSync`) can re-register AI actions against the freshly committed list.
    public static let aiActionPresetsDidChange = Notification.Name("OpenClip.AIActionPresetsDidChange")
}

@MainActor
public final class AIServiceManager: ObservableObject {
    public static let shared = AIServiceManager()

    // `@AppStorage` does not automatically publish `objectWillChange`; forward manually
    // so Preferences (and any other observers) refresh when settings change.
    @AppStorage("aiEnabled") public var isAIEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiActiveProvider") public var activeProviderRaw: String = AIProviderType.apple.rawValue {
        willSet { objectWillChange.send() }
    }
    public var cloudAPIKey: String {
        guard let account = cloudCredentialAccount else { return "" }
        return SecretStore.get(account: account) ?? ""
    }

    func setCloudAPIKey(_ key: String, account: String) -> Bool {
        objectWillChange.send()
        let saved = key.isEmpty
            ? SecretStore.delete(account: account)
            : SecretStore.set(key, account: account)
        if !saved {
            Log.settings.error("Failed to update the cloud API key in SecretStore")
        }
        return saved
    }

    @AppStorage("aiCloudService") public var cloudServiceRaw: String = "openai" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiCloudCustomURL") public var cloudCustomURL: String = "" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiCloudModel") public var cloudModel: String = "gpt-4o-mini" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiOllamaURL") public var ollamaURL: String = "http://localhost:11434" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiOllamaModel") public var ollamaModel: String = "llama3" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiBrowserPreset") public var browserPreset: String = "chatgpt" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiBrowserURLTemplate") public var browserURLTemplate: String = "https://chatgpt.com/?q={text}" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("aiActionPresetsJSON") public var actionPresetsJSON: String = "" {
        willSet { objectWillChange.send() }
    }

    public static let defaultPresets: [AIActionPreset] = [
        AIActionPreset(id: "proofread", title: String(localized: "Proofread"), prompt: String(localized: "Fix all spelling, punctuation, and grammatical errors while preserving the original wording, tone, and formatting"), isEnabled: true),
        AIActionPreset(id: "rewrite", title: String(localized: "Rewrite"), prompt: String(localized: "Rewrite to improve clarity, flow, and vocabulary while keeping the original meaning and language"), isEnabled: true),
        AIActionPreset(id: "summarize", title: String(localized: "Summarize"), prompt: String(localized: "Provide a concise bulleted summary capturing the key points"), isEnabled: true),
        AIActionPreset(id: "explain", title: String(localized: "Explain"), prompt: String(localized: "Search and analyze, then ELI25. Explain concisely in Chinese:"), isEnabled: true),
        AIActionPreset(id: "translate", title: String(localized: "Translate"), prompt: String(localized: "Translate the text accurately into natural English"), isEnabled: true),
        AIActionPreset(id: "fix_code", title: String(localized: "Fix Code"), prompt: String(localized: "Fix bugs, syntax errors, and logic issues in this code snippet. Return only the raw working code without markdown code blocks or explanations"), isEnabled: false),
        AIActionPreset(id: "make_shorter", title: String(localized: "Make Shorter"), prompt: String(localized: "Condense this text to be as concise as possible while keeping all essential information"), isEnabled: false),
        AIActionPreset(id: "formal_tone", title: String(localized: "Formal Tone"), prompt: String(localized: "Rewrite this text in a polished, professional, and formal tone"), isEnabled: false)
    ]

    private static let presetDecodeFailureLogged = OSAllocatedUnfairLock(initialState: false)

    public var presets: [AIActionPreset] {
        get {
            guard !actionPresetsJSON.isEmpty,
                  let data = actionPresetsJSON.data(using: .utf8) else {
                return Self.defaultPresets
            }
            if let decoded = try? JSONDecoder().decode([AIActionPreset].self, from: data) {
                return decoded
            }
            Self.presetDecodeFailureLogged.withLock { alreadyLogged in
                guard !alreadyLogged else { return }
                alreadyLogged = true
                Log.ai.error("Failed to decode saved AI action presets; using defaults")
            }
            return Self.defaultPresets
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                actionPresetsJSON = str
            } else {
                Log.ai.error("Failed to encode AI action presets for persistence")
            }
            // Posted after the value above has committed, so observers always read the fresh list
            // (objectWillChange fires before @AppStorage lands). AIActionSync keeps the registered
            // AI actions in step with this list.
            NotificationCenter.default.post(name: .aiActionPresetsDidChange, object: self)
        }
    }

    public func updatePreset(_ updated: AIActionPreset) {
        var current = presets
        if let idx = current.firstIndex(where: { $0.id == updated.id }) {
            current[idx] = updated
        } else {
            current.append(updated)
        }
        presets = current
    }

    /// Maps a registered AI action id (`ai.preset.<presetID>`, see `AIAction`) back to its live
    /// preset, so palette/preferences routing can resolve the preset without touching `AIAction`'s
    /// internals.
    public func preset(forActionID actionID: String) -> AIActionPreset? {
        let prefix = "ai.preset."
        guard actionID.hasPrefix(prefix) else { return nil }
        let presetID = String(actionID.dropFirst(prefix.count))
        return presets.first { $0.id == presetID }
    }

    public func resetPresetsToDefault() {
        presets = Self.defaultPresets
    }

    private static let legacyCloudAPIKeyAccount = "aiCloudAPIKey"

    var cloudCredentialAccount: String? {
        Self.cloudCredentialAccount(for: cloudServiceProvider, customURL: cloudCustomURL)
    }

    private static func cloudCredentialAccount(for service: CloudServiceProvider, customURL: String) -> String? {
        let baseURL = CloudAPIProvider.resolveBaseURL(provider: service, customBaseURL: customURL)
        guard let url = URL(string: baseURL), let origin = CloudAPIProvider.origin(of: url) else { return nil }
        return "\(legacyCloudAPIKeyAccount).\(service.rawValue).\(origin)"
    }

    var cloudProvider: CloudAPIProvider {
        let service = cloudServiceProvider
        let url = cloudCustomURL
        let key = Self.cloudCredentialAccount(for: service, customURL: url).flatMap { SecretStore.get(account: $0) }
        return CloudAPIProvider(apiKey: key ?? "", model: cloudModel, serviceProvider: service, customBaseURL: url)
    }

    private init() {
        migrateCloudAPIKey()
        migrateExplainPrompt()
    }

    private func migrateCloudAPIKey() {
        let legacyAccount = Self.legacyCloudAPIKeyAccount
        let defaultsKey = UserDefaults.standard.string(forKey: legacyAccount)
        let storedKey = SecretStore.get(account: legacyAccount)
        guard let key = storedKey ?? defaultsKey, !key.isEmpty else { return }

        // Keep the original scope even if the secrets file is temporarily unwritable.
        let scopeKey = SettingKey<String?>("aiLegacyCloudCredentialAccount", defaultValue: nil)
        let settings = DefaultSettingsStore.shared
        let account = settings.get(scopeKey) ?? cloudCredentialAccount ?? ""
        settings.set(scopeKey, value: account)
        guard !account.isEmpty else { return }

        if storedKey != nil {
            guard SecretStore.move(from: legacyAccount, to: account) else { return }
        } else if SecretStore.get(account: account) == nil {
            guard SecretStore.set(key, account: account) else { return }
        }
        UserDefaults.standard.removeObject(forKey: legacyAccount)
    }

    private func migrateExplainPrompt() {
        guard !actionPresetsJSON.isEmpty else { return }
        let previousPrompts = [
            "Explain the core concept clearly and concisely in simple terms",
            "用简单的语言清晰、简洁地解释核心概念",
            "用簡單易懂的文字清晰簡潔地解釋核心概念",
            "Expliquer le concept principal de manière claire, concise et en termes simples",
            "核心となる概念をわかりやすい言葉で明確かつ簡潔に説明します"
        ]
        var saved = presets
        guard let index = saved.firstIndex(where: { $0.id == "explain" && previousPrompts.contains($0.prompt) }),
              let updated = Self.defaultPresets.first(where: { $0.id == "explain" }) else { return }
        saved[index].prompt = updated.prompt
        presets = saved
    }

    public var activeProviderType: AIProviderType {
        get { AIProviderType(rawValue: activeProviderRaw) ?? .apple }
        set { activeProviderRaw = newValue.rawValue }
    }

    public var cloudServiceProvider: CloudServiceProvider {
        get { CloudServiceProvider(rawValue: cloudServiceRaw) ?? .openai }
        set {
            cloudServiceRaw = newValue.rawValue
            if let firstModel = newValue.defaultModels.first {
                cloudModel = firstModel
            }
        }
    }

    public var effectiveBrowserURLTemplate: String {
        switch browserPreset {
        case "claude": return "https://claude.ai/new?q={text}"
        case "perplexity": return "https://www.perplexity.ai/search?q={text}"
        case "gemini": return "https://gemini.google.com/app?q={text}"
        case "deepseek": return "https://chat.deepseek.com/?q={text}"
        case "custom":
            let custom = browserURLTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            return custom.isEmpty ? "https://chatgpt.com/?q={text}" : custom
        default:
            return "https://chatgpt.com/?q={text}"
        }
    }

    /// Overrides the AI provider instance (for testing/mocking).
    public var providerOverride: (any AIProvider)? = nil

    public var currentProvider: any AIProvider {
        if let providerOverride {
            return providerOverride
        }
        switch activeProviderType {
        case .apple:
            return AppleIntelligenceProvider()
        case .ollama:
            return OllamaProvider(baseURL: ollamaURL, model: ollamaModel)
        case .cloud:
            return cloudProvider
        case .browser:
            return BrowserRedirectProvider(template: effectiveBrowserURLTemplate)
        }
    }
}

public enum CloudServiceProvider: String, CaseIterable, Identifiable, Sendable {
    case openai = "openai"
    case anthropic = "anthropic"
    case google = "google"
    case deepseek = "deepseek"
    case groq = "groq"
    case openrouter = "openrouter"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openai: return String(localized: "OpenAI (ChatGPT)")
        case .anthropic: return String(localized: "Anthropic (Claude)")
        case .google: return String(localized: "Google Gemini")
        case .deepseek: return String(localized: "DeepSeek")
        case .groq: return String(localized: "Groq")
        case .openrouter: return String(localized: "OpenRouter")
        case .custom: return String(localized: "Custom OpenAI-Compatible Endpoint")
        }
    }

    public var defaultModels: [String] {
        switch self {
        case .openai: return ["gpt-4o-mini", "gpt-4o", "o1-mini", "o1", "gpt-4-turbo"]
        case .anthropic: return ["claude-3-5-sonnet-latest", "claude-3-5-haiku-latest", "claude-3-opus-latest"]
        case .google: return ["gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-pro"]
        case .deepseek: return ["deepseek-chat", "deepseek-coder", "deepseek-reasoner"]
        case .groq: return ["llama-3.3-70b-versatile", "mixtral-8x7b-32768", "deepseek-r1-distill-llama-70b"]
        case .openrouter: return ["openai/gpt-4o-mini", "anthropic/claude-3.5-sonnet", "deepseek/deepseek-r1", "google/gemini-2.0-flash-001"]
        case .custom: return ["default"]
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1beta"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .custom: return ""
        }
    }
}

public struct AIActionPreset: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var prompt: String
    public var isEnabled: Bool

    public init(id: String, title: String, prompt: String, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.isEnabled = isEnabled
    }
}
