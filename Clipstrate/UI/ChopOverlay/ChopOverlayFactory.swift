import SwiftUI

/// Side effects are injected at the UI/System boundary so ChopOverlay remains
/// independently testable and never reaches into PasteService or panel state.
@MainActor
struct ChopOverlayActions {
    let copyText: (String) -> Void
    let pasteText: (String) -> Void
    let showToast: (String) -> Void

    init(
        copyText: @escaping (String) -> Void,
        pasteText: @escaping (String) -> Void,
        showToast: @escaping (String) -> Void
    ) {
        self.copyText = copyText
        self.pasteText = pasteText
        self.showToast = showToast
    }

    static let preview = ChopOverlayActions(
        copyText: { _ in },
        pasteText: { _ in },
        showToast: { _ in }
    )
}

@MainActor
enum ChopOverlayFactory {
    /// Adapter for A's stable SummonPanel overlay slot.
    static func makeBuilder(actions: ChopOverlayActions) -> ChopOverlayBuilder {
        { request, onClose in
            AnyView(
                ChopOverlayView(
                    text: request.text,
                    actions: actions,
                    onClose: onClose
                )
            )
        }
    }
}
