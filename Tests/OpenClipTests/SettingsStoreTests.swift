import XCTest
@testable import Core
@testable import OpenClip

final class SettingsStoreTests: XCTestCase {
    var userDefaults: UserDefaults!
    var store: DefaultSettingsStore!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: #file)!
        userDefaults.removePersistentDomain(forName: #file)
        store = DefaultSettingsStore(userDefaults: userDefaults)
    }

    @MainActor
    func testTypedSettingReadWrite() {
        XCTAssertEqual(store.get(.actionOrder), [])
        store.set(.actionOrder, value: ["builtin.copy", "builtin.paste"])
        XCTAssertEqual(store.get(.actionOrder), ["builtin.copy", "builtin.paste"])
    }

    @MainActor
    func testResultDeliveryRoundTrip() {
        store.set(.primaryClickBehavior, value: "preview")
        store.set(.secondaryClickBehavior, value: "paste")
        XCTAssertEqual(store.get(.primaryClickBehavior), "preview")
        XCTAssertEqual(store.get(.secondaryClickBehavior), "paste")
    }

    // MARK: - Safe fallbacks (issue #21)

    @MainActor
    func testSetKeyWithUnexpectedStoredTypeReturnsDefault() {
        // A non-array value stored under a Set<String> key must not crash — fall back to [].
        userDefaults.set("not-an-array", forKey: SettingKey.disabledActionIDs.name)
        XCTAssertEqual(store.get(.disabledActionIDs), [])

        // An array of the wrong element type is not readable as [String] — fall back to [].
        userDefaults.set([1, 2, 3], forKey: SettingKey.disabledPackages.name)
        XCTAssertEqual(store.get(.disabledPackages), [])
    }

    @MainActor
    func testOptionalDataKeyRoundTrip() {
        // Unset key reads back the default (nil).
        XCTAssertNil(store.get(.actionGroups))

        let payload = "hello".data(using: .utf8)
        store.set(.actionCustomizations, value: payload)
        XCTAssertEqual(store.get(.actionCustomizations), payload)
    }

    func testResultDeliveryPreferenceMapping() {
        XCTAssertEqual(ResultDeliveryPreference.allCases, [.preview, .paste, .copy])
        XCTAssertEqual(ResultDeliveryPreference(rawValue: "preview"), .preview)
        XCTAssertEqual(ResultDeliveryPreference(rawValue: "paste"), .paste)
        XCTAssertEqual(ResultDeliveryPreference(rawValue: "copy"), .copy)
        XCTAssertNil(ResultDeliveryPreference(rawValue: "bogus"))
    }
}
