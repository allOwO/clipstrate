import XCTest
@testable import Clipstrate

final class SummonKeyMapTests: XCTestCase {
    private func cmd(_ keyCode: UInt16, option: Bool = false, command: Bool = false,
                     modifier: DigitModifier = .none) -> SummonPanelCommand? {
        SummonKeyMap.command(keyCode: keyCode, option: option, command: command, digitModifier: modifier)
    }

    func testNavigationAndControlKeys() {
        XCTAssertEqual(cmd(123), .moveLeft)
        XCTAssertEqual(cmd(124), .moveRight)
        XCTAssertEqual(cmd(125), .moveDown)
        XCTAssertEqual(cmd(126), .moveUp)
        XCTAssertEqual(cmd(48), .openChop)
        XCTAssertEqual(cmd(53), .escape)
    }

    func testEnterPlainTextVariant() {
        XCTAssertEqual(cmd(36), .activate)
        XCTAssertEqual(cmd(76), .activate)
        XCTAssertEqual(cmd(36, option: true), .activatePlainText)
    }

    func testDigitModifierNoneUsesBareDigits() {
        XCTAssertEqual(cmd(18, modifier: .none), .digit(1))
        XCTAssertEqual(cmd(25, modifier: .none), .digit(9))
        // 带修饰键时不触发，避免与系统/其他快捷键冲突
        XCTAssertNil(cmd(18, option: true, modifier: .none))
        XCTAssertNil(cmd(18, command: true, modifier: .none))
    }

    func testDigitModifierCmdRequiresCommand() {
        XCTAssertNil(cmd(19, modifier: .cmd))
        XCTAssertEqual(cmd(19, command: true, modifier: .cmd), .digit(2))
        XCTAssertNil(cmd(19, option: true, command: true, modifier: .cmd))
    }

    func testDigitModifierOptRequiresOption() {
        XCTAssertNil(cmd(20, modifier: .opt))
        XCTAssertEqual(cmd(20, option: true, modifier: .opt), .digit(3))
    }

    func testZeroKeyAndUnknownAreNil() {
        XCTAssertNil(cmd(29), "0 键不参与 1–9 直贴")
        XCTAssertNil(cmd(200))
    }
}
