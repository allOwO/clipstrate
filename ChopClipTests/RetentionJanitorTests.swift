import XCTest
@testable import ChopClip

@MainActor
final class RetentionJanitorTests: XCTestCase {
    private var tempDir: URL!
    private var store: HistoryStore!
    private var blobs: BlobStore!
    private var janitor: RetentionJanitor!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChopClipJanitor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try HistoryStore(path: tempDir.appendingPathComponent("history.sqlite").path)
        blobs = try BlobStore(blobsDir: tempDir.appendingPathComponent("blobs"),
                              thumbsDir: tempDir.appendingPathComponent("thumbs"))
        janitor = RetentionJanitor(store: store, blobs: blobs)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// 插入一条带 blob 的图片条目，并把 blob 文件真的写到盘上。
    @discardableResult
    private func insertImage(hash: String, at usedAt: Int64, byteSize: Int,
                             pinned: Bool = false) async throws -> ClipItem {
        let name = "\(hash).png"
        try blobs.writeBlob(Data(count: byteSize), name: name)
        let draft = ClipItem(kind: .image, blobPath: name, contentHash: hash,
                             byteSize: byteSize, pinned: pinned)
        return try await store.upsert(draft, at: usedAt)
    }

    func testExpiredUnpinnedDeletedWithBlobs() async throws {
        let now: Int64 = 10_000_000_000       // 任意“现在”
        let dayMs: Int64 = 86_400 * 1000
        try await insertImage(hash: "old", at: now - 2 * dayMs, byteSize: 10)            // 过期
        try await insertImage(hash: "fresh", at: now - 1000, byteSize: 10)               // 新鲜
        try await insertImage(hash: "oldpinned", at: now - 5 * dayMs, byteSize: 10, pinned: true) // 过期但置顶

        try await janitor.runOnce(retention: .day, diskCapBytes: .max, now: now)

        let remaining = try await store.page().map(\.contentHash)
        XCTAssertEqual(Set(remaining), ["fresh", "oldpinned"], "过期未置顶被删；新鲜与置顶保留")
        XCTAssertFalse(blobs.blobExists("old.png"), "过期条目的 blob 同步删除")
        XCTAssertTrue(blobs.blobExists("fresh.png"))
        XCTAssertTrue(blobs.blobExists("oldpinned.png"))
    }

    func testCapacityTrimDeletesOldestUnpinnedWithBlobs() async throws {
        // 5 条各 100B，总 500B；last_used_at 递增（1..5，1 最旧）。
        for i in 1...5 {
            try await insertImage(hash: "c\(i)", at: Int64(i), byteSize: 100)
        }
        // 上限 250B：从旧到新删到 ≤250 → 删 c1/c2/c3（剩 200B），保留 c4/c5。
        try await janitor.runOnce(retention: .unlimited, diskCapBytes: 250, now: 100)

        let remaining = try await store.page().map(\.contentHash)
        XCTAssertEqual(Set(remaining), ["c4", "c5"])
        for gone in ["c1", "c2", "c3"] { XCTAssertFalse(blobs.blobExists("\(gone).png")) }
        for kept in ["c4", "c5"] { XCTAssertTrue(blobs.blobExists("\(kept).png")) }
        let total = try await store.totalByteSize()
        XCTAssertLessThanOrEqual(total, 250)
    }

    func testPinnedNeverDeletedEvenOverCap() async throws {
        for i in 1...3 {
            try await insertImage(hash: "p\(i)", at: Int64(i), byteSize: 100, pinned: true)
        }
        try await janitor.runOnce(retention: .unlimited, diskCapBytes: 50, now: 100)
        let count = try await store.count()
        XCTAssertEqual(count, 3, "置顶条目即便超容量也不删")
    }

    func testUnlimitedRetentionAndHugeCapKeepsEverything() async throws {
        try await insertImage(hash: "a", at: 1, byteSize: 100)
        try await insertImage(hash: "b", at: 2, byteSize: 100)
        try await janitor.runOnce(retention: .unlimited, diskCapBytes: .max, now: 999_999_999_999)
        let count = try await store.count()
        XCTAssertEqual(count, 2)
    }
}
