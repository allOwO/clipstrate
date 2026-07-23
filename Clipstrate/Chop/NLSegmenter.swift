import Foundation
import NaturalLanguage

/// Offline word segmentation backed by NaturalLanguage's word tokenizer.
struct NLSegmenter: Segmenter {
    func tokens(in text: String) -> [ChopToken] {
        guard !text.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }

        var pieces: [TokenPiece] = []
        var cursor = text.startIndex

        for range in ranges {
            appendGap(in: cursor..<range.lowerBound, from: text, to: &pieces)
            pieces.append(TokenPiece(range: range, isPunctuation: isPunctuation(text[range])))
            cursor = range.upperBound
        }
        appendGap(in: cursor..<text.endIndex, from: text, to: &pieces)

        return pieces.enumerated().map { index, piece in
            ChopToken(
                id: index,
                text: String(text[piece.range]),
                sourceRange: NSRange(piece.range, in: text),
                isPunctuation: piece.isPunctuation
            )
        }
    }

    /// `NLTokenizer(.word)` omits punctuation and symbols. Add those gaps back
    /// while deliberately omitting whitespace, which is not a selectable word
    /// block and matches the default no-separator join behavior.
    private func appendGap(
        in range: Range<String.Index>,
        from text: String,
        to pieces: inout [TokenPiece]
    ) {
        var index = range.lowerBound

        while index < range.upperBound {
            if text[index].isWhitespace {
                index = text.index(after: index)
                continue
            }

            let start = index
            let punctuation = isPunctuation(text[index...index])
            index = text.index(after: index)

            while index < range.upperBound,
                  !text[index].isWhitespace,
                  isPunctuation(text[index...index]) == punctuation {
                index = text.index(after: index)
            }

            pieces.append(
                TokenPiece(range: start..<index, isPunctuation: punctuation)
            )
        }
    }

    private func isPunctuation(_ text: Substring) -> Bool {
        !text.unicodeScalars.isEmpty
            && text.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains)
    }
}

private struct TokenPiece {
    let range: Range<String.Index>
    let isPunctuation: Bool
}
