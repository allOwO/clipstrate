import Foundation
import GRDB

/// 条目类型（对应 `item.kind` 列）。
enum ClipKind: String, Codable, Sendable, CaseIterable {
    case text
    case image
    case file
}

/// 一条剪贴板历史记录。既是采集阶段的「草稿」（`id == nil`），
/// 也是入库后的「已存」行（`id` 由自增主键回填）。列定义见 02 §4。
///
/// 说明：`fileURLs` 为 `[String]?`，GRDB 会把它以 JSON 存进 `file_urls` TEXT 列；
/// `kind` 以其 rawValue 存进 `kind` TEXT 列；`Bool` 列按 SQLite 惯例存 0/1。
struct ClipItem: Codable, Sendable, Equatable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var kind: ClipKind
    var isRich: Bool
    var plainText: String?
    var label: String?
    var richType: String?          // 'rtf' | 'html'
    var blobPath: String?          // 相对 blobs/
    var thumbPath: String?         // 相对 thumbs/
    var fileURLs: [String]?        // file: 路径数组（JSON）
    var contentHash: String        // SHA-256(kind + 规范化内容)，UNIQUE
    var appBundleID: String?
    var appName: String?
    var byteSize: Int
    var truncated: Bool
    var pinned: Bool
    var createdAt: Int64           // Unix ms
    var lastUsedAt: Int64          // Unix ms

    init(
        id: Int64? = nil,
        kind: ClipKind,
        isRich: Bool = false,
        plainText: String? = nil,
        label: String? = nil,
        richType: String? = nil,
        blobPath: String? = nil,
        thumbPath: String? = nil,
        fileURLs: [String]? = nil,
        contentHash: String,
        appBundleID: String? = nil,
        appName: String? = nil,
        byteSize: Int = 0,
        truncated: Bool = false,
        pinned: Bool = false,
        createdAt: Int64 = 0,
        lastUsedAt: Int64 = 0
    ) {
        self.id = id
        self.kind = kind
        self.isRich = isRich
        self.plainText = plainText
        self.label = label
        self.richType = richType
        self.blobPath = blobPath
        self.thumbPath = thumbPath
        self.fileURLs = fileURLs
        self.contentHash = contentHash
        self.appBundleID = appBundleID
        self.appName = appName
        self.byteSize = byteSize
        self.truncated = truncated
        self.pinned = pinned
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// Swift 属性名 → snake_case 列名（GRDB 以此映射列）。
    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case isRich = "is_rich"
        case plainText = "plain_text"
        case label
        case richType = "rich_type"
        case blobPath = "blob_path"
        case thumbPath = "thumb_path"
        case fileURLs = "file_urls"
        case contentHash = "content_hash"
        case appBundleID = "app_bundle_id"
        case appName = "app_name"
        case byteSize = "byte_size"
        case truncated
        case pinned
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }

    static let databaseTableName = "item"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
