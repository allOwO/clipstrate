import Foundation
import CryptoKit

/// 去重指纹（01 §1.3）：`SHA-256(kind + 规范化内容)`。
/// - text：用 `plain_text`
/// - image：用原始数据
/// - file：用排序后的路径列表（顺序无关）
///
/// 规范化 = 原文本身（不做 trim/大小写折叠），保证「看起来不同即不同条目」。
enum ContentHash {
    static func text(_ plain: String) -> String {
        digest(kind: .text, Data(plain.utf8))
    }

    static func image(_ data: Data) -> String {
        digest(kind: .image, data)
    }

    static func file(_ paths: [String]) -> String {
        digest(kind: .file, Data(paths.sorted().joined(separator: "\n").utf8))
    }

    private static func digest(kind: ClipKind, _ content: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: content)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
