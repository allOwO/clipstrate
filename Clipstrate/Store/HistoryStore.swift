import Foundation
import GRDB

/// 历史库唯一入口（02 §7）。包装 GRDB `DatabasePool`（WAL，内部读写并发）；
/// 对外全 async，写串行、读并行。主线程禁止直接调用其底层——一律 `await`。
///
/// FTS：`item_fts` 用 trigram 分词器做中文子串搜索；由三个触发器与 `item` 同步
/// （见 migration v1）。trigram 查询要求 ≥3 字符，更短查询回退 `LIKE`（02 §4）。
final class HistoryStore: Sendable {
    private let dbPool: DatabasePool

    /// 打开（或创建）指定路径的库并跑迁移。
    init(path: String) throws {
        dbPool = try DatabasePool(path: path)
        try Self.migrator.migrate(dbPool)
    }

    /// 默认库：Application Support/Clipstrate/history.sqlite。
    static func makeDefault() throws -> HistoryStore {
        try HistoryStore(path: AppPaths.databaseFile().path)
    }

    // MARK: - 迁移

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE item (
                  id            INTEGER PRIMARY KEY AUTOINCREMENT,
                  kind          TEXT    NOT NULL,
                  is_rich       INTEGER NOT NULL DEFAULT 0,
                  plain_text    TEXT,
                  label         TEXT,
                  rich_type     TEXT,
                  blob_path     TEXT,
                  thumb_path    TEXT,
                  file_urls     TEXT,
                  content_hash  TEXT    NOT NULL UNIQUE,
                  app_bundle_id TEXT,
                  app_name      TEXT,
                  byte_size     INTEGER NOT NULL DEFAULT 0,
                  truncated     INTEGER NOT NULL DEFAULT 0,
                  pinned        INTEGER NOT NULL DEFAULT 0,
                  created_at    INTEGER NOT NULL,
                  last_used_at  INTEGER NOT NULL
                );

                CREATE INDEX idx_item_recency ON item(pinned DESC, last_used_at DESC);

                CREATE VIRTUAL TABLE item_fts USING fts5(
                  plain_text, label, app_name,
                  content='item', content_rowid='id', tokenize='trigram'
                );

                -- 外部内容表同步触发器：仅索引 plain_text / label / app_name 三列。
                CREATE TRIGGER item_ai AFTER INSERT ON item BEGIN
                  INSERT INTO item_fts(rowid, plain_text, label, app_name)
                  VALUES (new.id, new.plain_text, new.label, new.app_name);
                END;

                CREATE TRIGGER item_ad AFTER DELETE ON item BEGIN
                  INSERT INTO item_fts(item_fts, rowid, plain_text, label, app_name)
                  VALUES ('delete', old.id, old.plain_text, old.label, old.app_name);
                END;

                -- 仅在被索引的三列真正变化时重建索引（置顶/更新 last_used_at 不触发）。
                CREATE TRIGGER item_au AFTER UPDATE ON item
                WHEN old.plain_text IS NOT new.plain_text
                  OR old.label      IS NOT new.label
                  OR old.app_name   IS NOT new.app_name
                BEGIN
                  INSERT INTO item_fts(item_fts, rowid, plain_text, label, app_name)
                  VALUES ('delete', old.id, old.plain_text, old.label, old.app_name);
                  INSERT INTO item_fts(rowid, plain_text, label, app_name)
                  VALUES (new.id, new.plain_text, new.label, new.app_name);
                END;
                """)
        }
        return migrator
    }

    // MARK: - 写入

    /// 入库或去重置顶（01 §1.3）：命中已有 `content_hash` 则只更新
    /// `last_used_at` 并保留原 `pinned`，不新建行；否则插入新行。返回已存行。
    @discardableResult
    func upsert(_ draft: ClipItem, at now: Int64 = HistoryStore.nowMillis()) async throws -> ClipItem {
        try await dbPool.write { db in
            if var existing = try ClipItem
                .filter(Column("content_hash") == draft.contentHash)
                .fetchOne(db) {
                existing.lastUsedAt = now
                try existing.update(db, columns: ["last_used_at"])
                return existing
            }
            var new = draft
            new.id = nil
            if new.createdAt == 0 { new.createdAt = now }
            new.lastUsedAt = now
            try new.insert(db)
            return new
        }
    }

    // MARK: - 读取

    /// keyset 分页（02 §4）：按 `pinned DESC, last_used_at DESC, id DESC`，
    /// 传上一页最后一条 `after` 取下一页。首页传 nil。
    func page(after cursor: ClipItem? = nil, limit: Int = 50) async throws -> [ClipItem] {
        try await dbPool.read { db in
            var request = ClipItem
                .order(sql: "pinned DESC, last_used_at DESC, id DESC")
                .limit(limit)
            if let cursor, let id = cursor.id {
                request = request.filter(
                    sql: "(pinned, last_used_at, id) < (?, ?, ?)",
                    arguments: [cursor.pinned, cursor.lastUsedAt, id]
                )
            }
            return try request.fetchAll(db)
        }
    }

    /// 搜索（01 §3.6 范围：正文 / label / 来源 App，同权）。≥3 字符走 FTS5 trigram，
    /// 更短走 `LIKE` 回退；空查询回退为最近一页。
    func search(_ query: String, limit: Int = 50) async throws -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return try await page(limit: limit) }

        return try await dbPool.read { db in
            if q.count >= 3 {
                // 作为字面字符串匹配（trigram 子串），双引号转义避免 MATCH 语法歧义。
                let match = "\"" + q.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                return try ClipItem.fetchAll(db, sql: """
                    SELECT item.* FROM item
                    JOIN item_fts ON item_fts.rowid = item.id
                    WHERE item_fts MATCH ?
                    ORDER BY item.pinned DESC, item.last_used_at DESC, item.id DESC
                    LIMIT ?
                    """, arguments: [match, limit])
            } else {
                let esc = q
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                let pattern = "%\(esc)%"
                return try ClipItem.fetchAll(db, sql: """
                    SELECT * FROM item
                    WHERE plain_text LIKE ? ESCAPE '\\'
                       OR label      LIKE ? ESCAPE '\\'
                       OR app_name   LIKE ? ESCAPE '\\'
                    ORDER BY pinned DESC, last_used_at DESC, id DESC
                    LIMIT ?
                    """, arguments: [pattern, pattern, pattern, limit])
            }
        }
    }

    func count() async throws -> Int {
        try await dbPool.read { db in try ClipItem.fetchCount(db) }
    }

    // MARK: - 清理（RetentionJanitor 用）

    /// 未置顶且 `last_used_at < cutoff` 的条目（超时限）。
    func expiredUnpinned(olderThan cutoffMs: Int64) async throws -> [ClipItem] {
        try await dbPool.read { db in
            try ClipItem
                .filter(sql: "pinned = 0 AND last_used_at < ?", arguments: [cutoffMs])
                .fetchAll(db)
        }
    }

    /// 未置顶条目，从旧到新（容量清理的删除顺序）。
    func unpinnedOldestFirst() async throws -> [ClipItem] {
        try await dbPool.read { db in
            try ClipItem
                .filter(sql: "pinned = 0")
                .order(sql: "last_used_at ASC, id ASC")
                .fetchAll(db)
        }
    }

    /// 所有条目 `byte_size` 之和（容量度量）。
    func totalByteSize() async throws -> Int64 {
        try await dbPool.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(byte_size), 0) FROM item") ?? 0
        }
    }

    @discardableResult
    func delete(ids: [Int64]) async throws -> Int {
        guard !ids.isEmpty else { return 0 }
        return try await dbPool.write { db in
            try ClipItem.deleteAll(db, keys: ids)
        }
    }

    /// 清空（工具 / 测试用）。
    func deleteAll() async throws {
        _ = try await dbPool.write { db in try ClipItem.deleteAll(db) }
    }

    // MARK: - 工具

    static func nowMillis() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}
