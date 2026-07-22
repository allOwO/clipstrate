import XCTest
@testable import ChopClip

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: HistoryStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChopClipTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try HistoryStore(path: tempDir.appendingPathComponent("history.sqlite").path)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func text(_ s: String, hash: String, appName: String? = nil) -> ClipItem {
        ClipItem(kind: .text, plainText: s, contentHash: hash, appName: appName)
    }

    func testInsertAndFetch() async throws {
        let saved = try await store.upsert(text("hello", hash: "h1"), at: 1000)
        XCTAssertNotNil(saved.id)
        XCTAssertEqual(saved.lastUsedAt, 1000)
        XCTAssertEqual(saved.createdAt, 1000, "createdAt 未提供时用入库时刻")

        let page = try await store.page()
        XCTAssertEqual(page.count, 1)
        XCTAssertEqual(page.first?.plainText, "hello")
        let total = try await store.count()
        XCTAssertEqual(total, 1)
    }

    func testDedupPromotesAndPreservesPinned() async throws {
        _ = try await store.upsert(
            ClipItem(kind: .text, plainText: "dup", contentHash: "h1", pinned: true), at: 1000)
        let promoted = try await store.upsert(
            ClipItem(kind: .text, plainText: "dup", contentHash: "h1", pinned: false), at: 2000)

        let total = try await store.count()
        XCTAssertEqual(total, 1, "命中已有 hash 不新建行")
        XCTAssertEqual(promoted.lastUsedAt, 2000, "更新 last_used_at 置顶")
        XCTAssertTrue(promoted.pinned, "保留原 pinned，不被再次复制清掉")
    }

    func testKeysetPagination() async throws {
        for i in 1...120 {
            _ = try await store.upsert(text("n\(i)", hash: "h\(i)"), at: Int64(i))
        }
        let p1 = try await store.page(limit: 50)
        XCTAssertEqual(p1.count, 50)
        XCTAssertEqual(p1.first?.plainText, "n120", "最近在前")
        XCTAssertEqual(p1.last?.plainText, "n71")

        let p2 = try await store.page(after: p1.last, limit: 50)
        XCTAssertEqual(p2.count, 50)
        XCTAssertEqual(p2.first?.plainText, "n70")

        let p3 = try await store.page(after: p2.last, limit: 50)
        XCTAssertEqual(p3.count, 20)
        XCTAssertEqual(p3.last?.plainText, "n1")

        let all = (p1 + p2 + p3).compactMap(\.plainText)
        XCTAssertEqual(Set(all).count, 120, "分页无重叠且全覆盖")
    }

    func testPinnedSortsBeforeRecent() async throws {
        _ = try await store.upsert(text("old-recent", hash: "h1"), at: 5000)
        _ = try await store.upsert(
            ClipItem(kind: .text, plainText: "pinned-older", contentHash: "h2", pinned: true),
            at: 1000)
        let page = try await store.page()
        XCTAssertEqual(page.first?.plainText, "pinned-older", "置顶恒在最前，即便 last_used_at 更旧")
    }

    func testChineseFTSSearch() async throws {
        _ = try await store.upsert(text("这是一个验证码 823914 请查收", hash: "h1"), at: 100)
        _ = try await store.upsert(text("完全无关的一段内容", hash: "h2"), at: 200)

        let hits = try await store.search("验证码")
        XCTAssertEqual(hits.map(\.contentHash), ["h1"])

        // trigram 子串：搜非词首的中间片段也命中
        let sub = try await store.search("一个验")
        XCTAssertEqual(sub.first?.contentHash, "h1")
    }

    func testShortQueryUsesLikeFallback() async throws {
        _ = try await store.upsert(text("abcdefgh", hash: "h1"), at: 100)
        _ = try await store.upsert(text("xyz", hash: "h2"), at: 200)
        // 2 字符 < 3 → LIKE 子串回退
        let hits = try await store.search("cd")
        XCTAssertEqual(hits.map(\.contentHash), ["h1"])
    }

    func testSearchMatchesAppName() async throws {
        _ = try await store.upsert(
            ClipItem(kind: .text, plainText: "body one", contentHash: "h1", appName: "Safari"), at: 100)
        _ = try await store.upsert(
            ClipItem(kind: .text, plainText: "body two", contentHash: "h2", appName: "Notes"), at: 200)
        let hits = try await store.search("Safari")
        XCTAssertEqual(hits.map(\.contentHash), ["h1"], "来源 App 名参与匹配")
    }

    func testEmptyQueryReturnsRecent() async throws {
        _ = try await store.upsert(text("a", hash: "h1"), at: 100)
        _ = try await store.upsert(text("b", hash: "h2"), at: 200)
        let hits = try await store.search("   ")
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits.first?.contentHash, "h2", "空查询回退最近一页")
    }

    func testFileURLsRoundTripAsJSON() async throws {
        let draft = ClipItem(kind: .file, label: "a.txt, b.txt",
                             fileURLs: ["/tmp/a.txt", "/tmp/b.txt"], contentHash: "hf")
        _ = try await store.upsert(draft, at: 100)
        let fetched = try await store.page().first
        XCTAssertEqual(fetched?.fileURLs, ["/tmp/a.txt", "/tmp/b.txt"])
        XCTAssertEqual(fetched?.kind, .file)
    }
}
