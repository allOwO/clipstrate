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

    /// 滚动中指针静止：掠过的悬停被挡下（防重排抖动），但滚动一停选中要对齐到
    /// 最后掠过光标的卡（跟手），且这种选中不触发自动滚动。
    func testHoverDuringScrollAppliesWhenScrollingStops() {
        let model = SummonPanelModel(
            historyStore: nil,
            initialItems: (0..<10).map { item("h\($0)") }
        )
        model.beginPresentation()   // lastHoverLocation 取当前指针，测试期间指针视为静止

        model.scrollPhaseChanged(isScrolling: true)
        model.hoverSelect(at: 3)
        model.hoverSelect(at: 5)
        XCTAssertEqual(model.selectedIndex, 0, "滚动中指针静止的悬停不得改选中")

        model.scrollPhaseChanged(isScrolling: false)
        XCTAssertEqual(model.selectedIndex, 5, "滚动停止后选中对齐到最后掠过的卡")
        XCTAssertFalse(model.shouldAutoScrollToSelection(), "悬停型选中不自动滚动定位")
    }

    /// 非滚动状态下指针静止的悬停（如选中卡放大导致布局移动）不产生待定悬停，
    /// 后续滚动结束时也不会被误应用。
    func testStationaryHoverOutsideScrollingIsIgnored() {
        let model = SummonPanelModel(
            historyStore: nil,
            initialItems: (0..<10).map { item("s\($0)") }
        )
        model.beginPresentation()

        model.hoverSelect(at: 4)
        XCTAssertEqual(model.selectedIndex, 0, "指针未移动的悬停不改选中")

        model.scrollPhaseChanged(isScrolling: true)
        model.scrollPhaseChanged(isScrolling: false)
        XCTAssertEqual(model.selectedIndex, 0, "无滚动期悬停不得残留为待定悬停")
    }
}
