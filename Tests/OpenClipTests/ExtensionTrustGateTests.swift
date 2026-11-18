import XCTest
@testable import Core

final class ExtensionTrustGateTests: XCTestCase {
    var tempDir: URL!
    var store: MemorySettingsStore!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = MemorySettingsStore()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // Writes a single-action manifest package and returns its scanned actions (no gate).
    @MainActor
    private func scannedActions(for packageID: String, name: String, script: String = "echo hi", minOpenClipVersion: String? = nil) async -> [any Action] {
        let pkg = tempDir.appendingPathComponent("\(name).openclipext")
        try! FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        let manifestURL = pkg.appendingPathComponent("openclip.json")
        let versionField = minOpenClipVersion.map { ",\"minOpenClipVersion\":\"\($0)\"" } ?? ""
        try! """
        {"identifier":"\(packageID)","name":"\(name)"\(versionField),"actions":[
            {"title":"Run","type":"shell","script":"main.sh"}]}
        """.write(to: manifestURL, atomically: true, encoding: .utf8)
        let scriptURL = pkg.appendingPathComponent("main.sh")
        try! script.write(to: scriptURL, atomically: true, encoding: .utf8)
        return await ExtensionManager.scanActionsForTest(in: tempDir)
    }

    @MainActor
    private func plan(packageID: String, name: String, trust: [String: String], hashes: [String: String], sources: [String: String], isMigrated: Bool, script: String = "echo hi", appVersion: String = "1.4.0", minOpenClipVersion: String? = nil) async throws -> ExtensionGatePlan {
        let actions = await scannedActions(for: packageID, name: name, script: script, minOpenClipVersion: minOpenClipVersion)
        return ExtensionTrustGate.evaluate(
            actions: actions, in: tempDir,
            trust: trust, hashes: hashes, sources: sources,
            isMigrated: isMigrated, appVersion: appVersion
        )
    }

    @MainActor
    func testNewLocalPackageBeforeMigrationAutoTrusts() async throws {
        let p = try await plan(packageID: "com.t.first", name: "First", trust: [:], hashes: [:], sources: [:], isMigrated: false)
        XCTAssertEqual(p.actions.count, 1)
        XCTAssertFalse(p.actions[0] is GatedExtensionAction, "migration must keep the real action")
        XCTAssertEqual(p.trust["com.t.first"], "trusted")
        XCTAssertEqual(p.hashes["com.t.first"]?.count, 64)
        XCTAssertTrue(p.trustChanged)
        XCTAssertTrue(p.hashesChanged)
        XCTAssertTrue(p.migratedChanged, "migration flag must be set once")
        XCTAssertTrue(p.isMigrated)
        XCTAssertTrue(p.events.isEmpty)
    }

    @MainActor
    func testFreshStoreInstallFailsClosedWhenFingerprintUnresolvable() async throws {
        // Scan a valid package, then delete it so fingerprinting returns nil at evaluate time.
        // A fresh store install must not auto-trust or run without a hash.
        let actions = await scannedActions(for: "com.t.nilhash", name: "NilHash")
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("NilHash.openclipext"))

        let p = ExtensionTrustGate.evaluate(
            actions: actions, in: tempDir,
            trust: [:], hashes: [:], sources: ["com.t.nilhash": "store"],
            isMigrated: true, appVersion: "1.4.0"
        )
        let gated = try XCTUnwrap(p.actions[0] as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .filesChanged)
        XCTAssertNil(p.trust["com.t.nilhash"], "must not persist trust without a fingerprint")
        XCTAssertTrue(p.hashes.isEmpty, "must not persist an empty hash")
        XCTAssertFalse(p.trustChanged)
        XCTAssertFalse(p.hashesChanged)
    }

    @MainActor
    func testTrustedPackageFailsClosedWhenFingerprintUnresolvable() async throws {
        let actions = await scannedActions(for: "com.t.niltrust", name: "NilTrust")
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("NilTrust.openclipext"))

        let p = ExtensionTrustGate.evaluate(
            actions: actions, in: tempDir,
            trust: ["com.t.niltrust": "trusted"], hashes: ["com.t.niltrust": "oldhash"],
            sources: [:], isMigrated: true, appVersion: "1.4.0"
        )
        let gated = try XCTUnwrap(p.actions[0] as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .filesChanged)
        XCTAssertEqual(p.trust["com.t.niltrust"], "seen", "unverifiable trusted package flips to seen")
        XCTAssertTrue(p.events.isEmpty)
        XCTAssertEqual(p.hashes["com.t.niltrust"], "oldhash", "the stale hash must be left untouched, not replaced by an empty one")
    }

    @MainActor
    func testStorePackageThatIsRevokedStaysRevoked() async throws {
        let p = try await plan(packageID: "com.t.srev", name: "SRev", trust: ["com.t.srev": "revoked"], hashes: [:], sources: ["com.t.srev": "store"], isMigrated: true)
        let gated = try XCTUnwrap(p.actions[0] as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .revoked)
        XCTAssertEqual(p.trust["com.t.srev"], "revoked", "revoked must survive an update")
    }

    @MainActor
    func testOpenClipVersionGatesIncompatibleTrustedPackage() async throws {
        // Trusted + matching hash, but the package requires a newer app → gate on needsNewerApp,
        // NOT tampered (version check runs after trust resolution).
        let first = try await plan(packageID: "com.t.minv", name: "MinV", trust: [:], hashes: [:], sources: [:], isMigrated: false, minOpenClipVersion: "2.0.0")
        let hash = first.hashes["com.t.minv"]!
        let p = try await plan(packageID: "com.t.minv", name: "MinV", trust: ["com.t.minv": "trusted"], hashes: ["com.t.minv": hash], sources: [:], isMigrated: true, appVersion: "1.4.0", minOpenClipVersion: "2.0.0")
        let gated = try XCTUnwrap(p.actions[0] as? GatedExtensionAction)
        XCTAssertEqual(gated.reason, .needsNewerApp(required: "2.0.0"))
        XCTAssertEqual(p.trust["com.t.minv"], "trusted", "a matching-hash trusted package must gate on needsNewerApp, not filesChanged")
        XCTAssertTrue(p.events.isEmpty, "version gating is not a tamper event")
    }

    @MainActor
    func testGatedActionExcludedFromAvailableActionsAndSearchCatalog() async throws {
        let registry = ActionRegistry(settingsStore: store)
        let gated = GatedExtensionAction(
            packageID: "com.t.gated", title: "Gated", icon: .symbol("wand.and.stars"),
            chrome: ActionChrome(badge: .extensionPkg("Gated"), rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: "com.t.gated")),
            reason: .filesChanged
        )
        registry.register(action: gated)
        let selection = SelectionContext(text: "hello", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let ctx = ActionContext(selection: selection, modifiers: [])
        XCTAssertTrue(registry.availableActions(for: ctx).isEmpty, "gated action must never appear in floating popup")
        XCTAssertTrue(registry.searchCatalog(for: ctx).isEmpty, "gated action must never appear in search catalog")
    }
}
