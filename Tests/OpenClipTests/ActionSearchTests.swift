import XCTest
@testable import Core

final class ActionSearchTests: XCTestCase {
    private struct MockSearchAction: Action {
        let id: String
        let title: String
        let icon = ActionIcon.symbol("star")
        let chrome = ActionChrome()
        func isEnabled(for context: ActionContext) -> Bool { true }
        func perform(_ context: ActionContext) async throws -> ActionResult { .success }
    }

    private func item(_ id: String, _ title: String, _ keywords: String = "", _ usageRecency: Int = 0) -> ActionSearchIndex {
        ActionSearchIndex(
            id: id,
            title: title,
            keywords: keywords,
            action: MockSearchAction(id: id, title: title),
            usageRecency: usageRecency
        )
    }

    func testEmptyQueryReturnsAllInInputOrder() {
        let items = [item("a", "Alpha"), item("b", "Beta"), item("c", "Gamma")]
        let result = ActionSearch.search("   ", in: items)
        XCTAssertEqual(result.map(\.id), ["a", "b", "c"])
    }

    func testPrefixMatchesRankAboveContainsMatches() {
        let items = [item("a", "Search Web"), item("b", "Web Search"), item("c", "Search Actions")]
        let result = ActionSearch.search("sear", in: items)
        XCTAssertEqual(result.map(\.id), ["a", "c", "b"])
    }

    func testMatchIsCaseInsensitive() {
        let items = [item("a", "Copy"), item("b", "Cut")]
        let result = ActionSearch.search("COPY", in: items)
        XCTAssertEqual(result.map(\.id), ["a"])
    }

    func testFuzzySubsequenceRanksBelowTitleContainsAndAboveKeyword() {
        // "sear": prefix on a, contains on b, fuzzy subsequence on c (s→e→a→r, not contiguous)
        let items = [
            item("a", "Search Web"),
            item("b", "Web Search"),
            item("c", "Satellite Earth Radar")
        ]
        let result = ActionSearch.search("sear", in: items)
        XCTAssertEqual(result.map(\.id), ["a", "b", "c"])
    }

    func testFuzzyTightMatchRanksAboveLooseMatch() {
        // "sro": b starts at a word boundary ("S…" in "Sort Options"), a is interior and spread
        // out ("Assembler Resources" — s→r→o across two words). Both are fuzzy tier; the
        // tighter, better-anchored one wins even though it appears later in the input.
        let items = [
            item("a", "Assembler Resources"),
            item("b", "Sort Options")
        ]
        let result = ActionSearch.search("sro", in: items)
        XCTAssertEqual(result.map(\.id), ["b", "a"])
    }

    func testUsageRecencyBreaksTiesWithinTier() {
        // Both contain "look"; b was used more recently → b first, despite coming later in input.
        let items = [
            item("a", "Aaa Look", "", 1),
            item("b", "Bbb Look", "", 5)
        ]
        let result = ActionSearch.search("look", in: items)
        XCTAssertEqual(result.map(\.id), ["b", "a"])
    }

    func testNonASCIIAndUnicodeScalarMatching() {
        let items = [
            item("a", "Übersetzen"),
            item("b", "Search"),
            item("c", "翻訳ツール")
        ]
        let germanResult = ActionSearch.search("über", in: items)
        XCTAssertEqual(germanResult.map(\.id), ["a"])

        let cjkResult = ActionSearch.search("翻訳", in: items)
        XCTAssertEqual(cjkResult.map(\.id), ["c"])
    }

    @MainActor
    func testRecencyPersistsAcrossInstances() {
        let settings = MemorySettingsStore()
        ActionUsageStore(settingsStore: settings).record("builtin.search")
        let reloaded = ActionUsageStore(settingsStore: settings)
        XCTAssertEqual(reloaded.recency["builtin.search"], 1)
    }
}
