import XCTest
@testable import OpenClip

final class DebugLogCommandTests: XCTestCase {
    func testNegativeCountIsUsageError() {
        guard case .usageError = DebugLogCommand.parse(["OpenClip", "--dump-logs", "--count=-5"]) else {
            return XCTFail("expected usageError")
        }
    }

    func testBareDumpDefaults() {
        guard case .dumpLogs(let opts) = DebugLogCommand.parse(["OpenClip", "--dump-logs"]) else {
            return XCTFail("expected dumpLogs")
        }
        XCTAssertNil(opts.category)
        XCTAssertNil(opts.level)
        XCTAssertEqual(opts.count, 500)
        XCTAssertEqual(opts.collectSeconds, 4)
    }

    func testDumpWithOptions() {
        guard case .dumpLogs(let opts) = DebugLogCommand.parse([
            "OpenClip", "--dump-logs",
            "--category=extensions", "--level=error", "--count=20", "--collect=3"
        ]) else {
            return XCTFail("expected dumpLogs")
        }
        XCTAssertEqual(opts.category, "extensions")
        XCTAssertEqual(opts.level, .error)
        XCTAssertEqual(opts.count, 20)
        XCTAssertEqual(opts.collectSeconds, 3)
    }

    func testBadLevelIsUsageError() {
        guard case .usageError = DebugLogCommand.parse(["OpenClip", "--dump-logs", "--level=nope"]) else {
            return XCTFail("expected usageError")
        }
    }
}
