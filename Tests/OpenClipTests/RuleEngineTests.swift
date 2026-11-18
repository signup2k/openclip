import XCTest
@testable import Core

final class RuleEngineTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }
    
    
    @MainActor
    func testWildcardMatchingAndResolvePolicies() async throws {
        let json = """
        {
            "rules": [
                {
                    "bundle-identifiers": ["com.jetbrains.*"],
                    "deny-paste": true
                },
                {
                    "bundle-identifiers": ["*"],
                    "use-menu-copy": true
                },
                {
                    "bundle-identifiers": ["com.jetbrainsfoo"],
                    "deny-paste": false
                },
                {
                    "bundle-identifiers": [":menu-copy-apps:"],
                    "deny-paste": true
                }
            ]
        }
        """.data(using: .utf8)!
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_test.json")
        try json.write(to: tempURL)
        
        await RuleEngine.shared.loadRules(from: tempURL)
        
        // Test wildcard `.*`
        let jetbrainsContext = RuleEngine.shared.resolvePolicies(for: "com.jetbrains.idea")
        XCTAssertEqual(jetbrainsContext.denyPaste, true)
        XCTAssertEqual(jetbrainsContext.useMenuCopy, true) // inherits from `*`
        
        let jetbrainsFooContext = RuleEngine.shared.resolvePolicies(for: "com.jetbrainsfoo")
        XCTAssertEqual(jetbrainsFooContext.denyPaste, false)
        XCTAssertEqual(jetbrainsFooContext.useMenuCopy, true)
        
        // Test `*`
        let randomContext = RuleEngine.shared.resolvePolicies(for: "com.random.app")
        XCTAssertEqual(randomContext.useMenuCopy, true)
        XCTAssertEqual(randomContext.denyPaste, false)
        
        // Test macro
        let menuCopyContext = RuleEngine.shared.resolvePolicies(for: "com.apple.Terminal")
        XCTAssertEqual(menuCopyContext.denyPaste, true)
        
        try FileManager.default.removeItem(at: tempURL)
    }

    @MainActor
    func testLegacyUseMenuCopyResolvesToMenuCopyMode() async throws {
        let json = """
        {
            "rules": [
                {
                    "bundle-identifiers": ["com.legacy.app"],
                    "use-menu-copy": true
                }
            ]
        }
        """.data(using: .utf8)!
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_legacy_test.json")
        try json.write(to: tempURL)
        
        await RuleEngine.shared.loadRules(from: tempURL)
        
        let context = RuleEngine.shared.resolvePolicies(for: "com.legacy.app")
        XCTAssertTrue(context.useMenuCopy)
        XCTAssertEqual(context.retrievalMode, .menuCopy, "Legacy use-menu-copy: true should alias to .menuCopy")
        
        try FileManager.default.removeItem(at: tempURL)
    }

    @MainActor
    func testRetrievalModeJSONDecodesAndResolves() async throws {
        let json = """
        {
            "rules": [
                {
                    "bundle-identifiers": ["com.test.browser"],
                    "retrieval-mode": "browser-script"
                }
            ]
        }
        """.data(using: .utf8)!
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_retrieval_mode_test.json")
        try json.write(to: tempURL)
        
        await RuleEngine.shared.loadRules(from: tempURL)
        
        let context = RuleEngine.shared.resolvePolicies(for: "com.test.browser")
        XCTAssertEqual(context.retrievalMode, .browserScript, "retrieval-mode: browser-script should resolve for a matching bundle")
        
        try FileManager.default.removeItem(at: tempURL)
    }

    @MainActor
    func testBrowserScriptModeResolvesForBrowserGroups() async throws {
        let safariContext = RuleEngine.shared.resolvePolicies(for: "com.apple.Safari")
        XCTAssertEqual(safariContext.retrievalMode, .axWebArea)
        
        let firefoxContext = RuleEngine.shared.resolvePolicies(for: "org.mozilla.firefox")
        XCTAssertEqual(firefoxContext.retrievalMode, .axWebArea)
        
        let arcContext = RuleEngine.shared.resolvePolicies(for: "company.thebrowser.Browser")
        XCTAssertEqual(arcContext.retrievalMode, .axWebArea)
    }

    @MainActor
    func testKeyboardCopyModeResolvesForCodeEditorApps() async throws {
        let vsCodeContext = RuleEngine.shared.resolvePolicies(for: "com.microsoft.VSCode")
        XCTAssertEqual(vsCodeContext.retrievalMode, .keyboardCopy)
        XCTAssertFalse(vsCodeContext.denyPaste)
    }

    @MainActor
    func testDenyPasteModeResolvesForTerminalAndGhostty() async throws {
        let terminalContext = RuleEngine.shared.resolvePolicies(for: "com.apple.Terminal")
        XCTAssertTrue(terminalContext.denyPaste)
        XCTAssertEqual(terminalContext.retrievalMode, .keyboardCopy)

        let itermContext = RuleEngine.shared.resolvePolicies(for: "com.googlecode.iterm2")
        XCTAssertTrue(itermContext.denyPaste)
        XCTAssertEqual(itermContext.retrievalMode, .keyboardCopy)

        let ghosttyContext = RuleEngine.shared.resolvePolicies(for: "com.mitchellh.ghostty")
        XCTAssertTrue(ghosttyContext.denyPaste)
        XCTAssertEqual(ghosttyContext.retrievalMode, .keyboardCopy)
    }

    @MainActor
    func testGateResolvesDefaultAndLenient() async throws {
        let json = """
        {
            "rules": [
                {
                    "bundle-identifiers": ["com.lenient.app"],
                    "gate": {
                        "skipRoles": [],
                        "allowedCursors": ["beam", "arrow", "pointingHand", "unknown"]
                    }
                }
            ]
        }
        """.data(using: .utf8)!
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_gate_test.json")
        try json.write(to: tempURL)
        
        await RuleEngine.shared.loadRules(from: tempURL)
        
        let lenientContext = RuleEngine.shared.resolvePolicies(for: "com.lenient.app")
        XCTAssertEqual(lenientContext.gate, .lenient, "Explicit lenient gate should resolve for a matching bundle")
        
        let defaultContext = RuleEngine.shared.resolvePolicies(for: "com.random.app")
        XCTAssertEqual(defaultContext.gate, .default, "Apps with no gate rule keep the default gate")
        
        try FileManager.default.removeItem(at: tempURL)
    }

    @MainActor
    func testDisabledAndHotkeyOnlyJSONDecodingAndResolution() async throws {
        let json = """
        {
            "rules": [
                {
                    "bundle-identifiers": ["com.disabled.app"],
                    "disabled": true
                },
                {
                    "bundle-identifiers": ["com.hotkeyonly.app"],
                    "hotkey-only": true
                }
            ]
        }
        """.data(using: .utf8)!
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_disabled_hotkey_test.json")
        try json.write(to: tempURL)
        
        await RuleEngine.shared.loadRules(from: tempURL)
        
        let disabledContext = RuleEngine.shared.resolvePolicies(for: "com.disabled.app")
        XCTAssertTrue(disabledContext.disabled)
        XCTAssertFalse(disabledContext.hotkeyOnly)
        
        let hotkeyContext = RuleEngine.shared.resolvePolicies(for: "com.hotkeyonly.app")
        XCTAssertFalse(hotkeyContext.disabled)
        XCTAssertTrue(hotkeyContext.hotkeyOnly)
        
        let randomContext = RuleEngine.shared.resolvePolicies(for: "com.random.app")
        XCTAssertFalse(randomContext.disabled)
        XCTAssertFalse(randomContext.hotkeyOnly)
        
        try FileManager.default.removeItem(at: tempURL)
    }
}
