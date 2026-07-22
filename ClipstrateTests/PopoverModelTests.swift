import XCTest
@testable import Clipstrate

@MainActor
final class PopoverModelTests: XCTestCase {
    private var tempDir: URL!
    private var store: HistoryStore!
    private var model: PopoverModel!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipstratePopover-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try HistoryStore(path: tempDir.appendingPathComponent("history.sqlite").path)
        model = PopoverModel(historyStore: store)
    }

    override func tearDownWithError() throws {
        model?.tearDown()
        model = nil
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func seed(_ count: Int) async throws {
        for i in 1...count {
            _ = try await store.upsert(
                ClipItem(kind: .text, plainText: "item-\(i)", contentHash: "h\(i)", byteSize: 10),
                at: Int64(i))
        }
    }

    func testFirstPageAndPaginationCoversAllWithoutOverlap() async throws {
        try await seed(120)

        await model.loadFirstPage()
        XCTAssertEqual(model.items.count, 50)
        XCTAssertEqual(model.items.first?.plainText, "item-120", "最近在前")

        await model.loadNextPage()
        XCTAssertEqual(model.items.count, 100)

        await model.loadNextPage()
        XCTAssertEqual(model.items.count, 120)

        await model.loadNextPage() // 无更多，不变
        XCTAssertEqual(model.items.count, 120)
        XCTAssertEqual(Set(model.items.map(\.contentHash)).count, 120, "分页无重叠且全覆盖")
    }

    func testSearchFilters() async throws {
        _ = try await store.upsert(
            ClipItem(kind: .text, plainText: "验证码 8823", contentHash: "hx", byteSize: 10), at: 100)
        _ = try await store.upsert(
            ClipItem(kind: .text, plainText: "无关内容", contentHash: "hy", byteSize: 10), at: 200)

        model.query = "验证码"
        await model.performSearch()
        XCTAssertEqual(model.items.map(\.contentHash), ["hx"])
    }

    func testStatsCountAndBytes() async throws {
        try await seed(3)
        await model.refreshStats()
        XCTAssertEqual(model.totalCount, 3)
        XCTAssertEqual(model.totalBytes, 30)
    }

    func testReloadResetsQueryAndLoadsRecent() async throws {
        try await seed(5)
        model.query = "item-2"
        await model.performSearch()
        XCTAssertEqual(model.items.count, 1)

        await model.reload()
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.items.count, 5)
        XCTAssertEqual(model.totalCount, 5)
    }
}
