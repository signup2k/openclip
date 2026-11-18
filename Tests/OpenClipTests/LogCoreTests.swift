import XCTest
@testable import Core

private final class TestLogSink: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    var records: [(date: Date, category: String, level: LogLevel, message: String)] = []

    func record(date: Date, category: String, level: LogLevel, message: String) {
        lock.lock()
        defer { lock.unlock() }
        records.append((date: date, category: category, level: level, message: message))
    }

    func getRecords() -> [(date: Date, category: String, level: LogLevel, message: String)] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}

final class LogCoreTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            TestIsolation.reset()
            Log.removeAllSinks()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            Log.removeAllSinks()
        }
        try await super.tearDown()
    }

    func testLogPrivateInterpolationRedaction() {
        let sink = TestLogSink()
        Log.addSink(sink)

        let secret = "super-secret-token"
        let unannotated = "unannotated-text"
        let autoVal = "auto-text"
        let publicVal = 42
        Log.settings.info("Auth info: secret=\(secret, privacy: .private) unannotated=\(unannotated) auto=\(autoVal, privacy: .auto) count=\(publicVal, privacy: .public)")

        let records = sink.getRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].message, "Auth info: secret=<private> unannotated=<private> auto=<private> count=42")
    }
}
