import Foundation
import Observation

enum ChopOverlayCommand: Equatable {
    case entity(number: Int)
    case copySelection
    case pasteSelection
    case selectAll
    case close
}

enum ChopOverlayEffect: Equatable {
    case none
    case shake
    case copy(text: String, toast: String?)
    case paste(text: String)
    case close
}

@MainActor
@Observable
final class ChopOverlayModel {
    let text: String

    private(set) var tokens: [ChopToken]
    private(set) var entities: [DetectedEntity]
    private(set) var isLoading = false
    private(set) var selectedTokenIDs: Set<Int> = []

    private let segmenter: any Segmenter
    private let detector: EntityDetector
    private var dragAnchorIndex: Int?
    private var dragSelects = true
    private var selectionBeforeDrag: Set<Int> = []

    init(
        text: String,
        tokens: [ChopToken] = [],
        entities: [DetectedEntity] = [],
        segmenter: any Segmenter = NLSegmenter(),
        detector: EntityDetector = EntityDetector()
    ) {
        self.text = text
        self.tokens = tokens
        self.entities = entities
        self.segmenter = segmenter
        self.detector = detector
    }

    var selectedCount: Int { selectedTokenIDs.count }

    func load() async {
        guard tokens.isEmpty, !text.isEmpty else { return }
        isLoading = true

        let segmenter = segmenter
        let detector = detector
        let text = text
        async let tokenResult = Task.detached(priority: .userInitiated) {
            segmenter.tokens(in: text)
        }.value
        async let entityResult = Task.detached(priority: .userInitiated) {
            detector.entities(in: text)
        }.value

        let (loadedTokens, loadedEntities) = await (tokenResult, entityResult)
        guard !Task.isCancelled else {
            isLoading = false
            return
        }

        tokens = loadedTokens
        entities = loadedEntities
        selectedTokenIDs.formIntersection(loadedTokens.map(\.id))
        isLoading = false
    }

    func isSelected(_ token: ChopToken) -> Bool {
        selectedTokenIDs.contains(token.id)
    }

    func toggleToken(at index: Int) {
        guard tokens.indices.contains(index) else { return }
        let id = tokens[index].id
        if selectedTokenIDs.contains(id) {
            selectedTokenIDs.remove(id)
        } else {
            selectedTokenIDs.insert(id)
        }
    }

    /// Mouse-down toggles the anchor and fixes the select/deselect mode for the
    /// entire stroke (01 §4.3).
    func beginDrag(at index: Int) {
        guard tokens.indices.contains(index) else { return }
        selectionBeforeDrag = selectedTokenIDs
        dragAnchorIndex = index
        dragSelects = !selectedTokenIDs.contains(tokens[index].id)
        updateDrag(to: index)
    }

    /// Rebuild from the mouse-down snapshot on every move. This is what makes a
    /// backwards stroke shrink and restores tokens outside the current range.
    func updateDrag(to index: Int) {
        guard let anchor = dragAnchorIndex, tokens.indices.contains(index) else { return }
        selectedTokenIDs = selectionBeforeDrag
        let bounds = min(anchor, index)...max(anchor, index)

        for tokenIndex in bounds {
            let id = tokens[tokenIndex].id
            if dragSelects {
                selectedTokenIDs.insert(id)
            } else {
                selectedTokenIDs.remove(id)
            }
        }
    }

    func endDrag() {
        dragAnchorIndex = nil
        selectionBeforeDrag = []
    }

    func selectedText(separator: String = "") -> String {
        tokens
            .filter { selectedTokenIDs.contains($0.id) }
            .map(\.text)
            .joined(separator: separator)
    }

    @discardableResult
    func perform(_ command: ChopOverlayCommand, separator: String = "") -> ChopOverlayEffect {
        switch command {
        case let .entity(number):
            guard entities.indices.contains(number - 1) else { return .none }
            let value = entities[number - 1].value
            return .copy(text: value, toast: "已复制：\(value) ✓")

        case .copySelection:
            let value = selectedText(separator: separator)
            return value.isEmpty ? .shake : .copy(text: value, toast: nil)

        case .pasteSelection:
            let value = selectedText(separator: separator)
            return value.isEmpty ? .shake : .paste(text: value)

        case .selectAll:
            selectedTokenIDs = Set(tokens.map(\.id))
            return .none

        case .close:
            return .close
        }
    }
}
