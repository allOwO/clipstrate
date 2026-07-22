import AppKit
import ImageIO

private struct SendableCGImage: @unchecked Sendable {
    let image: CGImage
}

/// 卡片媒体资源加载器。缓存有硬上限；缩略图解码、富文本解析与文件 stat 均在后台。
final class CardAssetLoader: @unchecked Sendable {
    static let shared = CardAssetLoader()

    private let thumbnails = NSCache<NSString, CGImage>()
    private let richDocuments = NSCache<NSString, NSAttributedString>()
    private static let maximumRichBytes = 2 * 1024 * 1024

    private init() {
        thumbnails.countLimit = 64
        thumbnails.totalCostLimit = 24 * 1024 * 1024
        richDocuments.countLimit = 64
        richDocuments.totalCostLimit = 8 * 1024 * 1024
    }

    func thumbnail(named name: String, store: BlobStore) async -> CGImage? {
        if let cached = thumbnails.object(forKey: name as NSString) { return cached }
        let boxed: SendableCGImage? = await Task.detached(priority: .userInitiated) { [thumbnails] in
            guard let data = try? store.readThumb(name),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [
                    kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary) else { return nil }
            thumbnails.setObject(image, forKey: name as NSString, cost: image.bytesPerRow * image.height)
            return SendableCGImage(image: image)
        }.value
        return boxed?.image
    }

    func richText(for item: ClipItem, store: BlobStore) async -> AttributedString? {
        guard item.byteSize <= Self.maximumRichBytes,
              let name = item.blobPath,
              let richType = item.richType,
              richType == "rtf" || richType == "html" else { return nil }
        if let cached = richDocuments.object(forKey: name as NSString) {
            return AttributedString(cached)
        }
        return await Task.detached(priority: .userInitiated) { [richDocuments] in
            guard let data = try? store.readBlob(name), data.count <= Self.maximumRichBytes else { return nil }
            let documentType: NSAttributedString.DocumentType = richType == "rtf" ? .rtf : .html
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: documentType,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]
            guard let document = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
                return nil
            }
            let bounded = NSMutableAttributedString(attributedString: document)
            var attachmentRanges: [NSRange] = []
            bounded.enumerateAttribute(.attachment, in: NSRange(location: 0, length: bounded.length)) { value, range, _ in
                if value != nil { attachmentRanges.append(range) }
            }
            for range in attachmentRanges.reversed() {
                bounded.replaceCharacters(in: range, with: "[附件]")
            }
            richDocuments.setObject(bounded, forKey: name as NSString, cost: min(Self.maximumRichBytes, bounded.length * 8))
            return AttributedString(bounded)
        }.value
    }

    func fileMeta(paths: [String]) async -> String? {
        await Task.detached(priority: .utility) {
            guard let first = paths.first else { return nil }
            let firstURL = URL(fileURLWithPath: first)
            let folder = (firstURL.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            let totalBytes = paths.reduce(Int64(0)) { partial, path in
                let size = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return partial + Int64(size)
            }
            if totalBytes > 0 {
                return "\(folder) · \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
            }
            return folder
        }.value
    }
}
