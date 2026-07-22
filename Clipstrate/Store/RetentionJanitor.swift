import Foundation

/// 配额清理（01 §2）：每次启动 + 每小时执行一次。
/// 1. 删除超过存储时限的未置顶条目；
/// 2. 若 `byte_size` 总量仍超磁盘上限，按 `last_used_at` 从旧到新删未置顶直至达标；
/// 3. 删行（DB 事务）之后再删对应 blob/thumb 文件。
///
/// 置顶条目永不被清理（时限与容量都豁免）。
final class RetentionJanitor: Sendable {
    private let store: HistoryStore
    private let blobs: BlobStore

    init(store: HistoryStore, blobs: BlobStore) {
        self.store = store
        self.blobs = blobs
    }

    /// 用当前设置执行一次。
    func runOnce(now: Int64 = HistoryStore.nowMillis()) async throws {
        try await runOnce(
            retention: Settings.retention,
            diskCapBytes: Int64(Settings.diskCapMB) * 1024 * 1024,
            now: now
        )
    }

    /// 可注入参数版本（便于单测）。
    func runOnce(retention: Retention, diskCapBytes: Int64,
                 now: Int64 = HistoryStore.nowMillis()) async throws {
        var deleted: [ClipItem] = []

        // 1. 超时限
        if let maxAge = retention.maxAgeSeconds {
            let cutoff = now - Int64(maxAge * 1000)
            let expired = try await store.expiredUnpinned(olderThan: cutoff)
            if !expired.isEmpty {
                try await store.delete(ids: expired.compactMap(\.id))
                deleted.append(contentsOf: expired)
            }
        }

        // 2. 超容量：从旧到新删未置顶，直至总量 ≤ 上限（置顶不动）。
        var total = try await store.totalByteSize()
        if total > diskCapBytes {
            var toDelete: [ClipItem] = []
            for item in try await store.unpinnedOldestFirst() {
                if total <= diskCapBytes { break }
                toDelete.append(item)
                total -= Int64(item.byteSize)
            }
            if !toDelete.isEmpty {
                try await store.delete(ids: toDelete.compactMap(\.id))
                deleted.append(contentsOf: toDelete)
            }
        }

        // 3. 事务后删文件（DB 已提交，避免回滚后误删）。
        for item in deleted {
            if let blobPath = item.blobPath { blobs.deleteBlob(blobPath) }
            if let thumbPath = item.thumbPath { blobs.deleteThumb(thumbPath) }
        }

        if !deleted.isEmpty {
            Log.store.info("retention cleaned \(deleted.count, privacy: .public) item(s)")
        }
    }
}
