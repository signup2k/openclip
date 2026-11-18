import XCTest
@testable import Core
@testable import OpenClip

final class DebugLogFilterTests: XCTestCase {
    private func entry(_ n: Int, category: String, level: DebugLogLevel) -> DebugLogEntry {
        DebugLogEntry(id: 0, date: Date(timeIntervalSince1970: Double(n)), category: category, level: level, message: "m\(n)")
    }

    func testFilterByCategory() {
        let entries = [
            entry(1, category: "extensions", level: .info),
            entry(2, category: "ai", level: .info),
            entry(3, category: "extensions", level: .error),
        ]
        let out = DebugLogFilter(category: "extensions").apply(to: entries)
        XCTAssertEqual(out.count, 2)
        XCTAssertTrue(out.allSatisfy { $0.category == "extensions" })
    }

    func testCountCap() {
        let entries = (1...10).map { entry($0, category: "a", level: .info) }
        let out = DebugLogFilter(count: 3).apply(to: entries)
        XCTAssertEqual(out.map(\.message), ["m10", "m9", "m8"])
    }
}
