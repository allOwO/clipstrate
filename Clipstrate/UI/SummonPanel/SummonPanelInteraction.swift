import Foundation

enum SummonPanelFocus: Equatable, Sendable {
    case card
    case action(Int)
}

enum SummonPanelCommand: Equatable, Sendable {
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case activate
    case activatePlainText
    case openChop
    case escape
}

typealias SummonPasteHandler = @MainActor (_ item: ClipItem, _ plainText: Bool) -> Void
