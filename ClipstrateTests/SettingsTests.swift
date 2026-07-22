import XCTest
@testable import Clipstrate

/// T0.1 冒烟测试：设置基线默认值与枚举取值域。
final class SettingsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Settings.registerDefaults()
    }

    func testBaselineDefaultsMatchSpecTable() {
        // 02 §5 默认值表
        XCTAssertTrue(Settings.launchAtLogin)
        XCTAssertTrue(Settings.menuBarIconVisible)
        XCTAssertFalse(Settings.soundEnabled)
        XCTAssertTrue(Settings.autoClose)
        XCTAssertFalse(Settings.plainTextDefault)
        XCTAssertEqual(Settings.diskCapMB, 512)
        XCTAssertEqual(Settings.retention, .month)
        XCTAssertEqual(Settings.digitModifier, .none)
        XCTAssertEqual(Settings.pressAction, .paste)
        XCTAssertEqual(Settings.returnAction, .paste)
        XCTAssertEqual(Settings.panelStyle, .glass)
        XCTAssertFalse(Settings.backupAutoICloud)
        XCTAssertTrue(Settings.backupIncludeHistory)
    }

    func testEnumRawValueRoundTrip() {
        XCTAssertEqual(Retention(rawValue: "unlimited"), .unlimited)
        XCTAssertEqual(ClickAction(rawValue: "copy"), .copy)
        XCTAssertEqual(PanelStyle(rawValue: "compat"), .compat)
        XCTAssertEqual(DigitModifier(rawValue: "cmd"), .cmd)
        XCTAssertNil(Retention(rawValue: "century"))
    }

    func testUnknownStoredValueFallsBackToSpecDefault() {
        UserDefaults.standard.set("bogus", forKey: SettingsKey.retention)
        defer { UserDefaults.standard.removeObject(forKey: SettingsKey.retention) }
        XCTAssertEqual(Settings.retention, .month)
    }
}
