import XCTest
@testable import Core
@testable import OpenClip

final class DefaultActionFactoryTests: XCTestCase {
    
    
    
    func testFactoryRejectsSymlinkEscapingDirectory() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "Symlink Shell", icon: "symbol:terminal", script: "evil.sh", url: nil, regex: nil)
        let manifest = ExtensionMetadata(identifier: "com.test.symlink", name: "Symlink Test", actions: [actionMeta], options: nil)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let symlinkURL = tempDir.appendingPathComponent("evil.sh")
        try? FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: URL(fileURLWithPath: "/bin/zsh"))
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertNil(action, "Symlink pointing outside package directory must be rejected by factory")
        
        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func testFactoryMapsLoadingFlagOntoChrome() async {
        let factory = DefaultActionFactory()
        let loadingMeta = ExtensionActionMetadata(title: "Loading", icon: "symbol:play", script: "test.applescript", type: "applescript", loading: true, loadingMessage: "Connecting to Music…")
        let plainMeta = ExtensionActionMetadata(title: "Plain", icon: "symbol:play", script: "test2.applescript", type: "applescript")
        let manifest = ExtensionMetadata(identifier: "com.test.loading", name: "Loading Test", actions: [loadingMeta, plainMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? "return \"hi\"".write(to: tempDir.appendingPathComponent("test.applescript"), atomically: true, encoding: .utf8)
        try? "return \"hi\"".write(to: tempDir.appendingPathComponent("test2.applescript"), atomically: true, encoding: .utf8)

        guard let loading = await factory.createAction(metadata: loadingMeta, manifest: manifest, directoryURL: tempDir, index: 0) as? AppleScriptAction else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("Expected AppleScriptAction")
        }
        XCTAssertTrue(loading.chrome.showsLoading)
        XCTAssertEqual(loading.chrome.loadingMessage, "Connecting to Music…")

        guard let plain = await factory.createAction(metadata: plainMeta, manifest: manifest, directoryURL: tempDir, index: 1) as? AppleScriptAction else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("Expected AppleScriptAction")
        }
        XCTAssertFalse(plain.chrome.showsLoading)
        XCTAssertNil(plain.chrome.loadingMessage)

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testUniformIDBareSlugExpandsWithManifestIdentifier() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(id: "a", title: "Action A", icon: "symbol:link", script: nil, url: "https://example.com/a?q={query}", regex: nil)
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertEqual(action?.id, "pkg.a")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testUniformIDFullIDUsedVerbatim() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(id: "com.custom.namespaced.action", title: "Action", icon: "symbol:link", script: nil, url: "https://example.com?q={query}", regex: nil)
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertEqual(action?.id, "com.custom.namespaced.action")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testUniformIDIndexFallbackIgnoresTitle() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "Some Title", icon: "symbol:link", script: nil, url: "https://example.com?q={query}", regex: nil)
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 2)
        XCTAssertEqual(action?.id, "pkg.action.2")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testGroupActionIsNotRunnableAsSingleButFlattensViaCreateActions() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(
            id: "tools",
            title: "Group",
            type: "group",
            subActions: [
                ExtensionActionMetadata(id: "sub", title: "Sub Action", url: "https://example.com?q={query}", type: "url")
            ]
        )
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // The single-action seam keeps groups schema-only (never a runnable bare group row).
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertNil(action)

        // The registry path flattens: a GroupAction row plus sub-actions under the ID-prefix convention.
        let flattened = await factory.createActions(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertEqual(flattened.count, 2)
        XCTAssertTrue(flattened[0] is GroupAction)
        XCTAssertEqual(flattened[0].id, "pkg.tools")
        XCTAssertEqual(flattened[1].id, "pkg.tools.sub")

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Rules attachment (Phase 4 visibility)

    @MainActor
    func testFactoryAttachesRulesToURLAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(
            title: "URL Action",
            icon: "symbol:link",
            url: "https://example.com/?q={text}",
            regex: "^[a-z]+$",
            requirements: ActionRequirements(apps: ["com.allowed"], appsMode: .allow)
        )
        let manifest = ExtensionMetadata(identifier: "com.test.rules", name: "Rules Test", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0) as? URLTemplateAction else {
            XCTFail("Expected URLTemplateAction")
            try? FileManager.default.removeItem(at: tempDir)
            return
        }
        XCTAssertEqual(action.rules?.legacyRegex, "^[a-z]+$")
        XCTAssertEqual(action.rules?.requirements?.apps, ["com.allowed"])

        // Allow-list filtering flows through ActionVisibility.
        let allowedContext = ActionContext(
            selection: SelectionContext(text: "hello", sourceApp: AppIdentity(bundleIdentifier: "com.allowed", localizedName: "Allowed"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        let deniedContext = ActionContext(
            selection: SelectionContext(text: "hello", sourceApp: AppIdentity(bundleIdentifier: "com.other", localizedName: "Other"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: allowedContext))
        XCTAssertFalse(action.isEnabled(for: deniedContext))

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Delivery declaration (manifest secondary/toast onto Action.delivery)

    func testFactoryComposesMenuAndDeliveryDecoration() async {
        let factory = DefaultActionFactory()
        let combo = ExtensionActionMetadata(
            id: "combo",
            title: "Combo",
            url: "https://example.com?q={query}",
            type: "url",
            menuRelevance: "\\s",
            secondary: ExtensionSecondaryDeclaration(type: "paste", value: "alt", message: nil)
        )
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [combo], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard let menu = await factory.createAction(metadata: combo, manifest: manifest, directoryURL: tempDir, index: 0) as? MenuDecoratedAction else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("Both declarations should keep menuRelevance decoration outermost")
        }
        guard let delivery = menu.base as? DeliveryDecoratedAction else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("menuRelevance outer wrapper should carry the DeliveryDecoratedAction inside")
        }
        guard case .paste(let value)? = delivery.delivery?.secondary else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("secondary should map to .paste")
        }
        XCTAssertEqual(value, "alt")
        // The declared delivery must stay reachable on the outermost wrapper the registry holds.
        guard case .paste(let outerValue)? = menu.delivery?.secondary else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("MenuDecoratedAction should forward delivery to its base")
        }
        XCTAssertEqual(outerValue, "alt")

        try? FileManager.default.removeItem(at: tempDir)
    }
}
