import XCTest
@testable import Clipstrate

/// T0.1 冒烟测试：设置基线默认值与枚举取值域。
final class SettingsTests: XCTestCase {
    /// 基线默认值只应反映“注册域默认”。先清掉这些键在 standard 持久域可能的残留，
    /// 避免其他用例（向 UserDefaults.standard 写入且顺序在前）污染本用例。
    private static let baselineKeys = [
        SettingsKey.launchAtLogin, SettingsKey.plainTextDefault, SettingsKey.diskCapMB,
        SettingsKey.retention, SettingsKey.digitModifier, SettingsKey.pressAction,
        SettingsKey.returnAction, SettingsKey.panelStyle, SettingsKey.backupAutoICloud,
        SettingsKey.backupIncludeHistory,
    ]

    override func setUp() {
        super.setUp()
        for key in Self.baselineKeys { UserDefaults.standard.removeObject(forKey: key) }
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
        XCTAssertTrue(Settings.backupAutoICloud, "iCloud 自动备份默认开启")
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
