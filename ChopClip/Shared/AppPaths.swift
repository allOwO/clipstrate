import Foundation

/// App 落盘路径。数据全部在 `~/Library/Application Support/ChopClip/` 下：
/// `history.sqlite`（GRDB）、`blobs/`（富文本原数据 / 图片原图）、`thumbs/`（缩略图）。
enum AppPaths {
    static let appFolderName = "ChopClip"

    /// Application Support/ChopClip/（不存在则创建）。
    static func supportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(appFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func databaseFile() throws -> URL {
        try supportDirectory().appendingPathComponent("history.sqlite")
    }

    static func blobsDirectory() throws -> URL {
        try ensureSubdirectory("blobs")
    }

    static func thumbsDirectory() throws -> URL {
        try ensureSubdirectory("thumbs")
    }

    private static func ensureSubdirectory(_ name: String) throws -> URL {
        let dir = try supportDirectory().appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
