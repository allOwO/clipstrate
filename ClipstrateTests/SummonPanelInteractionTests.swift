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
            pasteHandler: { item, plainText, _ in calls.append((item.contentHash, plainText)) },
            initialItems: [item("a"), item("b")]
        )

        // 单击任意卡片 = 直接粘贴（走 returnAction），不再需要“先选中再点一次”。
        model.activateCard(at: 1)
        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertEqual(calls.map(\.0), ["b"], "单击即粘贴")
        model.activateCard(at: 1)
        XCTAssertEqual(calls.map(\.0), ["b", "b"], "再次单击再次粘贴")
        model.handle(.activatePlainText)
        XCTAssertEqual(calls.map(\.1), [false, false, true])
    }

    func testEscapeReturnsFromActionLayerThenRequestsClose() {
        let model = SummonPanelModel(historyStore: nil, initialItems: [item("a")])
        model.handle(.moveDown)
        XCTAssertTrue(model.handle(.escape))
        XCTAssertEqual(model.focus, .card)
        XCTAssertFalse(model.handle(.escape))
    }

    func testDigitDirectPasteSelectsItemWithPressSource() {
        var calls: [(String, Bool, SummonPasteSource)] = []
        let model = SummonPanelModel(
            historyStore: nil,
            pasteHandler: { calls.append(($0.contentHash, $1, $2)) },
            initialItems: [item("a"), item("b"), item("c")]
        )
        model.beginPresentation()

        XCTAssertTrue(model.handle(.digit(2)))
        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, "b")
        XCTAssertEqual(calls.first?.1, false)
        XCTAssertEqual(calls.first?.2, .press)
    }

    func testDigitOutOfRangeIsConsumedButDoesNotPaste() {
        var count = 0
        let model = SummonPanelModel(
            historyStore: nil,
            pasteHandler: { _, _, _ in count += 1 },
            initialItems: [item("a"), item("b")]
        )
        model.beginPresentation()

        XCTAssertTrue(model.handle(.digit(5)), "越界数字仍被面板消费，不透传")
        XCTAssertEqual(count, 0)
    }

    func testEnterUsesReturnSource() {
        var sources: [SummonPasteSource] = []
        let model = SummonPanelModel(
            historyStore: nil,
            pasteHandler: { _, _, source in sources.append(source) },
            initialItems: [item("a")]
        )
        model.beginPresentation()

        model.handle(.activate)
        XCTAssertEqual(sources, [.return])
    }
}
