import XCTest
@testable import Clipstrate

/// 波浪放大（「完整特效」，01 §3.2）的纯函数与状态机测试。
/// 参数拍板记录：prototype/wave-magnify.html（幅度 1.08 / 半径 220 / 余弦 / 选中卡不参与）。
@MainActor
final class WaveMagnifyTests: XCTestCase {
    // MARK: - 衰减曲线

    func testScaleAtCursorIsMax() {
        XCTAssertEqual(WaveMagnify.scale(distance: 0, gain: 1), WaveMagnify.maxScale, accuracy: 1e-9)
    }

    func testScaleBeyondRadiusIsIdentity() {
        XCTAssertEqual(WaveMagnify.scale(distance: WaveMagnify.radius, gain: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(WaveMagnify.scale(distance: WaveMagnify.radius * 3, gain: 1), 1, accuracy: 1e-9)
    }

    func testScaleIsSymmetricAndMonotonicallyDecaying() {
        var previous = WaveMagnify.scale(distance: 0, gain: 1)
        for step in 1...20 {
            let d = WaveMagnify.radius * CGFloat(step) / 20
            let scale = WaveMagnify.scale(distance: d, gain: 1)
            XCTAssertEqual(scale, WaveMagnify.scale(distance: -d, gain: 1), accuracy: 1e-9, "对称性 d=\(d)")
            XCTAssertLessThanOrEqual(scale, previous, "单调衰减 d=\(d)")
            previous = scale
        }
    }

    func testGainScalesAmplitudeLinearly() {
        let full = WaveMagnify.scale(distance: 0, gain: 1) - 1
        let half = WaveMagnify.scale(distance: 0, gain: 0.5) - 1
        XCTAssertEqual(half, full / 2, accuracy: 1e-9)
        XCTAssertEqual(WaveMagnify.scale(distance: 0, gain: 0), 1)
    }

    /// 幅度约束（01 §3.2 / 调研结论 2）：未选中卡放大后不越出裁剪边界，
    /// 且明显小于选中态放大避免语义混淆。
    func testMaxScaleRespectsClipHeadroomAndSelectionSemantics() {
        let grownHeight = DS.Metrics.cardUnselected.height * WaveMagnify.maxScale
        let clipCeiling = DS.Metrics.cardSelected.height + SummonPanelLayout.shadowPadding
        XCTAssertLessThanOrEqual(grownHeight, clipCeiling, "波浪放大越出 ScrollView 裁剪边界")

        let selectionGrowth = DS.Metrics.cardSelected.width / DS.Metrics.cardUnselected.width
        XCTAssertLessThan(WaveMagnify.maxScale, selectionGrowth * 0.6,
                          "波浪幅度须明显小于选中态放大（约 \(selectionGrowth)×）")
        XCTAssertLessThanOrEqual(WaveMagnify.maxScale, 1.08, "拍板上限 1.08×")
    }

    // MARK: - 状态机

    func testDisabledStateIgnoresPointer() {
        let wave = WaveMagnifyState()
        wave.preparePresentation(enabled: false)
        wave.pointerMoved(to: 300)
        XCTAssertNil(wave.pointerX)
        XCTAssertEqual(wave.gain, 0)
    }

    func testEnabledStateTracksPointerAndFades() {
        let wave = WaveMagnifyState()
        wave.preparePresentation(enabled: true)
        wave.pointerMoved(to: 300)
        XCTAssertEqual(wave.pointerX, 300)
        XCTAssertEqual(wave.gain, 1)
        wave.pointerExited()
        XCTAssertEqual(wave.gain, 0)
    }

    func testPreparePresentationResetsStalePointer() {
        let wave = WaveMagnifyState()
        wave.preparePresentation(enabled: true)
        wave.pointerMoved(to: 300)
        wave.preparePresentation(enabled: true)
        XCTAssertNil(wave.pointerX, "上次唤出的指针位置不得泄漏到本次")
        XCTAssertEqual(wave.gain, 0)
    }

    // MARK: - 设置

    func testFullEffectsDefaultsOnAndSurvivesBackupRoundTrip() {
        Settings.registerDefaults()
        let store = UserDefaults.standard
        let original = store.object(forKey: SettingsKey.fullEffects)
        defer {
            if let original {
                store.set(original, forKey: SettingsKey.fullEffects)
            } else {
                store.removeObject(forKey: SettingsKey.fullEffects)
            }
        }

        store.removeObject(forKey: SettingsKey.fullEffects)
        XCTAssertTrue(Settings.fullEffects, "注册默认值应为开")

        store.set(false, forKey: SettingsKey.fullEffects)
        let document = Settings.makeBackupDocument()
        XCTAssertEqual(document.booleans[SettingsKey.fullEffects], false, "应包含在备份文档中")

        store.set(true, forKey: SettingsKey.fullEffects)
        try? Settings.restore(from: document)
        XCTAssertFalse(Settings.fullEffects, "恢复备份应还原该开关")
    }
}
