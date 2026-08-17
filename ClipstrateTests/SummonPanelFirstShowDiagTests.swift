import AppKit
import SwiftUI
import XCTest
@testable import Clipstrate

/// 「冷启动后第一次唤出很卡，之后丝滑」诊断（2026-08-17）。**报告型用例，不做硬断言。**
///
/// 假设：`PanelController.init` 里那句「预热：先离屏渲染一次」并没有渲染——
/// `panel.orderOut(nil)` 对一个从未 order-in 过的窗口是空操作，NSHostingView 只是被
/// 挂上去，SwiftUI 视图树从未 layout、CALayer 树从未建、玻璃材质从未合成。所有这些
/// 进程级一次性成本（SwiftUI AttributeGraph 启动、字体、Liquid Glass 的 Metal 管线）
/// 全部落在**用户按下 ⌥V 的那一次** `orderFrontRegardless()` 上。
///
/// 量法：同一进程内连开两块内容相同的面板。第一块承担「进程级一次性 + 实例级」成本，
/// 第二块只剩「实例级」。差值就是「第一次卡、第二次丝滑」的那部分——也正是可以在启动时
/// 预付掉的部分。
///
/// 注意：本用例必须**单独跑**才准（其他 UI 用例会先把进程级成本付掉）：
///   xcodebuild -scheme Clipstrate test \
///     -only-testing:ClipstrateTests/SummonPanelFirstShowDiagTests
@MainActor
final class SummonPanelFirstShowDiagTests: XCTestCase {
    private var panels: [SummonPanel] = []

    override func tearDown() async throws {
        for panel in panels { panel.orderOut(nil) }
        panels = []
    }

    // MARK: - 夹具

    private func makeItems(_ count: Int) -> [ClipItem] {
        (0..<count).map { index in
            ClipItem(
                kind: .text,
                plainText: "条目 \(index) 的示例文本，用来占据卡片正文若干行。",
                contentHash: "first-show-hash-\(index)",
                appName: "DiagApp"
            )
        }
    }

    /// 只建窗口 + 挂 hosting view，**不显示**——复刻生产 `PanelController.init` 的现状。
    private func makeHiddenPanel(itemCount: Int) -> (SummonPanel, SummonPanelModel) {
        let model = SummonPanelModel(historyStore: nil, initialItems: makeItems(itemCount))
        let size = SummonPanelLayout.panelSize(
            itemCount: itemCount,
            availableWidth: NSScreen.main?.visibleFrame.width ?? 1512
        )
        let panel = SummonPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.contentView = NSHostingView(rootView: SummonPanelView(model: model))
        panel.orderOut(nil)                         // 生产里的「预热」，实为空操作
        panels.append(panel)
        return (panel, model)
    }

    /// 把面板摆到主屏中下部——与生产的 caret 锚点同区域（玻璃背景采样量相当）。
    private func place(_ panel: SummonPanel) {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        panel.setFrame(
            NSRect(x: visible.midX - panel.frame.width / 2,
                   y: visible.minY + 80,
                   width: panel.frame.width,
                   height: panel.frame.height),
            display: false
        )
    }

    /// 同步逼出第一帧：orderFront 之后强制 layout + display + 提交事务。
    /// 不 pump RunLoop——那会把等待时间也算进来，这里只要主线程被占住的那段。
    @discardableResult
    private func presentAndFlush(_ panel: SummonPanel) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        CATransaction.flush()
        return (CFAbsoluteTimeGetCurrent() - start) * 1000
    }

    private func milliseconds(_ body: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        body()
        return (CFAbsoluteTimeGetCurrent() - start) * 1000
    }

    private struct Run {
        let label: String
        let build: Double        // NSHostingView 构造 + 挂到 contentView
        let present: Double      // orderFront → 第一帧提交
        var total: Double { build + present }
    }

    private func report(_ runs: [Run]) {
        print("[DEBUG-firstshow] ───────────────────────────────────────────")
        for run in runs {
            print(String(format: "[DEBUG-firstshow] %@  建树 %6.1fms  出帧 %6.1fms  合计 %6.1fms",
                         run.label, run.build, run.present, run.total))
        }
        print("[DEBUG-firstshow] ───────────────────────────────────────────")
    }

    // MARK: - 用例

    /// 第一块面板 vs 第二块面板：差值 = 进程级一次性成本 = 「第一次唤出卡」的量。
    func testFirstPanelPresentationCostVersusSecond() {
        var runs: [Run] = []
        var first: Run!
        var second: Run!

        for (index, label) in ["①首块（含进程级一次性）", "②次块（纯实例级）"].enumerated() {
            var panel: SummonPanel!
            let build = milliseconds { (panel, _) = self.makeHiddenPanel(itemCount: 12) }
            place(panel)
            let present = presentAndFlush(panel)
            panel.orderOut(nil)
            let run = Run(label: label, build: build, present: present)
            runs.append(run)
            if index == 0 { first = run } else { second = run }
        }

        report(runs)
        let oneOff = first.total - second.total
        print(String(format: "[DEBUG-firstshow] 进程级一次性成本 ≈ %.1fms（可在启动时预付）", oneOff))
        XCTAssertGreaterThan(first.total, 0)
    }

    /// 生产稳态：同一块面板 orderOut 之后再 orderFront，就是「后面比较丝滑」的那次。
    func testWarmPanelRepeatedPresentationIsCheap() {
        let (panel, _) = makeHiddenPanel(itemCount: 12)
        place(panel)

        var costs: [Double] = []
        for _ in 0..<5 {
            costs.append(presentAndFlush(panel))
            panel.orderOut(nil)
        }
        let formatted = costs.map { String(format: "%.1f", $0) }.joined(separator: " / ")
        print("[DEBUG-firstshow] 同一面板连续 5 次出帧(ms)：\(formatted)")
        XCTAssertEqual(costs.count, 5)
    }

    /// 候选修复验证：启动时把面板真的 order-in 一帧（离屏、alpha 0）再 orderOut，
    /// 之后那次「用户唤出」还剩多少。与 ①/② 对比即知预热是否把一次性成本吃掉了。
    func testOffscreenPrewarmMovesTheCostOffTheSummonPath() {
        // 先建一块并真显示，模拟「启动时已预热过」把进程级成本付掉。
        let (warmup, _) = makeHiddenPanel(itemCount: 12)
        warmup.alphaValue = 0
        warmup.setFrame(NSRect(x: -10_000, y: -10_000,
                               width: warmup.frame.width, height: warmup.frame.height),
                        display: false)
        let prewarmCost = presentAndFlush(warmup)
        warmup.orderOut(nil)
        warmup.alphaValue = 1
        print(String(format: "[DEBUG-firstshow] 启动期离屏预热耗时 %.1fms（不在用户感知路径上）", prewarmCost))

        // 之后用户唤出：同一块面板，只是挪到屏内并显示。
        place(warmup)
        let summon = presentAndFlush(warmup)
        warmup.orderOut(nil)
        print(String(format: "[DEBUG-firstshow] 预热后首次「唤出」出帧 %.1fms", summon))
        XCTAssertGreaterThan(prewarmCost, 0)
    }

    /// 修复回归：真 `PanelController` 启动后会自己把预热帧渲染掉（首批快照落地之后），
    /// 用户唤出时不再承担首帧成本。
    func testPanelControllerRendersPrewarmFrameAfterSnapshotLands() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("first-show-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try HistoryStore(path: dir.appendingPathComponent("history.sqlite").path)
        for item in makeItems(6) { _ = try await store.upsert(item) }

        let controller = PanelController(historyStore: store, chopOverlayBuilder: nil)
        XCTAssertFalse(controller.isPrewarmed, "init 同步阶段不渲染——要等首批快照落地")

        for _ in 0..<200 where !controller.isPrewarmed {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(controller.isPrewarmed, "首批快照落地后应已渲染过预热帧")
        XCTAssertFalse(controller.isVisible, "预热帧渲染完必须收起，用户看不到")
        controller.tearDown()
    }

    /// `PanelController.show()` 在主线程同步调 `SelectionGrabber.caretRect()`（3 次跨进程
    /// AX IPC，默认消息超时 6s，未设 AXUIElementSetMessagingTimeout）。首次对某个 App 建立
    /// AX 连接明显更贵——这也是「第一次慢」的候选来源。无 AX 权限时本用例只报告不测。
    func testCaretRectFirstCallCost() {
        guard AXPermission.isTrusted else {
            print("[DEBUG-firstshow] 无 AX 权限，caretRect 直接返回 nil，跳过测量")
            return
        }
        var costs: [Double] = []
        for _ in 0..<5 {
            costs.append(milliseconds { _ = SelectionGrabber.caretRect() })
        }
        let formatted = costs.map { String(format: "%.1f", $0) }.joined(separator: " / ")
        print("[DEBUG-firstshow] caretRect 连续 5 次(ms)：\(formatted)")
        XCTAssertEqual(costs.count, 5)
    }
}
