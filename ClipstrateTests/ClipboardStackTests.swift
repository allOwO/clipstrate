import XCTest
@testable import Clipstrate

final class ClipboardStackTests: XCTestCase {
    func testDisabledStackIgnoresCopiesAndReturnsEmpty() async {
        let stack = ClipboardStack()

        let didEnqueue = await stack.enqueue(item("A"))
        let dequeued = await stack.dequeue()
        let state = await stack.state()
        XCTAssertFalse(didEnqueue)
        XCTAssertNil(dequeued)
        XCTAssertEqual(state, .init(isEnabled: false, count: 0))
    }

    func testEnabledStackDequeuesInFIFOOrderIncludingDuplicates() async {
        let stack = ClipboardStack()
        _ = await stack.setEnabled(true)

        let enqueuedA = await stack.enqueue(item("A"))
        let enqueuedB = await stack.enqueue(item("B"))
        let enqueuedDuplicateA = await stack.enqueue(item("A"))
        let first = await stack.dequeue()
        let second = await stack.dequeue()
        let third = await stack.dequeue()
        let empty = await stack.dequeue()

        XCTAssertTrue(enqueuedA)
        XCTAssertTrue(enqueuedB)
        XCTAssertTrue(enqueuedDuplicateA)
        XCTAssertEqual(first?.plainText, "A")
        XCTAssertEqual(second?.plainText, "B")
        XCTAssertEqual(third?.plainText, "A")
        XCTAssertNil(empty)
    }

    func testDisablingClearsQueueBeforeNextSession() async {
        let stack = ClipboardStack()
        _ = await stack.setEnabled(true)
        _ = await stack.enqueue(item("old"))

        let disabled = await stack.toggle()
        let reenabled = await stack.toggle()
        let dequeued = await stack.dequeue()
        XCTAssertEqual(disabled, .init(isEnabled: false, count: 0))
        XCTAssertEqual(reenabled, .init(isEnabled: true, count: 0))
        XCTAssertNil(dequeued)
    }

    private func item(_ text: String) -> ClipItem {
        ClipItem(kind: .text, plainText: text, contentHash: text)
    }
}
