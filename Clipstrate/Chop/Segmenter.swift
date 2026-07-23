import Foundation

/// A value produced by the chop segmenter, ordered exactly as it appears in
/// the source text.
struct ChopToken: Identifiable, Sendable, Hashable {
    let id: Int
    let text: String
    let sourceRange: NSRange
    let isPunctuation: Bool
}

/// Text segmentation seam. Implementations are synchronous pure logic so the
/// caller can run them together with entity detection in a detached task.
protocol Segmenter: Sendable {
    func tokens(in text: String) -> [ChopToken]
}
