import XCTest
@testable import Core

final class ManifestValidationTests: XCTestCase {
    private var validator: ManifestValidator { ManifestValidator.shared }

    private func decodeManifest(_ json: String) throws -> ExtensionMetadata {
        try JSONDecoder().decode(ExtensionMetadata.self, from: Data(json.utf8))
    }

    // MARK: - action kinds

    func testRecognizedKindsValidateClean() throws {
        let json = """
        {
            "identifier": "com.example.allkinds",
            "name": "All Kinds",
            "actions": [
                { "title": "URL", "type": "url", "url": "https://example.com/{query}" },
                { "title": "Web", "type": "websearch", "url": "https://example.com/{query}" },
                { "title": "JS", "type": "js", "scriptCode": "function action(t){return t}" },
                { "title": "AppleScript", "type": "applescript", "scriptCode": "return text" },
                { "title": "Shell", "type": "shell", "scriptCode": "echo hi" },
                { "title": "Script file", "type": "scriptfile", "script": "main.sh" },
                { "title": "Snippet", "type": "textsnippet", "scriptCode": "{text}" },
                { "title": "Key", "type": "keypress", "keyPress": "command+b" },
                { "title": "Shortcut", "type": "shortcut", "shortcutName": "Trim" },
                { "title": "Service", "type": "service", "serviceName": "Share" },
                { "title": "Group", "type": "group", "subActions": [
                    { "id": "sub", "title": "Sub", "type": "url", "url": "https://example.com/{query}" }
                ] }
            ]
        }
        """
        let manifest = try decodeManifest(json)
        XCTAssertEqual(validator.validate(manifest), [])
        XCTAssertTrue(validator.validate(manifest, data: Data(json.utf8)).isValid)
    }

    func testUnknownActionKindRejectsManifest() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.badkind",
            "name": "Bad Kind",
            "actions": [{ "title": "Nope", "type": "banana", "url": "https://example.com/{query}" }]
        }
        """)
        let issues = validator.validate(manifest)
        XCTAssertEqual(issues, [ManifestValidationIssue(kind: .unknownActionKind("banana"), path: "actions[0]")])
    }

    func testUnknownKindInsideGroupSubActionRejectsManifest() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.badgroup",
            "name": "Bad Group",
            "actions": [{ "title": "Group", "type": "group", "subActions": [
                { "id": "sub", "title": "Sub", "type": "bogus", "url": "https://example.com/{query}" }
            ] }]
        }
        """)
        let issues = validator.validate(manifest)
        XCTAssertEqual(issues, [ManifestValidationIssue(kind: .unknownActionKind("bogus"), path: "actions[0].subActions[0]")])
    }

    func testLegacyManifestWithoutTypeButWithScriptIsValid() throws {
        // Mirrors the shipped AppleMusic package: singular "action", no "type", script file.
        let manifest = try decodeManifest("""
        {
            "identifier": "com.openclip.applemusic",
            "name": "Apple Music",
            "action": { "title": "Apple Music", "icon": "music.note", "script": "main.applescript" }
        }
        """)
        XCTAssertEqual(manifest.actions.count, 1)
        XCTAssertEqual(validator.validate(manifest), [])
    }

    func testLegacyManifestWithoutTypeButWithURLIsValid() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.openclip.googlemaps",
            "name": "Google Maps",
            "action": { "title": "Google Maps", "url": "https://www.google.com/maps/search/{text}" }
        }
        """)
        XCTAssertEqual(validator.validate(manifest), [])
    }

    func testContentlessActionRejectsManifest() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.empty",
            "name": "Empty",
            "actions": [{ "title": "Nothing here" }]
        }
        """)
        let issues = validator.validate(manifest)
        XCTAssertEqual(issues, [ManifestValidationIssue(kind: .missingRequiredField("url/script/scriptCode"), path: "actions[0]")])
    }

    // MARK: - secondary on javascript actions

    func testJavascriptActionWithSecondaryRejects() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.jssec",
            "name": "JS Sec",
            "actions": [{ "title": "JS", "type": "javascript", "scriptCode": "return 1",
                "secondary": { "type": "copy", "value": "x" } }]
        }
        """)
        let issues = validator.validate(manifest)
        XCTAssertEqual(issues, [ManifestValidationIssue(kind: .secondaryOnJavaScriptAction, path: "actions[0]")])
    }

    func testNonJavascriptActionWithSecondaryIsClean() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.nonsec",
            "name": "Non-Sec",
            "actions": [
                { "title": "URL", "type": "url", "url": "https://example.com/{query}",
                    "secondary": { "type": "copy", "value": "x" } },
                { "title": "Snippet", "type": "textsnippet", "scriptCode": "{text}",
                    "secondary": { "type": "none" } }
            ]
        }
        """)
        XCTAssertEqual(validator.validate(manifest), [])
    }

    func testJavascriptSubActionWithSecondaryRejectsInsideGroup() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.jsgroup",
            "name": "JS Group",
            "actions": [{ "title": "Group", "type": "group", "subActions": [
                { "id": "sub", "title": "Sub JS", "type": "javascript", "scriptCode": "return 1",
                    "secondary": { "type": "toast" } }
            ] }]
        }
        """)
        let issues = validator.validate(manifest)
        XCTAssertEqual(issues, [ManifestValidationIssue(kind: .secondaryOnJavaScriptAction, path: "actions[0].subActions[0]")])
    }

    // MARK: - required fields per kind

    func testKeyPressWithoutKeyPressFieldRejects() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.badkey",
            "name": "Bad Key",
            "actions": [{ "title": "Key", "type": "keypress" }]
        }
        """)
        XCTAssertEqual(validator.validate(manifest), [ManifestValidationIssue(kind: .missingRequiredField("keyPress"), path: "actions[0]")])
    }

    func testCanvasKindRejectsManifest() throws {
        // The canvas feature was removed; `type: "canvas"` is rejected like any unknown kind.
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.badcanvas",
            "name": "Bad Canvas",
            "actions": [{ "title": "Canvas", "type": "canvas" }]
        }
        """)
        XCTAssertEqual(validator.validate(manifest), [ManifestValidationIssue(kind: .unknownActionKind("canvas"), path: "actions[0]")])
    }

    func testShortcutWithoutShortcutNameRejects() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.badshortcut",
            "name": "Bad Shortcut",
            "actions": [{ "title": "Shortcut", "type": "shortcut" }]
        }
        """)
        XCTAssertEqual(validator.validate(manifest), [ManifestValidationIssue(kind: .missingRequiredField("shortcutName"), path: "actions[0]")])
    }

    func testEmptyGroupRejects() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.emptygroup",
            "name": "Empty Group",
            "actions": [{ "title": "Group", "type": "group" }]
        }
        """)
        XCTAssertEqual(validator.validate(manifest), [ManifestValidationIssue(kind: .missingRequiredField("subActions"), path: "actions[0]")])
    }

    // MARK: - capability gating (empty known set on day one)

    func testCapabilityGateEmptyKnownSetRejectsAnyDeclaration() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.cap",
            "name": "Cap",
            "capabilities": ["network"],
            "actions": [{ "title": "URL", "type": "url", "url": "https://example.com/{query}" }]
        }
        """)
        let issues = validator.validate(manifest)
        XCTAssertEqual(issues, [ManifestValidationIssue(kind: .unknownCapability("network"), path: "manifest")])
    }

    func testOpenClipVersionDoesNotAffectValidation() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.minv",
            "name": "Min V",
            "minOpenClipVersion": "1.5.0",
            "actions": [{ "title": "URL", "type": "url", "url": "https://example.com/{query}" }]
        }
        """)
        XCTAssertEqual(validator.validate(manifest), [])
        XCTAssertEqual(manifest.minOpenClipVersion, "1.5.0")
    }

    // MARK: - record (schema version, declared version, fingerprint)

    func testDuplicateOptionIdentifierRejectsManifest() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.dupoptions",
            "name": "Dup Options",
            "actions": [{
                "title": "JS",
                "type": "js",
                "scriptCode": "function action(t){return t}",
                "options": [
                    { "identifier": "apiKey", "label": "Key 1", "type": "string" },
                    { "identifier": "apiKey", "label": "Key 2", "type": "string" }
                ]
            }]
        }
        """)
        let issues = validator.validate(manifest)
        XCTAssertEqual(issues, [ManifestValidationIssue(kind: .duplicateOptionIdentifier("apiKey"), path: "actions[0]")])
    }

    func testDuplicateTopLevelOptionIdentifierRejectsManifest() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.duptopleveloptions",
            "name": "Dup Top-Level Options",
            "options": [
                { "identifier": "apiKey", "label": "Key 1", "type": "string" },
                { "identifier": "apiKey", "label": "Key 2", "type": "string" }
            ],
            "actions": [{
                "title": "JS",
                "type": "js",
                "scriptCode": "function action(t){return t}"
            }]
        }
        """)
        let issues = validator.validate(manifest)
        XCTAssertEqual(issues, [ManifestValidationIssue(kind: .duplicateOptionIdentifier("apiKey"), path: "options")])
    }

    func testScriptPathTraversalRejectsManifest() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.traversal",
            "name": "Traversal Test",
            "actions": [{ "title": "Evil", "type": "scriptfile", "script": "../../../../bin/zsh" }]
        }
        """)
        let issues = validator.validate(manifest)
        XCTAssertEqual(issues, [ManifestValidationIssue(kind: .unsafeScriptPath("../../../../bin/zsh"), path: "actions[0]")])
    }

    func testScriptPathTraversalInsideGroupSubActionRejectsManifest() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.grouptraversal",
            "name": "Group Traversal Test",
            "actions": [{
                "title": "Group",
                "type": "group",
                "subActions": [
                    { "id": "sub", "title": "Evil Sub", "type": "scriptfile", "script": "../evil.sh" }
                ]
            }]
        }
        """)
        let issues = validator.validate(manifest)
        XCTAssertEqual(issues, [ManifestValidationIssue(kind: .unsafeScriptPath("../evil.sh"), path: "actions[0].subActions[0]")])
    }

    func testAbsoluteScriptPathRejectsManifest() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.absolutepath",
            "name": "Absolute Path Test",
            "actions": [{ "title": "Evil", "type": "scriptfile", "script": "/bin/zsh" }]
        }
        """)
        let issues = validator.validate(manifest)
        XCTAssertEqual(issues, [ManifestValidationIssue(kind: .unsafeScriptPath("/bin/zsh"), path: "actions[0]")])
    }

    func testTildeScriptPathRejectsManifest() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.tildepath",
            "name": "Tilde Path Test",
            "actions": [{ "title": "Evil", "type": "scriptfile", "script": "~/evil.sh" }]
        }
        """)
        let issues = validator.validate(manifest)
        XCTAssertEqual(issues, [ManifestValidationIssue(kind: .unsafeScriptPath("~/evil.sh"), path: "actions[0]")])
    }

    func testSafeScriptPathsValidateClean() throws {
        let manifest = try decodeManifest("""
        {
            "identifier": "com.example.safescript",
            "name": "Safe Script Test",
            "actions": [
                { "title": "Run", "type": "scriptfile", "script": "main.sh" },
                { "title": "Nested", "type": "js", "script": "dist/bundle.js" },
                { "title": "Explicit Relative", "type": "applescript", "script": "./run.applescript" }
            ]
        }
        """)
        let issues = validator.validate(manifest)
        XCTAssertEqual(issues, [])
    }
}
