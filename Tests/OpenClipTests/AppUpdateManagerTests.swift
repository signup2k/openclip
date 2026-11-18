import XCTest
@testable import OpenClip

@MainActor
final class AppUpdateManagerTests: XCTestCase {
    func testPersonalBuildDoesNotStartUpdaterWithoutIndependentFeedAndKey() {
        let manager = AppUpdateManager.shared
        XCTAssertFalse(manager.isUpdateChannelConfigured)
        XCTAssertFalse(manager.canCheckForUpdates)
        XCTAssertNil(manager.lastUpdateCheckDate)
        manager.checkForUpdates() // No controller, no upstream fallback or crash.
    }

    func testUpdateConfigurationRejectsMissingKeysAndUpstreamFeeds() {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        XCTAssertFalse(AppUpdateManager.acceptsUpdateConfiguration(feedURL: nil, publicKey: key))
        XCTAssertFalse(AppUpdateManager.acceptsUpdateConfiguration(feedURL: AppUpdateManager.defaultFeedURL, publicKey: nil))
        XCTAssertFalse(AppUpdateManager.acceptsUpdateConfiguration(feedURL: AppUpdateManager.defaultFeedURL, publicKey: "invalid"))
        XCTAssertFalse(AppUpdateManager.acceptsUpdateConfiguration(
            feedURL: "https://github.com/ganeshmshetty/openclip/releases/latest/download/appcast.xml", publicKey: key))
        XCTAssertTrue(AppUpdateManager.acceptsUpdateConfiguration(feedURL: AppUpdateManager.defaultFeedURL, publicKey: key))
    }
}
