import Foundation

/// ClipItem → 卡片文案与轻量 meta 的纯映射。
struct ClipCardPresentation: Equatable, Sendable {
    let typeLabel: String
    let body: String
    let sourceName: String?
    let symbolName: String
    let meta: String?

    init(item: ClipItem) {
        sourceName = item.appName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        switch item.kind {
        case .text:
            typeLabel = item.isRich ? "富文本" : "文本"
            body = item.plainText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "空文本"
            symbolName = "text.alignleft"
            meta = item.truncated ? "内容已截断" : nil
        case .image:
            typeLabel = "图片"
            body = item.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "图片"
            symbolName = "photo"
            meta = Self.imageMeta(item)
        case .file:
            typeLabel = "文件"
            body = Self.fileLabel(item)
            symbolName = "doc"
            meta = nil
        }
    }

    private static func imageMeta(_ item: ClipItem) -> String? {
        if let thumbPath = item.thumbPath,
           let descriptor = ImageThumbnailDescriptor(fileName: thumbPath) {
            let size = ByteCountFormatter.string(
                fromByteCount: Int64(descriptor.originalByteSize),
                countStyle: .file
            )
            return "\(descriptor.pixelWidth) × \(descriptor.pixelHeight) · \(descriptor.format) · \(size)"
        }
        var parts: [String] = []
        if let ext = item.blobPath.map({ URL(fileURLWithPath: $0).pathExtension.uppercased() }), !ext.isEmpty {
            parts.append(ext)
        }
        if item.byteSize > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func fileLabel(_ item: ClipItem) -> String {
        if let label = item.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return label
        }
        let names = item.fileURLs?.map { URL(fileURLWithPath: $0).lastPathComponent }
            .filter { !$0.isEmpty } ?? []
        return names.isEmpty ? "文件" : names.joined(separator: ", ")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
