import AppKit
import SwiftUI
import XCTest
@testable import Clipstrate

/// 卡片条双指滚动回归（由 2026-07 滚动冻结诊断沉淀，机制结论见各用例注释与提交记录）。
/// 把真实 SummonPanelView 装进真实 SummonPanel，合成带 gesture/momentum phase 的
/// 连续滚动 NSEvent 流，按 AppKit 手势锁定语义投递，读 NSClipView 断言滚动推进。
///
/// 覆盖两类已确认的系统缺陷及其工作区：
///   - 滚动事件坐标损坏 → 事件被窗口丢弃、拖动冻结（ScrollEventRescue 修复）；
///   - 零 changed 轻扫的惯性列被 SwiftUI 丢弃（MomentumScrollAssist 修复）。
@MainActor
final class SummonPanelScrollDiagTests: XCTestCase {
    // MARK: - 夹具

    private var panel: SummonPanel!
    private var model: SummonPanelModel!
    private var scrollView: NSScrollView!
    private var clip: NSClipView!
    private var doc: NSView!
    private var gestureTarget: NSView!
    private var globalLocation: CGPoint = .zero
    /// 与生产环境同款的惯性救援（生产走 App 级 monitor，harness 在 send() 里镜像其语义）。
    private var assist: MomentumScrollAssist!

    private func makeItems(_ count: Int) -> [ClipItem] {
        (0..<count).map { index in
            ClipItem(
                kind: .text,
                plainText: "条目 \(index) 的示例文本，用来占据卡片正文若干行。",
                contentHash: "diag-hash-\(index)",
                appName: "DiagApp"
            )
        }
    }

    private func setUpPanel(itemCount: Int = 50, panelWidth: CGFloat = 1_000) throws {
        model = SummonPanelModel(historyStore: nil, initialItems: makeItems(itemCount))
        try setUpPanel(rootView: AnyView(SummonPanelView(model: model)), panelWidth: panelWidth) {
            self.model.beginPresentation()
        }
    }

    private func setUpPanel(
        rootView: AnyView,
        panelWidth: CGFloat = 1_000,
        afterMount: () -> Void = {}
    ) throws {
        assist = MomentumScrollAssist()
        panel = SummonPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: SummonPanelLayout.normalPanelHeight),
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
        panel.contentView = NSHostingView(rootView: rootView)
        afterMount()
        panel.setFrame(
            NSRect(x: 40, y: 60, width: panelWidth, height: SummonPanelLayout.normalPanelHeight),
            display: true
        )
        panel.orderFrontRegardless()
        pump(0.6)

        let content = try XCTUnwrap(panel.contentView)
        scrollView = try XCTUnwrap(findViews(in: content) { $0 is NSScrollView }.first as? NSScrollView)
        clip = scrollView.contentView
        doc = try XCTUnwrap(scrollView.documentView)

        let midInWindow = scrollView.convert(
            CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY), to: nil
        )
        let midOnScreen = panel.convertPoint(toScreen: midInWindow)
        let screenHeight = NSScreen.screens.first?.frame.height ?? 1_000
        globalLocation = CGPoint(x: midOnScreen.x, y: screenHeight - midOnScreen.y)

        let hitPoint = content.convert(midInWindow, from: nil)
        gestureTarget = content.hitTest(content.convert(hitPoint, to: content.superview)) ?? content
    }

    override func tearDown() async throws {
        panel?.orderOut(nil)
        panel = nil
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func findViews(in root: NSView, where predicate: (NSView) -> Bool) -> [NSView] {
        var result: [NSView] = []
        if predicate(root) { result.append(root) }
        for sub in root.subviews {
            result.append(contentsOf: findViews(in: sub, where: predicate))
        }
        return result
    }

    // MARK: - 事件引擎

    /// CG 原始值：scrollPhase mayBegin=128 began=1 changed=2 ended=4 cancelled=8 none=0；
    /// momentumPhase begin=1 continue=2 end=3 none=0。
    private func send(deltaX: Int32, deltaY: Int32 = 0, scrollPhase: Int64, momentumPhase: Int64) {
        guard let cg = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else { return }
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        cg.location = globalLocation
        guard let event = NSEvent(cgEvent: cg) else { return }
        // 镜像 App 级 monitor 的分发语义：惯性救援未消费的事件才直投视图。
        if !assist.handle(event, in: panel) {
            gestureTarget.scrollWheel(with: event)
        }
        pump(0.003)
    }

    private var offsetX: CGFloat { clip.bounds.origin.x }
    private var maxOffset: CGFloat { doc.frame.width - clip.bounds.width }

    /// 一轮手势（可带 mayBegin 前缀、纵向分量、惯性段），返回逐事件 offset 轨迹。
    @discardableResult
    private func performGesture(
        deltas: [Int32],
        deltaYRatio: Double = 0,
        mayBegin: Bool = false,
        momentumDeltas: [Int32] = []
    ) -> [CGFloat] {
        var trace: [CGFloat] = []
        func record() { trace.append(offsetX) }
        if mayBegin { send(deltaX: 0, scrollPhase: 128, momentumPhase: 0); record() }
        send(deltaX: 0, scrollPhase: 1, momentumPhase: 0); record()
        for delta in deltas {
            send(deltaX: delta, deltaY: Int32(Double(delta) * deltaYRatio), scrollPhase: 2, momentumPhase: 0)
            record()
        }
        send(deltaX: 0, scrollPhase: 4, momentumPhase: 0); record()
        if !momentumDeltas.isEmpty {
            send(deltaX: momentumDeltas[0], scrollPhase: 0, momentumPhase: 1); record()
            for delta in momentumDeltas.dropFirst() {
                send(deltaX: delta, deltaY: Int32(Double(delta) * deltaYRatio), scrollPhase: 0, momentumPhase: 2)
                record()
            }
            send(deltaX: 0, scrollPhase: 0, momentumPhase: 3); record()
        }
        return trace
    }

    /// 反复整轮手势直到到底 / 卡住；返回卡住位置（nil = 顺利到底）。
    private func scrollToEnd(
        rounds: Int = 60,
        gesture: () -> [CGFloat]
    ) -> CGFloat? {
        for round in 0..<rounds {
            let before = offsetX
            if before >= maxOffset - 1 { return nil }
            let trace = gesture()
            let after = offsetX
            print("[DEBUG-scrl] round=\(round) off \(before) -> \(after) docWidth=\(doc.frame.width)")
            if after - before < 1 {
                print("[DEBUG-scrl] 卡住轮逐事件轨迹: \(trace.map { "\($0)" }.joined(separator: ","))")
                return after
            }
        }
        return offsetX >= maxOffset - 1 ? nil : offsetX
    }

    private func assertReachesEnd(_ stalledAt: CGFloat?, _ label: String) {
        XCTAssertNil(stalledAt, "[DEBUG-scrl] \(label)：滚动在 offset=\(stalledAt ?? -1)（max=\(maxOffset)）处卡住")
        XCTAssertGreaterThanOrEqual(offsetX, maxOffset - 1, "[DEBUG-scrl] \(label)：未能滚到底")
    }

    // MARK: - 场景

    /// 1. 基线：纯 changed 手势流（首轮已验证绿，保留做回归锚点）。
    func testPlainGestureScrollReachesEnd() throws {
        try setUpPanel()
        let stalled = scrollToEnd { performGesture(deltas: Array(repeating: -40, count: 20)) }
        assertReachesEnd(stalled, "纯手势")
    }

    /// 2. 真实触摸板节奏：mayBegin 前缀 + 手势段 + 惯性衰减段。
    func testMomentumScrollReachesEnd() throws {
        try setUpPanel()
        // 惯性段：从 -60 逐步衰减到 -2，模拟系统动量曲线。
        let momentum: [Int32] = stride(from: -60, through: -2, by: 4).map { Int32($0) }
        let stalled = scrollToEnd {
            performGesture(
                deltas: Array(repeating: -30, count: 8),
                mayBegin: true,
                momentumDeltas: momentum
            )
        }
        assertReachesEnd(stalled, "惯性滚动")
    }

    /// 3. 斜向滑动：横向为主 + 30% 纵向分量（真实双指几乎必带纵向抖动）。
    func testDiagonalGestureScrollReachesEnd() throws {
        try setUpPanel()
        let stalled = scrollToEnd {
            performGesture(deltas: Array(repeating: -40, count: 20), deltaYRatio: 0.3)
        }
        assertReachesEnd(stalled, "斜向手势")
    }

    /// 8. 快速轻扫（真机取证 17:04:49 seg13 的精确模式）：手指接住惯性后立即轻扫离板，
    ///    手势段只有 began(带 delta)→ended、零个 changed，随后系统补发整列衰减惯性。
    ///    真机表现：惯性列全部到达但几何冻结——本测试在进程内复刻该事件序列。
    func testQuickFlickMomentumApplies() throws {
        try setUpPanel()
        try assertQuickFlickGlides("SummonPanelView")
    }

    /// 8b/8c. 同一轻扫打在对照条上：区分框架级行为 vs 本视图成分。
    func testQuickFlickOnLazyControlStrip() throws {
        try setUpPanel(rootView: AnyView(PlainDiagStrip(lazy: true)))
        try assertQuickFlickGlides("LazyHStack对照")
    }

    func testQuickFlickOnEagerControlStrip() throws {
        try setUpPanel(rootView: AnyView(PlainDiagStrip(lazy: false)))
        try assertQuickFlickGlides("急切HStack对照")
    }

    /// catch-flick：mayBegin → began(dx=-14) → ended（零 changed）→ 惯性列 Σ≈-139。
    /// 真机取证显示该模式下整列惯性被丢弃；本断言在惯性应用率 <50% 时红。
    private func assertQuickFlickGlides(_ label: String) throws {
        // 先正常滚到中段，避免边缘橡皮筋干扰。
        performGesture(deltas: Array(repeating: -40, count: 10))
        let start = offsetX
        XCTAssertGreaterThan(start, 100, "[DEBUG-scrl] \(label)：前置滚动未生效，harness 异常")

        let momentum: [Int32] = [-7, -7, -7, -6, -6, -5, -5, -5, -5, -4, -4, -4, -4, -4,
                                 -8, -3, -6, -6, -3, -3, -3, -6, -2, -2, -2, -2, -2, -2,
                                 -2, -2, -2, -2, -2, -2, -2, -2]
        send(deltaX: 0, scrollPhase: 128, momentumPhase: 0)
        send(deltaX: -14, scrollPhase: 1, momentumPhase: 0)
        send(deltaX: 0, scrollPhase: 4, momentumPhase: 0)   // ended（NS .ended = CG 4）
        send(deltaX: momentum[0], scrollPhase: 0, momentumPhase: 1)
        for delta in momentum.dropFirst() {
            send(deltaX: delta, scrollPhase: 0, momentumPhase: 2)
        }
        send(deltaX: 0, scrollPhase: 0, momentumPhase: 3)
        pump(0.3)

        let moved = offsetX - start
        let expected = CGFloat(14 + momentum.map { -Int($0) }.reduce(0, +))
        print("[DEBUG-scrl] quick-flick[\(label)] start=\(start) end=\(offsetX) moved=\(moved) 事件Σ=\(expected)")
        XCTAssertGreaterThan(
            moved, expected * 0.5,
            "[DEBUG-scrl] \(label)：快速轻扫的惯性被丢弃：Σdelta=\(expected) 实际只走了 \(moved)"
        )

        // 接管之后的常规拖动必须无缝衔接：不回跳、按 delta 正常前进。
        let beforeDrag = offsetX
        performGesture(deltas: Array(repeating: -20, count: 6))
        let dragMoved = offsetX - beforeDrag
        XCTAssertGreaterThan(
            dragMoved, 60,
            "[DEBUG-scrl] \(label)：接管后常规拖动异常（moved=\(dragMoved)），疑似状态回跳"
        )
    }

    /// 9. 慢速拖动（真机取证 17:18:06 seg51 的模式）：小 delta 的长 changed 事件列。
    ///    真机表现：前 ~5 个事件 1:1 应用，此后整列手势事件被无视、几何冻结 12 秒。
    func testSlowDragKeepsApplying() throws {
        try setUpPanel()
        try assertSlowDragGlides("SummonPanelView")
    }

    func testSlowDragOnLazyControlStrip() throws {
        try setUpPanel(rootView: AnyView(PlainDiagStrip(lazy: true)))
        try assertSlowDragGlides("LazyHStack对照")
    }

    // 诊断期还存在过三类一次性取证测试，结论已入 commit 记录，测试本体已删：
    //   - 系统层 CGEventPost 投递（复现的是合成流保真度工件，非产品缺陷）；
    //   - 劫持真实光标的悬停变体（证明 harness 无法在手势中途插入 tracking 事件）；
    //   - 视图层级 dump（确认玻璃卡由 SwiftUI._NSGraphicsView 承载、hitTest 穿透）。

    private func assertSlowDragGlides(_ label: String) throws {
        // 先滚到中段（避免边缘），并留出与真机一致的手势间隔。
        performGesture(deltas: Array(repeating: -40, count: 10))
        pump(0.2)
        let start = offsetX
        XCTAssertGreaterThan(start, 100, "[DEBUG-scrl] \(label)：前置滚动未生效")

        // 慢拖：began(dx=-1) + 120 × changed(dx=-2)，事件间隔 ~8ms 对齐真机 120Hz。
        var trace: [CGFloat] = []
        send(deltaX: 0, scrollPhase: 128, momentumPhase: 0)
        send(deltaX: -1, scrollPhase: 1, momentumPhase: 0)
        for _ in 0..<120 {
            send(deltaX: -2, scrollPhase: 2, momentumPhase: 0)
            pump(0.005)
            trace.append(offsetX)
        }
        send(deltaX: 0, scrollPhase: 4, momentumPhase: 0)
        pump(0.1)

        let moved = offsetX - start
        let expected: CGFloat = 241
        // 压缩打印轨迹（每 10 个事件一个采样点）便于观察冻结点。
        let samples = stride(from: 0, to: trace.count, by: 10).map { "\(trace[$0])" }
        print("[DEBUG-scrl] slow-drag[\(label)] start=\(start) end=\(offsetX) moved=\(moved)/\(expected) 轨迹=\(samples.joined(separator: ","))")
        XCTAssertGreaterThan(
            moved, expected * 0.5,
            "[DEBUG-scrl] \(label)：慢速拖动中途冻结：Σdelta=\(expected) 实际只走了 \(moved)"
        )
    }

    /// 10. 透明区丢事件判定（真机复现：光标特意放在两卡缝隙里则完全划不动）。
    ///     面板是无边框透明窗口：卡间 10px 间隙 / 未选中卡上方留白原本 hitTest 为 nil
    ///    （点击穿透区），手势从 began 起即被丢弃。卡片条垫命中兜底背景后三个落点都应能滚。
    ///     走 panel.sendEvent（完整 NSWindow 路由）；面板放 (0,0) 使无窗口事件坐标恰为窗口坐标；
    ///     每段拖动前滚回起点，保证落点与卡/缝的对位成立。
    func testSendEventRoutingOverCardBodyAndGap() throws {
        try setUpPanel()
        panel.setFrame(
            NSRect(x: 0, y: 0, width: 1_000, height: SummonPanelLayout.normalPanelHeight),
            display: true
        )
        pump(0.2)

        // 窗口坐标（bottom-left）：卡片条 ScrollView 占 y∈[56,284]，槽底 72；
        // 未选中卡 126 高 → 卡身 y∈[72,198]，上方留白 y∈(198,268]。
        // offset=0 时：卡0(选中,252宽) x∈[16,268]，间隙 x∈[268,278]，卡1 x∈[278,406]。
        let overCardBody = CGPoint(x: 340, y: 150)   // 卡1 实体
        let overGap = CGPoint(x: 273, y: 150)        // 卡0/卡1 之间的间隙
        let overTopBand = CGPoint(x: 340, y: 230)    // 卡1 上方透明带

        func sendViaWindow(deltaX: Int32, scrollPhase: Int64, at point: CGPoint) {
            let screenHeight = NSScreen.screens.first?.frame.height ?? 1_000
            guard let cg = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                wheel1: 0, wheel2: deltaX, wheel3: 0
            ) else { return }
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
            cg.location = CGPoint(x: point.x, y: screenHeight - point.y)   // 转 CG top-left
            guard let event = NSEvent(cgEvent: cg) else { return }
            panel.sendEvent(event)
            pump(0.003)
        }

        // 每段拖动前滚回起点：落点坐标按 offset=0 计算，不归零则对位失效。
        // 回滚会触发左边缘橡皮筋，必须等回弹动画完全停稳再开始下一段，否则测量被污染。
        func scrollBackToStart() {
            var attempts = 0
            while offsetX > 1, attempts < 10 {
                sendViaWindow(deltaX: 0, scrollPhase: 1, at: overCardBody)
                for _ in 0..<10 { sendViaWindow(deltaX: 200, scrollPhase: 2, at: overCardBody) }
                sendViaWindow(deltaX: 0, scrollPhase: 4, at: overCardBody)
                pump(0.1)
                attempts += 1
            }
            var settleTicks = 0
            var lastOffset = offsetX
            while settleTicks < 40 {
                pump(0.05)
                if abs(offsetX - lastOffset) < 0.25 { break }
                lastOffset = offsetX
                settleTicks += 1
            }
            XCTAssertLessThanOrEqual(abs(offsetX), 1.5, "[DEBUG-scrl] 无法稳定回到起点，harness 异常")
        }

        func slowDrag(at point: CGPoint, label: String) -> CGFloat {
            scrollBackToStart()
            let before = offsetX
            sendViaWindow(deltaX: -1, scrollPhase: 1, at: point)
            for _ in 0..<40 { sendViaWindow(deltaX: -4, scrollPhase: 2, at: point) }
            sendViaWindow(deltaX: 0, scrollPhase: 4, at: point)
            pump(0.05)
            let moved = offsetX - before
            print("[DEBUG-scrl] sendEvent慢拖[\(label)] moved=\(moved)/161")
            return moved
        }

        let bodyMoved = slowDrag(at: overCardBody, label: "卡身")
        let gapMoved = slowDrag(at: overGap, label: "间隙")
        let bandMoved = slowDrag(at: overTopBand, label: "上方留白")

        XCTAssertGreaterThan(bodyMoved, 100, "[DEBUG-scrl] 落点在卡身也不滚：sendEvent 路由 harness 不成立")
        XCTAssertGreaterThan(gapMoved, 100, "[DEBUG-scrl] 落点在卡间隙时事件被丢弃（光标放缝里划不动）")
        XCTAssertGreaterThan(bandMoved, 100, "[DEBUG-scrl] 落点在卡上方透明带时事件被丢弃")

        // 缺陷本体判定：三个落点（含缝隙 / 上方留白）hitTest 必须命中实体视图。
        // 无命中兜底背景时缝隙命中 nil——真实 AppKit 手势锁定语义下整段手势被丢弃，
        // 合成的无窗口事件测不出这一段，故直接断言命中本身。
        scrollBackToStart()
        let content = try XCTUnwrap(panel.contentView)
        for (point, label) in [(overCardBody, "卡身"), (overGap, "间隙"), (overTopBand, "上方留白")] {
            let hit = content.superview?.hitTest(point)
            XCTAssertNotNil(
                hit,
                "[DEBUG-scrl] \(label) hitTest 为 nil：滚动区存在点击穿透缺口，缝里滚动会被丢弃"
            )
        }
    }

    /// 11. 坏坐标事件判定（真机取证 18:00:36 的模式：loc.y = mouse.y − 656，掉出窗口）。
    ///     真机上手势段大量事件带坏 y 坐标 → hitTest nil → NSWindow 丢弃 → 冻结。
    ///     本测试把面板放 (0,0)，先发合法坐标事件（应滚动），再发坏 y 坐标事件走
    ///     panel.sendEvent——若坏坐标事件被丢弃则复现冻结（修复前红）；接上
    ///     ScrollEventRescue 后应恢复滚动（修复后绿）。
    func testCorruptedLocationEventsStillScroll() throws {
        try setUpPanel()
        panel.setFrame(
            NSRect(x: 0, y: 0, width: 1_000, height: SummonPanelLayout.normalPanelHeight),
            display: true
        )
        pump(0.2)
        let rescue = ScrollEventRescue()

        let screenHeight = NSScreen.screens.first?.frame.maxY ?? 1_000
        var rescueEnabled = false
        // 面板在 (0,0)：无窗口事件的 locationInWindow == AppKit 全局坐标 == 窗口坐标。
        func sendViaWindow(deltaX: Int32, scrollPhase: Int64, locY: CGFloat) {
            guard let cg = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                wheel1: 0, wheel2: deltaX, wheel3: 0
            ) else { return }
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
            cg.location = CGPoint(x: 340, y: screenHeight - locY)   // CG top-left 全局
            guard let event = NSEvent(cgEvent: cg) else { return }
            // pointerOverride：模拟「物理光标在面板卡身上」（测试机真实光标位置不可控）。
            if rescueEnabled,
               rescue.rescueIfNeeded(event, assumeWindow: panel, pointerOverride: NSPoint(x: 340, y: 150)) {
                pump(0.003)
                return
            }
            panel.sendEvent(event)
            pump(0.003)
        }

        func corruptedDrag() -> CGFloat {
            let before = offsetX
            sendViaWindow(deltaX: -1, scrollPhase: 1, locY: 150)
            for i in 0..<40 {
                sendViaWindow(deltaX: -4, scrollPhase: 2, locY: i < 5 ? 150 : -446)
            }
            sendViaWindow(deltaX: 0, scrollPhase: 4, locY: -446)
            pump(0.05)
            return offsetX - before
        }

        // 基线 1：合法坐标（y=150，卡身）应能滚。
        let beforeValid = offsetX
        sendViaWindow(deltaX: -1, scrollPhase: 1, locY: 150)
        for _ in 0..<20 { sendViaWindow(deltaX: -8, scrollPhase: 2, locY: 150) }
        sendViaWindow(deltaX: 0, scrollPhase: 4, locY: 150)
        pump(0.05)
        let validMoved = offsetX - beforeValid
        print("[DEBUG-scrl] 合法坐标 moved=\(validMoved)/161")
        XCTAssertGreaterThan(validMoved, 100, "[DEBUG-scrl] 合法坐标事件也不滚：harness 不成立")

        // 基线 2（机制自证）：营救关闭时，坏 y 事件应被丢弃 → 几乎不动（复现真机冻结）。
        let droppedMoved = corruptedDrag()
        print("[DEBUG-scrl] 坏坐标（无营救）moved=\(droppedMoved)/161")
        XCTAssertLessThan(
            droppedMoved, 60,
            "[DEBUG-scrl] 坏坐标事件竟然照常滚动——「坏坐标即根因」的机制假设需要重审"
        )

        // 修复验证：开启营救后，同样的坏坐标事件流应滚满。
        rescueEnabled = true
        let rescuedMoved = corruptedDrag()
        print("[DEBUG-scrl] 坏坐标（营救开）moved=\(rescuedMoved)/161")
        XCTAssertGreaterThan(
            rescuedMoved, 100,
            "[DEBUG-scrl] 营救未生效：坏坐标事件仍被丢弃"
        )
    }

    /// 对照条：与 SummonPanelView 同构的最小 ScrollView 卡片条，
    /// 首张 252×196 其余 128×126、间距 10、四周 16 padding，无玻璃/手势/显式钉宽。
    /// lazy 参数切换 LazyHStack（估算式布局）与 HStack（全实体化）做差分。
    private struct PlainDiagStrip: View {
        var lazy = true

        var body: some View {
            VStack(spacing: 18) {
                ScrollView(.horizontal) {
                    if lazy {
                        LazyHStack(alignment: .bottom, spacing: 10) { cards }
                            .padding(16)
                    } else {
                        HStack(alignment: .bottom, spacing: 10) { cards }
                            .padding(16)
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: 228)
            }
        }

        private var cards: some View {
            ForEach(0..<50, id: \.self) { index in
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(0.4))
                    .frame(
                        width: index == 0 ? 252 : 128,
                        height: index == 0 ? 196 : 126
                    )
                    .frame(height: 196, alignment: .bottom)
            }
        }
    }

    // MARK: - 波浪放大（「完整特效」，01 §3.2）

    /// 12. 波浪激活下滚动照常到底：特效是纯 visualEffect 变换，不触碰滚动几何与事件路径。
    ///     指针钉在条中部、gain=1，滚动全程卡片逐帧过波峰——布局驱动式实现会在此重现
    ///     「尺寸切换反复重排」的冻结,变换驱动应与基线用例同绿。
    func testWaveActiveScrollReachesEnd() throws {
        try setUpPanel()
        model.wave.preparePresentation(enabled: true)
        model.wave.pointerMoved(to: 500)
        let stalled = scrollToEnd { performGesture(deltas: Array(repeating: -40, count: 20)) }
        assertReachesEnd(stalled, "波浪激活")
    }

    /// 13. 波浪激活下惯性滚动（含 mayBegin/momentum 全相位）不被特效打断。
    func testWaveActiveMomentumScrollReachesEnd() throws {
        try setUpPanel()
        model.wave.preparePresentation(enabled: true)
        model.wave.pointerMoved(to: 500)
        let momentum: [Int32] = stride(from: -60, through: -2, by: 4).map { Int32($0) }
        let stalled = scrollToEnd {
            performGesture(
                deltas: Array(repeating: -30, count: 8),
                mayBegin: true,
                momentumDeltas: momentum
            )
        }
        assertReachesEnd(stalled, "波浪激活惯性")
    }

    /// 14. 波浪开 / 关的滚动开销对照（报告用）：同一事件流各跑一遍，打印进程 CPU 时间与
    ///     RSS 增量。pump 的 RunLoop 睡眠主导墙钟,CPU 时间才是特效开销的信号;只做
    ///     倍数级防线断言,精确帧率以 Instruments 实测为准（02 §9 summon.wave 区间）。
    func testWaveScrollOverheadReport() throws {
        func cpuSeconds() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
            let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
            return user + system
        }
        func residentMB() -> Double {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(
                MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
            )
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
        }

        func measureRun(waveEnabled: Bool) throws -> (cpu: Double, rss: Double) {
            try setUpPanel()
            model.wave.preparePresentation(enabled: waveEnabled)
            if waveEnabled { model.wave.pointerMoved(to: 500) }
            let cpuBefore = cpuSeconds()
            for _ in 0..<6 {
                performGesture(deltas: Array(repeating: -40, count: 20))
                performGesture(deltas: Array(repeating: 40, count: 20))
            }
            let cpu = cpuSeconds() - cpuBefore
            let rss = residentMB()
            panel.orderOut(nil)
            return (cpu, rss)
        }

        let off = try measureRun(waveEnabled: false)
        let on = try measureRun(waveEnabled: true)
        print("[DEBUG-wave] 滚动 240 事件 CPU: off=\(String(format: "%.3f", off.cpu))s " +
              "on=\(String(format: "%.3f", on.cpu))s (+\(String(format: "%.0f", (on.cpu / max(off.cpu, 0.001) - 1) * 100))%) " +
              "RSS: off=\(String(format: "%.1f", off.rss))MB on=\(String(format: "%.1f", on.rss))MB")
        XCTAssertLessThan(on.cpu, max(off.cpu, 0.05) * 3,
                          "[DEBUG-wave] 波浪激活的滚动 CPU 开销超过基线 3 倍，疑似逐帧重排回归")
    }

    /// 4. 确定性 fuzz：变长 delta + 时有时无的惯性段，长跑多轮（模拟人手的不规则滑动）。
    func testFuzzedGestureSoak() throws {
        try setUpPanel(itemCount: 120)
        var seed: UInt64 = 0x5EED_2026
        func rand(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        let stalled = scrollToEnd(rounds: 120) {
            let count = 4 + rand(24)
            let deltas = (0..<count).map { _ in Int32(-(4 + rand(72))) }
            let withMomentum = rand(2) == 0
            let momentum: [Int32] = withMomentum
                ? stride(from: -(20 + rand(50)), through: -2, by: 5).map { Int32($0) }
                : []
            return performGesture(
                deltas: deltas,
                deltaYRatio: Double(rand(40)) / 100.0,
                mayBegin: withMomentum,
                momentumDeltas: momentum
            )
        }
        assertReachesEnd(stalled, "fuzz 长跑")
    }
}
