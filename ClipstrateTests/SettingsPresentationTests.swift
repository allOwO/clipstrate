import XCTest
@testable import Clipstrate

final class SettingsPresentationTests: XCTestCase {
    func testSectionOrderAndTitlesMatchSpecification() {
        XCTAssertEqual(
            SettingsSection.allCases.map(\.title),
            ["通用", "快捷键", "交互", "显示", "历史与存储", "数据备份", "权限", "关于"]
        )
    }

    func testScrollSpyTracksThresholdAndForcesAboutAtBottom() {
        let offsets: [SettingsSection: CGFloat] = [
            .general: -600,
            .shortcuts: -240,
            .interaction: 42,
            .display: 320,
        ]

        XCTAssertEqual(SettingsScrollSpy.section(offsets: offsets, isAtBottom: false), .interaction)
        XCTAssertEqual(SettingsScrollSpy.section(offsets: offsets, isAtBottom: true), .about)
    }

    func testProgrammaticScrollKeepsRequestedSelectionUntilTargetSettles() {
        let transient = SettingsScrollSpy.synchronize(
            programmaticTarget: .shortcuts,
            observed: .general
        )
        XCTAssertEqual(transient.section, .shortcuts)
        XCTAssertEqual(transient.pendingTarget, .shortcuts)

        let settled = SettingsScrollSpy.synchronize(
            programmaticTarget: transient.pendingTarget,
            observed: .shortcuts
        )
        XCTAssertEqual(settled.section, .shortcuts)
        XCTAssertNil(settled.pendingTarget)

        let manualScroll = SettingsScrollSpy.synchronize(
            programmaticTarget: nil,
            observed: .interaction
        )
        XCTAssertEqual(manualScroll.section, .interaction)
        XCTAssertNil(manualScroll.pendingTarget)
    }

    func testSettingsCatalogCoversEveryWindowUserDefaultsKey() {
        XCTAssertEqual(SettingsCatalog.windowKeys.count, 14)
        XCTAssertEqual(Set(SettingsCatalog.windowKeys).count, SettingsCatalog.windowKeys.count)
        XCTAssertTrue(SettingsCatalog.windowKeys.contains(SettingsKey.launchAtLogin))
        XCTAssertTrue(SettingsCatalog.windowKeys.contains(SettingsKey.retention))
        XCTAssertTrue(SettingsCatalog.windowKeys.contains(SettingsKey.backupLastUploadAt))
        XCTAssertFalse(SettingsCatalog.windowKeys.contains(SettingsKey.onboardingDone))
        XCTAssertFalse(SettingsCatalog.windowKeys.contains("interaction.autoClose"))
    }

    func testLoginItemStateReflectsRegistrationAndApproval() {
        XCTAssertFalse(LoginItemState.disabled.isSelected)
        XCTAssertTrue(LoginItemState.enabled.isSelected)
        XCTAssertTrue(LoginItemState.requiresApproval.isSelected)
        XCTAssertFalse(LoginItemState.unavailable.isSelected)
        XCTAssertNil(LoginItemState.enabled.notice)
        XCTAssertNotNil(LoginItemState.requiresApproval.notice)
        XCTAssertNotNil(LoginItemState.unavailable.notice)
    }

    func testStorageOptionsMatchSpecification() {
        XCTAssertEqual(SettingsCatalog.defaultWindowSize, CGSize(width: 780, height: 560))
        XCTAssertEqual(SettingsCatalog.diskCapsMB, [256, 512, 1_024, 2_048])
        XCTAssertEqual(
            SettingsCatalog.retentions.map(\.settingsLabel),
            ["天", "周", "月", "季度", "半年", "年", "无限制"]
        )
    }

    func testSettingEnumLabelsMatchControls() {
        XCTAssertEqual(DigitModifier.allCases.map(\.settingsLabel), ["暂无", "⌘ + 1~9", "⌥ + 1~9"])
        XCTAssertEqual(ClickAction.allCases.map(\.settingsLabel), ["输入剪贴板内容", "仅复制"])
    }
}
