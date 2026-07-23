import XCTest
@testable import Clipstrate

@MainActor
final class EntityHUDModelTests: XCTestCase {
    func testPresentPublishesPayloadAndPresentation() {
        let model = EntityHUDModel(dismissDelay: .seconds(30))
        var presentationCount = 0
        model.onPresent = { presentationCount += 1 }

        model.present(item: makeItem("验证码 123456"), entities: [makeEntity("123456")])

        XCTAssertEqual(model.payload?.text, "验证码 123456")
        XCTAssertEqual(model.payload?.entities.count, 1)
        XCTAssertEqual(presentationCount, 1)
    }

    func testEmptyEntitiesDismissExistingPayload() {
        let model = EntityHUDModel(dismissDelay: .seconds(30))
        model.present(item: makeItem("验证码 123456"), entities: [makeEntity("123456")])

        model.present(item: makeItem("普通文本"), entities: [])

        XCTAssertNil(model.payload)
    }

    func testClickOrHotkeyExpandsCurrentPayloadThenDismisses() {
        let model = EntityHUDModel(dismissDelay: .seconds(30))
        var expanded: EntityHUDPayload?
        var dismissCount = 0
        model.onExpand = { expanded = $0 }
        model.onDismiss = { dismissCount += 1 }
        model.present(item: makeItem("code 654321"), entities: [makeEntity("654321")])

        XCTAssertTrue(model.expandIfPresent())

        XCTAssertEqual(expanded?.text, "code 654321")
        XCTAssertNil(model.payload)
        XCTAssertEqual(dismissCount, 1)
        XCTAssertFalse(model.expandIfPresent())
    }

    func testAutomaticallyDismissesAfterConfiguredDelay() async {
        let model = EntityHUDModel(dismissDelay: .milliseconds(10))
        model.present(item: makeItem("code 112233"), entities: [makeEntity("112233")])

        try? await Task.sleep(for: .milliseconds(40))

        XCTAssertNil(model.payload)
    }

    func testSecondPresentationCancelsFirstDismissal() async {
        let model = EntityHUDModel(dismissDelay: .milliseconds(40))
        model.present(item: makeItem("code 111111"), entities: [makeEntity("111111")])
        try? await Task.sleep(for: .milliseconds(25))

        model.present(item: makeItem("code 222222"), entities: [makeEntity("222222")])
        try? await Task.sleep(for: .milliseconds(25))

        XCTAssertEqual(model.payload?.text, "code 222222")
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(model.payload)
    }

    private func makeEntity(_ value: String) -> DetectedEntity {
        DetectedEntity(
            kind: .verificationCode,
            value: value,
            sourceRange: NSRange(location: 0, length: value.utf16.count),
            icon: "key.fill",
            priority: 500
        )
    }

    private func makeItem(_ text: String) -> ClipItem {
        ClipItem(
            kind: .text,
            plainText: text,
            contentHash: "hash-\(text)",
            byteSize: text.utf8.count
        )
    }
}
