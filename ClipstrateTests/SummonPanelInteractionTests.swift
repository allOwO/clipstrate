import XCTest
@testable import Clipstrate

@MainActor
final class SummonPanelInteractionTests: XCTestCase {
    private func item(_ hash: String, kind: ClipKind = .text) -> ClipItem {
        ClipItem(kind: kind, plainText: kind == .text ? hash : nil, contentHash: hash)
    }

    func testHorizontalSelectionWrapsAndReturnsToCardLayer() {
        let model = SummonPanelModel(historyStore: nil, initialItems: [item("a"), item("b"), item("c")])
        model.beginPresentation()

        XCTAssertTrue(model.handle(.moveLeft))
        XCTAssertEqual(model.selectedIndex, 2)
        model.handle(.moveDown)
        XCTAssertEqual(model.focus, .action(0))
        model.handle(.moveRight)
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.focus, .card)
    }

    func testTextActionFocusCyclesBothDirections() {
        let model = SummonPanelModel(historyStore: nil, initialItems: [item("a")])
        model.handle(.moveDown)
        XCTAssertEqual(model.focus, .action(0))
        model.handle(.moveDown)
        XCTAssertEqual(model.focus, .action(1))
        model.handle(.moveDown)
        XCTAssertEqual(model.focus, .card)
        model.handle(.moveUp)
        XCTAssertEqual(model.focus, .action(1))
        model.handle(.moveUp)
        XCTAssertEqual(model.focus, .action(0))
    }

    func testImageCardIgnoresActionLayer() {
        let model = SummonPanelModel(historyStore: nil, initialItems: [item("image", kind: .image)])
        model.handle(.moveDown)
        XCTAssertEqual(model.focus, .card)
        model.handle(.activatePlainText)
        XCTAssertEqual(model.focus, .card)
    }

    func testActivationAndMouseSemantics() {
        var calls: [(String, Bool)] = []
        let model = SummonPanelModel(
            historyStore: nil,
            pasteHandler: { calls.append(($0.contentHash, $1)) },
            initialItems: [item("a"), item("b")]
        )

        model.activateCard(at: 1)
        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertTrue(calls.isEmpty)
        model.activateCard(at: 1)
        XCTAssertEqual(calls.map(\.0), ["b"])
        model.handle(.activatePlainText)
        XCTAssertEqual(calls.map(\.1), [false, true])
    }

    func testEscapeReturnsFromActionLayerThenRequestsClose() {
        let model = SummonPanelModel(historyStore: nil, initialItems: [item("a")])
        model.handle(.moveDown)
        XCTAssertTrue(model.handle(.escape))
        XCTAssertEqual(model.focus, .card)
        XCTAssertFalse(model.handle(.escape))
    }
}
