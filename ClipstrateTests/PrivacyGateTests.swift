import XCTest
import AppKit
@testable import Clipstrate

final class PrivacyGateTests: XCTestCase {
    func testAccessBehaviorMapping() {
        XCTAssertEqual(PrivacyGate.map(.alwaysAllow), .allowed)
        XCTAssertEqual(PrivacyGate.map(.alwaysDeny), .denied)
        XCTAssertEqual(PrivacyGate.map(.ask), .ask)
        XCTAssertEqual(PrivacyGate.map(.default), .ask)
    }
}
