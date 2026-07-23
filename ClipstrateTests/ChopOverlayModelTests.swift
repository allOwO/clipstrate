import XCTest
@testable import Clipstrate

@MainActor
final class ChopOverlayModelTests: XCTestCase {
    func testClickTogglesOneToken() {
        let model = makeModel(count: 4)

        model.beginDrag(at: 1)
        model.endDrag()
        XCTAssertEqual(model.selectedTokenIDs, [1])

        model.beginDrag(at: 1)
        model.endDrag()
        XCTAssertTrue(model.selectedTokenIDs.isEmpty)
    }

    func testSelectingDragShrinksWhenMovingBackwards() {
        let model = makeModel(count: 6)

        model.beginDrag(at: 1)
        model.updateDrag(to: 4)
        XCTAssertEqual(model.selectedTokenIDs, [1, 2, 3, 4])

        model.updateDrag(to: 2)
        XCTAssertEqual(model.selectedTokenIDs, [1, 2])
    }

    func testDeselectingDragRestoresSnapshotOutsideCurrentRange() {
        let model = makeModel(count: 6)
        for index in 1...4 { model.toggleToken(at: index) }

        model.beginDrag(at: 2)
        model.updateDrag(to: 4)
        XCTAssertEqual(model.selectedTokenIDs, [1])

        model.updateDrag(to: 3)
        XCTAssertEqual(model.selectedTokenIDs, [1, 4])
    }

    func testDragPreservesSelectionOutsideRange() {
        let model = makeModel(count: 6)
        model.toggleToken(at: 0)
        model.toggleToken(at: 5)

        model.beginDrag(at: 2)
        model.updateDrag(to: 3)

        XCTAssertEqual(model.selectedTokenIDs, [0, 2, 3, 5])
    }

    func testSelectedTextUsesSourceOrderNotSelectionOrder() {
        let model = makeModel(count: 5)
        model.toggleToken(at: 4)
        model.toggleToken(at: 1)
        model.toggleToken(at: 3)

        XCTAssertEqual(model.selectedText(), "t1t3t4")
        XCTAssertEqual(model.selectedText(separator: " "), "t1 t3 t4")
    }

    func testAsyncLoadRunsSegmenterAndDetector() async {
        let model = ChopOverlayModel(text: "验证码 123456")

        await model.load()

        XCTAssertFalse(model.tokens.isEmpty)
        XCTAssertEqual(model.entities.first?.kind, .verificationCode)
        XCTAssertFalse(model.isLoading)
    }

    func testNumberCopiesMatchingEntityWithToast() {
        let entities = [
            makeEntity(value: "first", location: 0),
            makeEntity(value: "second", location: 6)
        ]
        let model = ChopOverlayModel(text: "first second", entities: entities)

        XCTAssertEqual(
            model.perform(.entity(number: 2)),
            .copy(text: "second", toast: "已复制：second ✓")
        )
        XCTAssertEqual(model.perform(.entity(number: 0)), .none)
        XCTAssertEqual(model.perform(.entity(number: 9)), .none)
    }

    func testReturnCopiesSelectedTextInSourceOrder() {
        let model = makeModel(count: 5)
        model.toggleToken(at: 4)
        model.toggleToken(at: 1)

        XCTAssertEqual(
            model.perform(.copySelection),
            .copy(text: "t1t4", toast: nil)
        )
    }

    func testReturnVariantsWithEmptySelectionRequestShake() {
        let model = makeModel(count: 2)
        XCTAssertEqual(model.perform(.copySelection), .shake)
        XCTAssertEqual(model.perform(.pasteSelection), .shake)
    }

    func testShiftReturnPastesSelectedText() {
        let model = makeModel(count: 3)
        model.toggleToken(at: 0)
        model.toggleToken(at: 2)

        XCTAssertEqual(model.perform(.pasteSelection), .paste(text: "t0t2"))
    }

    func testCommandASelectsEveryToken() {
        let model = makeModel(count: 4)

        XCTAssertEqual(model.perform(.selectAll), .none)
        XCTAssertEqual(model.selectedTokenIDs, [0, 1, 2, 3])
    }

    func testEscapeRequestsClose() {
        XCTAssertEqual(makeModel(count: 1).perform(.close), .close)
    }

    private func makeModel(count: Int) -> ChopOverlayModel {
        let tokens = (0..<count).map {
            ChopToken(
                id: $0,
                text: "t\($0)",
                sourceRange: NSRange(location: $0 * 2, length: 2),
                isPunctuation: false
            )
        }
        return ChopOverlayModel(text: tokens.map(\.text).joined(), tokens: tokens)
    }

    private func makeEntity(value: String, location: Int) -> DetectedEntity {
        DetectedEntity(
            kind: .verificationCode,
            value: value,
            sourceRange: NSRange(location: location, length: value.utf16.count),
            icon: "key.fill",
            priority: 500
        )
    }
}
