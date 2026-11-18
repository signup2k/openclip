// ExtensionsStoreViewTests.swift
// OpenClip
//
// Covers the store view model's request lifecycle: out-of-order response protection
// (generation token), keystroke debouncing, stale-pagination discard, and the shared
// TTL page cache that survives tab switches.
import XCTest
@testable import Core
@testable import OpenClip

final class ExtensionsStoreViewTests: XCTestCase {
    /// Typing fast must never surface results for an earlier prefix: when the newer query's
    /// response lands first, the slow older response is discarded by the generation token.
    @MainActor
    func testOutOfOrderResponsesKeepLatestQueryResults() async throws {
        let api = GatedStoreAPI(arrivals: [
            expectation(description: "query 'a' fetch started"),
            expectation(description: "query 'abc' fetch started")
        ])
        let viewModel = ExtensionsStoreViewModel(api: api, debounceNanos: 10_000_000)

        viewModel.searchQuery = "a"
        viewModel.queryDidChange()
        await fulfillment(of: [api.arrivals[0]], timeout: 2)

        viewModel.searchQuery = "abc"
        viewModel.queryDidChange()
        await fulfillment(of: [api.arrivals[1]], timeout: 2)

        // Newer prefix resolves first and wins.
        await api.release(query: "abc", names: ["abc-result"])
        try await Task.sleep(nanoseconds: 50_000_000)
        let afterNewest = viewModel.extensions.map(\.id)
        XCTAssertEqual(afterNewest, ["abc-result"])

        // Older, slower response lands late — discarded, not rendered or appended.
        await api.release(query: "a", names: ["stale-a"])
        try await Task.sleep(nanoseconds: 50_000_000)
        let afterStale = viewModel.extensions.map(\.id)
        XCTAssertEqual(afterStale, ["abc-result"],
                       "a superseded response must never replace or extend current results")
    }

    /// Rapid keystrokes coalesce into exactly one network request for the final text.
    @MainActor
    func testDebounceCoalescesRapidKeystrokes() async throws {
        let api = RecordingStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api, debounceNanos: 50_000_000)

        viewModel.searchQuery = "s"
        viewModel.queryDidChange()
        viewModel.searchQuery = "sp"
        viewModel.queryDidChange()
        viewModel.searchQuery = "spa"
        viewModel.queryDidChange()

        try await Task.sleep(nanoseconds: 150_000_000) // quiet period elapses
        let queries = await api.recordedQueries()
        XCTAssertEqual(queries, ["spa"], "only the final query may hit the API")
        XCTAssertEqual(viewModel.extensions.map(\.id), ["spa-row"])
    }

    /// A page-2 prefetch parked mid-flight can neither block a new search nor append its
    /// rows to the fresh result set; the loading flag belongs to the winning generation.
    @MainActor
    func testStalePaginationAppendIsDiscardedAfterNewSearch() async throws {
        let api = GatedStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api, debounceNanos: 10_000_000)

        viewModel.searchQuery = "old"
        let initial = Task { await viewModel.resetAndFetch() }
        try await waitUntil { await api.hasPending(query: "old", page: 1) }
        await api.release(query: "old", names: ["old-1", "old-2"], totalPages: 2)
        await initial.value
        XCTAssertEqual(viewModel.extensions.map(\.id), ["old-1", "old-2"])

        // Page-2 prefetch starts and parks on the gate…
        let prefetch = Task { await viewModel.fetchNextPage() }
        try await waitUntil { await api.hasPending(query: "old", page: 2) }

        // …then a brand-new result set is requested; it must not be blocked by the parked page…
        viewModel.searchQuery = "new"
        let refreshed = Task { await viewModel.resetAndFetch() }
        try await waitUntil { await api.hasPending(query: "new", page: 1) }
        await api.release(query: "new", names: ["new-1"])
        await refreshed.value
        XCTAssertEqual(viewModel.extensions.map(\.id), ["new-1"])

        // …and when the stale page finally lands it must not leak into the new list.
        await api.release(query: "old", page: 2, names: ["stale-page-2"], totalPages: 9)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(viewModel.extensions.map(\.id), ["new-1"])
        XCTAssertFalse(viewModel.isLoading)
        await prefetch.value
    }

    // MARK: - Store Filter & Badges

    /// When the last fetched item is excluded by the active filter (e.g. .popular), it does not
    /// appear in displayedExtensions. Pagination must trigger from displayedExtensions.last.
    @MainActor
    func testPaginationTriggeredWhenLastFetchedItemExcludedByActiveFilter() async throws {
        let api = GatedStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)
        viewModel.selectedFilter = .popular

        let popularItem = ExtensionItem(id: "com.openclip.custom-popular", name: "Popular",
                                        description: "", author: "openclip", icon: "", downloadCount: 500, downloadURL: "")
        let obscureItem = ExtensionItem(id: "com.openclip.obscure-tool", name: "Obscure",
                                        description: "", author: "openclip", icon: "", downloadCount: 0, downloadURL: "", version: "1.0.0")

        let initial = Task { await viewModel.resetAndFetch() }
        try await waitUntil { await api.hasPending(query: "", page: 1) }
        await api.release(query: "", page: 1, items: [popularItem, obscureItem], totalPages: 2)
        await initial.value

        XCTAssertEqual(viewModel.currentPage, 2)
        // Last fetched item in full extensions array is obscureItem
        XCTAssertEqual(viewModel.extensions.last?.id, "com.openclip.obscure-tool")
        // But displayedExtensions in .popular only includes popularItem
        XCTAssertEqual(viewModel.displayedExtensions.map(\.id), ["com.openclip.custom-popular"])

        // Flat pagination must trigger on the last displayed item, not obscureItem
        XCTAssertTrue(viewModel.shouldTriggerFlatPagination(for: "com.openclip.custom-popular"))
        XCTAssertFalse(viewModel.shouldTriggerFlatPagination(for: "com.openclip.obscure-tool"))

        // Simulating the onAppear trigger on the last rendered card initiates page 2 fetch.
        let nextPage = Task { await viewModel.fetchNextPage() }
        try await waitUntil { await api.hasPending(query: "", page: 2) }
        let page2Item = ExtensionItem(id: "com.openclip.page2-popular", name: "Page 2 Popular",
                                      description: "", author: "openclip", icon: "", downloadCount: 200, downloadURL: "")
        await api.release(query: "", page: 2, items: [page2Item], totalPages: 2)
        await nextPage.value

        XCTAssertEqual(viewModel.currentPage, 3)
        XCTAssertEqual(viewModel.displayedExtensions.map(\.id), ["com.openclip.custom-popular", "com.openclip.page2-popular"])
    }

    /// The Featured section must always return 4 extensions: even before fetching,
    /// When the API response includes `featured` extensions (as provided by the website API),
    /// featuredSectionItems returns all curated featured items directly.
    @MainActor
    func testServerDrivenFeaturedExtensionsPopulatesFeaturedSection() async throws {
        let api = GatedStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)

        let serverFeatured = [
            ExtensionItem(id: "com.openclip.quick-translate", name: "Quick Translate", description: "", author: "openclip", icon: "", downloadCount: 120, downloadURL: ""),
            ExtensionItem(id: "com.openclip.wordcount", name: "Word Count", description: "", author: "openclip", icon: "", downloadCount: 84, downloadURL: ""),
            ExtensionItem(id: "com.openclip.speakselection", name: "Speak Selection", description: "", author: "openclip", icon: "", downloadCount: 74, downloadURL: ""),
            ExtensionItem(id: "com.openclip.obsidiancapture", name: "Obsidian Capture", description: "", author: "openclip", icon: "", downloadCount: 6, downloadURL: "")
        ]

        let fetchTask = Task { await viewModel.resetAndFetch() }
        try await waitUntil { await api.hasPending(query: "", page: 1) }
        let reminderItem = ExtensionItem(id: "com.openclip.applereminders", name: "Apple Reminders",
                                         description: "Live from API", author: "openclip", icon: "", downloadCount: 50, downloadURL: "")
        await api.release(query: "", page: 1, items: [reminderItem], featured: serverFeatured)
        await fetchTask.value

        // Must have all 4 featured items from the server response
        XCTAssertEqual(viewModel.featuredSectionItems.count, 4)
        XCTAssertEqual(viewModel.featuredSectionItems.map(\.id), [
            "com.openclip.quick-translate",
            "com.openclip.wordcount",
            "com.openclip.speakselection",
            "com.openclip.obsidiancapture"
        ])
    }

    // MARK: - Helpers

    @MainActor
    private func waitUntil(_ condition: () async -> Bool, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

/// Fetcher whose responses park on gates the test releases in a chosen order — the only way
/// to deterministically reproduce out-of-order network resolution. Optionally fulfills one
/// XCTestExpectation per request, in arrival order.
private actor GatedStoreAPI: ExtensionStoreFetching {
    let arrivals: [XCTestExpectation]
    private var pending: [String: CheckedContinuation<ExtensionsPageResponse, Error>] = [:]
    private var arrivalIndex = 0

    init(arrivals: [XCTestExpectation] = []) {
        self.arrivals = arrivals
    }

    func fetchExtensions(query: String, page: Int, limit: Int) async throws -> ExtensionsPageResponse {
        if arrivals.indices.contains(arrivalIndex) {
            arrivals[arrivalIndex].fulfill()
        }
        arrivalIndex += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending["\(query)|\(page)"] = continuation
        }
    }

    func hasPending(query: String, page: Int) -> Bool {
        pending["\(query)|\(page)"] != nil
    }

    func release(query: String, page: Int = 1, items: [ExtensionItem], featured: [ExtensionItem]? = nil, new: [ExtensionItem]? = nil, totalPages: Int = 1) {
        guard let continuation = pending.removeValue(forKey: "\(query)|\(page)") else {
            fatalError("no gated request for '\(query)|\(page)'")
        }
        continuation.resume(returning:
            ExtensionsPageResponse(extensions: items, featured: featured, new: new, page: page, totalPages: totalPages, totalCount: items.count))
    }

    func release(query: String, page: Int = 1, names: [String], totalPages: Int = 1) {
        let items = names.map {
            ExtensionItem(id: $0, name: $0, description: "", author: "", icon: "",
                          downloadCount: 0, downloadURL: "")
        }
        release(query: query, page: page, items: items, totalPages: totalPages)
    }
}

/// Immediate-response fetcher that records which queries were requested.
private actor RecordingStoreAPI: ExtensionStoreFetching {
    private var queries: [String] = []

    func recordedQueries() -> [String] {
        queries
    }

    func fetchExtensions(query: String, page: Int, limit: Int) async throws -> ExtensionsPageResponse {
        queries.append(query)
        let item = ExtensionItem(id: "\(query)-row", name: query, description: "", author: "", icon: "",
                                 downloadCount: 0, downloadURL: "")
        return ExtensionsPageResponse(extensions: [item], page: page, totalPages: 1, totalCount: 1)
    }
}
