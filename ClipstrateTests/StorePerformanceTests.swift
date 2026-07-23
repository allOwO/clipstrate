import XCTest
@testable import Clipstrate

/// T3.1 性能自测：灌 1 万条历史，验证 keyset 分页与 FTS 搜索在规模下仍正确且不退化。
/// 硬预算（唤出 <100ms、击键搜索 <30ms）由 os_signpost + Instruments 在真机核（02 §9），
/// 此处用宽松上限只拦截灾难性回归，避免 CI 抖动误报。
@MainActor
final class StorePerformanceTests: XCTestCase {
    private var tempDir: URL!
    private var store: HistoryStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipstratePerf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try HistoryStore(path: tempDir.appendingPathComponent("history.sqlite").path)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func measureAsync<T>(_ operation: () async throws -> T) async rethrows -> (value: T, elapsed: Duration) {
        let clock = ContinuousClock()
        let start = clock.now
        let value = try await operation()
        return (value, clock.now - start)
    }

    func testKeysetPaginationAndSearchScaleToTenThousand() async throws {
        for i in 1...10_000 {
            _ = try await store.upsert(
                ClipItem(kind: .text, plainText: "记录 \(i) 内容 tag\(i)", contentHash: "h\(i)"),
                at: Int64(i))
        }
        let total = try await store.count()
        XCTAssertEqual(total, 10_000)

        // 首页 keyset 分页：最近在前、恰好一页。
        let (page, pageTime) = try await measureAsync { try await store.page(limit: 50) }
        XCTAssertEqual(page.count, 50)
        XCTAssertEqual(page.first?.contentHash, "h10000", "最近在前")
        XCTAssertLessThan(pageTime, .milliseconds(250), "1 万条取一页不应退化")

        // 深翻一页仍走索引，不做全表扫描。
        let (page2, page2Time) = try await measureAsync { try await store.page(after: page.last, limit: 50) }
        XCTAssertEqual(page2.count, 50)
        XCTAssertEqual(page2.first?.contentHash, "h9950")
        XCTAssertLessThan(page2Time, .milliseconds(250))

        // FTS trigram 子串搜索命中唯一目标。
        let (hits, searchTime) = try await measureAsync { try await store.search("tag9999", limit: 50) }
        XCTAssertTrue(hits.contains { $0.contentHash == "h9999" })
        XCTAssertLessThan(searchTime, .milliseconds(250), "1 万条 FTS 搜索不应退化")
    }
}
