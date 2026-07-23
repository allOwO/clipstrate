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
        XCTAssertFalse(Settings.plainTextDefault)
        XCTAssertEqual(Settings.diskCapMB, 512)
        XCTAssertEqual(Settings.retention, .month)
        XCTAssertEqual(Settings.digitModifier, .cmd)
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

    func testRegisteredDefaultDoesNotCountAsPersistedLaunchPreference() {
        XCTAssertFalse(Settings.hasLaunchAtLoginPreference(in: nil))
        XCTAssertFalse(Settings.hasLaunchAtLoginPreference(in: [:]))
        XCTAssertTrue(
            Settings.hasLaunchAtLoginPreference(
                in: [SettingsKey.launchAtLogin: false]
            )
        )
    }

    func testBackupRestoreRejectsUnknownKeysAndInvalidValues() throws {
        let defaults = UserDefaults.standard
        let unknownKey = "backup.test.unknown"
        let originalDiskCap = defaults.object(forKey: SettingsKey.diskCapMB)
        let originalPanelItemCount = defaults.object(forKey: SettingsKey.panelItemCount)
        let originalModifier = defaults.object(forKey: SettingsKey.digitModifier)
        defer {
            defaults.removeObject(forKey: unknownKey)
            if let originalDiskCap {
                defaults.set(originalDiskCap, forKey: SettingsKey.diskCapMB)
            } else {
                defaults.removeObject(forKey: SettingsKey.diskCapMB)
            }
            if let originalPanelItemCount {
                defaults.set(originalPanelItemCount, forKey: SettingsKey.panelItemCount)
            } else {
                defaults.removeObject(forKey: SettingsKey.panelItemCount)
            }
            if let originalModifier {
                defaults.set(originalModifier, forKey: SettingsKey.digitModifier)
            } else {
                defaults.removeObject(forKey: SettingsKey.digitModifier)
            }
        }

        try Settings.restore(
            from: SettingsBackupDocument(
                booleans: [unknownKey: true],
                integers: [
                    SettingsKey.diskCapMB: 999,
                    SettingsKey.panelItemCount: 999,
                ],
                strings: [SettingsKey.digitModifier: "invalid"]
            )
        )

        XCTAssertNil(defaults.object(forKey: unknownKey))
        XCTAssertNotEqual(Settings.diskCapMB, 999)
        XCTAssertNotEqual(Settings.panelItemCount, 999)
        XCTAssertNotEqual(defaults.string(forKey: SettingsKey.digitModifier), "invalid")
    }
}
