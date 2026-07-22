import Foundation

/// ClipItem → 卡片文案的纯映射。T1.6 会把图片/文件占位内容替换为真实缩略图与图标。
struct ClipCardPresentation: Equatable, Sendable {
    let typeLabel: String
    let body: String
    let sourceName: String?
    let symbolName: String

    init(item: ClipItem) {
        sourceName = item.appName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        switch item.kind {
        case .text:
            typeLabel = item.isRich ? "富文本" : "文本"
            body = item.plainText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "空文本"
            symbolName = "text.alignleft"
        case .image:
            typeLabel = "图片"
            body = item.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "图片"
            symbolName = "photo"
        case .file:
            typeLabel = "文件"
            body = Self.fileLabel(item)
            symbolName = "doc"
        }
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
