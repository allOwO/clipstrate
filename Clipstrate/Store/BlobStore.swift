import Foundation

struct BlobStoreLocations: Sendable {
    let blobs: URL
    let thumbs: URL
}

/// blob / thumb 落盘与删除（01 §2）。内容寻址：文件名通常 = `content_hash`。
/// DB 只存相对文件名（`blob_path` 相对 `blobs/`、`thumb_path` 相对 `thumbs/`）。
///
/// 纯文件 I/O，调用方须在后台线程调用（主线程禁止 I/O）。缩略图的生成
/// （ImageIO 降采样）在 T1.6，本类只负责字节读写与删除。
final class BlobStore: Sendable {
    private let blobsDir: URL
    private let thumbsDir: URL

    init(blobsDir: URL, thumbsDir: URL) throws {
        self.blobsDir = blobsDir
        self.thumbsDir = thumbsDir
        let fm = FileManager.default
        try fm.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
    }

    var locations: BlobStoreLocations {
        BlobStoreLocations(blobs: blobsDir, thumbs: thumbsDir)
    }

    static func makeDefault() throws -> BlobStore {
        try BlobStore(blobsDir: AppPaths.blobsDirectory(),
                      thumbsDir: AppPaths.thumbsDirectory())
    }

    // MARK: - blobs

    /// 原子写入 blob，返回相对文件名（存入 `item.blob_path`）。
    @discardableResult
    func writeBlob(_ data: Data, name: String) throws -> String {
        try data.write(to: blobsDir.appendingPathComponent(name), options: .atomic)
        return name
    }

    func readBlob(_ name: String) throws -> Data {
        try Data(contentsOf: blobURL(name))
    }

    func blobExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: blobURL(name).path)
    }

    /// 删除 blob（幂等，缺失不报错）。
    func deleteBlob(_ name: String) {
        try? FileManager.default.removeItem(at: blobURL(name))
    }

    func blobURL(_ name: String) -> URL {
        blobsDir.appendingPathComponent(name)
    }

    // MARK: - thumbs

    @discardableResult
    func writeThumb(_ data: Data, name: String) throws -> String {
        try data.write(to: thumbsDir.appendingPathComponent(name), options: .atomic)
        return name
    }

    func readThumb(_ name: String) throws -> Data {
        try Data(contentsOf: thumbURL(name))
    }

    func thumbExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: thumbURL(name).path)
    }

    func deleteThumb(_ name: String) {
        try? FileManager.default.removeItem(at: thumbURL(name))
    }

    func thumbURL(_ name: String) -> URL {
        thumbsDir.appendingPathComponent(name)
    }
}
