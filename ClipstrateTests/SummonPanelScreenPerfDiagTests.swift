import AppKit
import SwiftUI
import XCTest
@testable import Clipstrate

/// 多屏滚动开销诊断（2026-07-30「60Hz 副屏卡顿」定性用）。**报告型用例，不做硬断言**：
/// 在真 Clipstrate.app 宿主里把真面板依次摆到每块屏上，用同一条合成滚动事件流驱动，
/// 分别量「进程内主线程 CPU」与「WindowServer 累计 CPU」——前者是代码开销，
/// 后者是 Liquid Glass 背景重采样的合成开销（进程内 trace 测不到，见工作流备忘）。
///
/// 二因子设计，把「屏」和「面板宽度」分开：
///   A 内屏 @ 内屏自然宽    B 副屏 @ 副屏自然宽    C 副屏 @ 内屏自然宽
///   B vs C → 同一块屏上，面板变宽带来的开销（代码/布局决定的量）
///   A vs C → 同样宽度下，换屏带来的开销（硬件/合成器决定的量）
/// 面板宽度不是常量：panelSize 按 `screen.visibleFrame.width` 算，逻辑桌面越宽面板越宽、
/// 实体化的玻璃卡越多——副屏 2560pt 与内屏 1512pt 差 1.7 倍，这本身就是变量。
@MainActor
final class SummonPanelScreenPerfDiagTests: XCTestCase {
    private var panel: SummonPanel!
    private var model: SummonPanelModel!
    private var scrollView: NSScrollView!
    private var clip: NSClipView!
    private var gestureTarget: NSView!
    private var globalLocation: CGPoint = .zero

    override func tearDown() async throws {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - 屏幕清单

    private struct ScreenInfo {
        let index: Int
        let screen: NSScreen
        let isBuiltIn: Bool
        var label: String { isBuiltIn ? "内屏#\(index)" : "副屏#\(index)" }
        /// 生产环境该屏上的面板宽度（与 PanelController.updateLayout 同一条公式）。
        func panelWidth(itemCount: Int) -> CGFloat {
            SummonPanelLayout.panelSize(
                itemCount: itemCount,
                availableWidth: screen.visibleFrame.width
            ).width
        }
    }

    /// 内屏判定：ProMotion 内屏是唯一 maximumFramesPerSecond > 60 的那块；退化时按
    /// CGDisplayIsBuiltin 判。两者都拿不到就按索引 0。
    private func screenInfos() -> [ScreenInfo] {
        NSScreen.screens.enumerated().map { index, screen in
            let displayID = (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value
            let builtIn = displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? (index == 0)
            return ScreenInfo(index: index, screen: screen, isBuiltIn: builtIn)
        }
    }

    // MARK: - 夹具（与 SummonPanelScrollDiagTests 同款，追加 targetScreen / 宽度可控）

    private func setUpPanel(itemCount: Int, on screen: NSScreen, panelWidth: CGFloat) throws {
        model = SummonPanelModel(historyStore: nil, initialItems: makeItems(itemCount))
        panel = SummonPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth,
                               height: SummonPanelLayout.normalPanelHeight),
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
        model.beginPresentation()

        // 摆到目标屏 visibleFrame 的水平居中、靠下——与生产的 caret 锚点定位同区域。
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: visible.midX - panelWidth / 2,
            y: visible.minY + 80,
            width: panelWidth,
            height: SummonPanelLayout.normalPanelHeight
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        pump(0.8)

        let content = try XCTUnwrap(panel.contentView)
        scrollView = try XCTUnwrap(
            findViews(in: content) { $0 is NSScrollView }.first as? NSScrollView
        )
        clip = scrollView.contentView

        let midInWindow = scrollView.convert(
            CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY), to: nil
        )
        globalLocation = flippedGlobal(panel.convertPoint(toScreen: midInWindow))
        gestureTarget = scrollView
    }

    /// NSEvent 屏幕坐标（左下原点）→ CGEvent 全局坐标（左上原点，以主屏为基准）。
    private func flippedGlobal(_ point: CGPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    private func makeItems(_ count: Int) -> [ClipItem] {
        (0..<count).map { index in
            ClipItem(
                kind: .text,
                plainText: "条目 \(index) 的示例文本，用来占据卡片正文若干行。",
                contentHash: "screen-perf-hash-\(index)",
                appName: "DiagApp"
            )
        }
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func layerCount(_ root: CALayer?) -> Int {
        guard let root else { return 0 }
        return 1 + (root.sublayers ?? []).reduce(0) { $0 + layerCount($1) }
    }

    private func findViews(in root: NSView, where predicate: (NSView) -> Bool) -> [NSView] {
        var result: [NSView] = []
        if predicate(root) { result.append(root) }
        for sub in root.subviews {
            result.append(contentsOf: findViews(in: sub, where: predicate))
        }
        return result
    }

    // MARK: - 事件引擎（同 SummonPanelScrollDiagTests，去掉惯性救援镜像：本用例只跑手势段）

    private func send(deltaX: Int32, scrollPhase: Int64) {
        guard let cg = CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: 0, wheel2: deltaX, wheel3: 0
        ) else { return }
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
        cg.location = globalLocation
        guard let event = NSEvent(cgEvent: cg) else { return }
        gestureTarget.scrollWheel(with: event)
        pump(0.008)                                     // ≈120Hz，贴近真实触控板出事率
    }

    private func performGesture(deltas: [Int32]) {
        send(deltaX: 0, scrollPhase: 1)
        for delta in deltas { send(deltaX: delta, scrollPhase: 2) }
        send(deltaX: 0, scrollPhase: 4)
    }

    // MARK: - 采样

    private func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        return user + system
    }

    /// WindowServer 累计 CPU 秒。玻璃背景重采样的开销在那个进程里，进程内 trace 测不到。
    /// `ps -o time=` 分辨率 1s，所以每个 run 要跑够长（本用例约 8–10s）才有信噪比。
    private nonisolated func windowServerCPUSeconds() -> Double? {
        guard let pidOut = shell("/usr/bin/pgrep", ["-x", "WindowServer"]),
              let pid = pidOut.split(separator: "\n").first.map(String.init),
              let timeOut = shell("/bin/ps", ["-o", "time=", "-p", pid]) else { return nil }
        // 形如 "12:34.56" / "1-02:03:04"；按冒号分段折算成秒。
        let trimmed = timeOut.trimmingCharacters(in: .whitespacesAndNewlines)
        let daySplit = trimmed.split(separator: "-")
        let days = daySplit.count == 2 ? Double(daySplit[0]) ?? 0 : 0
        let clock = String(daySplit.last ?? "")
        var seconds = days * 86_400
        for part in clock.split(separator: ":") {
            seconds = seconds * 60 + (Double(part) ?? 0)
        }
        return seconds
    }

    private nonisolated func shell(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 报告

    private struct Sample {
        let label: String
        let panelWidth: CGFloat
        let backingScale: CGFloat
        let maxFPS: Int
        let events: Int
        let appCPU: Double
        let windowServerCPU: Double?
        let wall: Double
        let instantiatedCards: Int
        /// 面板占用的物理像素（玻璃重采样的量级正比于它）。
        var panelPixels: Double {
            Double(panelWidth * SummonPanelLayout.normalPanelHeight)
                * Double(backingScale * backingScale)
        }
        var appCPUPerEvent: Double { appCPU / Double(max(events, 1)) }
    }

    /// 屏幕清单先单独打一份：刷新率 / backingScale / visibleFrame 是后面所有解读的前提。
    func testReportScreenInventory() {
        for info in screenInfos() {
            let screen = info.screen
            print("[DEBUG-scrn] \(info.label) frame=\(screen.frame) visible=\(screen.visibleFrame) " +
                  "backingScale=\(screen.backingScaleFactor) maxFPS=\(screen.maximumFramesPerSecond) " +
                  "面板宽=\(info.panelWidth(itemCount: 50))")
        }
        XCTAssertFalse(NSScreen.screens.isEmpty)
    }

    /// 二因子对照报告。单屏机器上只会跑出 A 一行（B/C 自动跳过，不算失败）。
    func testReportScrollCostAcrossScreens() throws {
        let itemCount = 50
        let infos = screenInfos()
        let builtIn = infos.first { $0.isBuiltIn } ?? infos[0]
        let external = infos.first { !$0.isBuiltIn }

        var runs: [(label: String, screen: ScreenInfo, width: CGFloat)] = [
            ("A 内屏@内屏宽", builtIn, builtIn.panelWidth(itemCount: itemCount))
        ]
        if let external {
            runs.append(("B 副屏@副屏宽", external, external.panelWidth(itemCount: itemCount)))
            runs.append(("C 副屏@内屏宽", external, builtIn.panelWidth(itemCount: itemCount)))
        } else {
            print("[DEBUG-scrn] 只有一块屏，跳过 B/C 对照。")
        }

        var samples: [Sample] = []
        for run in runs {
            try setUpPanel(itemCount: itemCount, on: run.screen.screen, panelWidth: run.width)
            model.wave.preparePresentation(enabled: true)
            model.wave.pointerMoved(to: run.width / 2)
            pump(0.4)                                   // 让波浪 gain 动画收敛，不算进采样

            // 图层数是玻璃表面数量的代理指标：SwiftUI 不给每张卡起 NSView，但每层玻璃
            // 都要一个独立 CALayer 才能各自采样背景。
            let cards = layerCount(panel.contentView?.layer)
            let wsBefore = windowServerCPUSeconds()
            let cpuBefore = cpuSeconds()
            let wallBefore = Date()
            // 跑到 20s 墙钟为止：ps -o time= 只有 1s 分辨率，窗口太短 WindowServer 读数全是 0。
            // 事件间隔按 8ms（≈120Hz，贴近真实触控板出事率），不刻意压满。
            var events = 0
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                performGesture(deltas: Array(repeating: -40, count: 20)); events += 22
                performGesture(deltas: Array(repeating: 40, count: 20)); events += 22
            }
            let appCPU = cpuSeconds() - cpuBefore
            let wall = Date().timeIntervalSince(wallBefore)
            let wsAfter = windowServerCPUSeconds()

            var wsDelta: Double?
            if let before = wsBefore, let after = wsAfter { wsDelta = after - before }
            samples.append(Sample(
                label: run.label,
                panelWidth: run.width,
                backingScale: run.screen.screen.backingScaleFactor,
                maxFPS: run.screen.screen.maximumFramesPerSecond,
                events: events,
                appCPU: appCPU,
                windowServerCPU: wsDelta,
                wall: wall,
                instantiatedCards: cards
            ))
            panel.orderOut(nil)
            pump(0.3)
        }

        for sample in samples {
            let ws: String = sample.windowServerCPU.map { String(format: "%.0fs", $0) } ?? "n/a"
            let pixels: String = String(format: "%.2f", sample.panelPixels / 1e6)
            let wall: String = String(format: "%.1f", sample.wall)
            let cpu: String = String(format: "%.3f", sample.appCPU)
            let perEvent: String = String(format: "%.3f", sample.appCPUPerEvent * 1000)
            let geometry: String = "宽=\(Int(sample.panelWidth))pt scale=\(sample.backingScale)"
            let display: String = "maxFPS=\(sample.maxFPS) 像素=\(pixels)Mpx"
            let load: String = "叶子视图=\(sample.instantiatedCards) 事件=\(sample.events) 墙钟=\(wall)s"
            let cost: String = "主线程CPU=\(cpu)s (\(perEvent)ms/事件) WindowServerCPU=\(ws)"
            print("[DEBUG-scrn] \(sample.label) \(geometry) \(display) \(load) \(cost)")
        }
        // 帧预算参照：120Hz=8.33ms，60Hz=16.67ms。主线程每事件成本对上它就知道瓶颈在哪边。
        if let a = samples.first(where: { $0.label.hasPrefix("A") }),
           let b = samples.first(where: { $0.label.hasPrefix("B") }),
           let c = samples.first(where: { $0.label.hasPrefix("C") }) {
            let widthEffect: String = String(format: "%.2f", b.appCPUPerEvent / max(c.appCPUPerEvent, 1e-9))
            let screenEffect: String = String(format: "%.2f", c.appCPUPerEvent / max(a.appCPUPerEvent, 1e-9))
            let pixelRatio: String = String(format: "%.2f", b.panelPixels / max(a.panelPixels, 1))
            print("[DEBUG-scrn] 结论用比值：宽度效应 B/C=\(widthEffect)× " +
                  "换屏效应 C/A=\(screenEffect)× 像素 B/A=\(pixelRatio)×")
        }
        XCTAssertFalse(samples.isEmpty)
    }

    /// 帧规律性对照：把 CADisplayLink 挂在面板视图上（它跟随窗口所在那块屏的 vsync），
    /// 滚动全程记回调时刻，统计「间隔 > 1.5 / 2.5 倍标称帧长」的次数——这就是掉帧/顿挫。
    /// 注意：主线程被 pump 的 RunLoop 占着，display link 回调迟到本身即主线程卡顿信号；
    /// 但 WindowServer 侧的合成掉帧本用例测不到（那部分看上一个用例的 WindowServer CPU）。
    func testReportFrameRegularityAcrossScreens() throws {
        let itemCount = 50
        let infos = screenInfos()
        let builtIn = infos.first { $0.isBuiltIn } ?? infos[0]
        let external = infos.first { !$0.isBuiltIn }

        var runs: [(label: String, screen: ScreenInfo, width: CGFloat)] = [
            ("A 内屏@内屏宽", builtIn, builtIn.panelWidth(itemCount: itemCount))
        ]
        if let external {
            runs.append(("B 副屏@副屏宽", external, external.panelWidth(itemCount: itemCount)))
            runs.append(("C 副屏@内屏宽", external, builtIn.panelWidth(itemCount: itemCount)))
        }

        for run in runs {
            try setUpPanel(itemCount: itemCount, on: run.screen.screen, panelWidth: run.width)
            model.wave.preparePresentation(enabled: true)
            model.wave.pointerMoved(to: run.width / 2)
            pump(0.4)

            let recorder = FrameRecorder()
            let link = try XCTUnwrap(panel.contentView).displayLink(
                target: recorder, selector: #selector(FrameRecorder.tick(_:))
            )
            link.add(to: .main, forMode: .default)
            recorder.stamps.removeAll()

            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                performGesture(deltas: Array(repeating: -40, count: 20))
                performGesture(deltas: Array(repeating: 40, count: 20))
            }
            link.invalidate()

            let nominal = 1.0 / Double(max(run.screen.screen.maximumFramesPerSecond, 1))
            let stamps = recorder.stamps
            var gaps: [Double] = []
            for index in 1..<max(stamps.count, 1) { gaps.append(stamps[index] - stamps[index - 1]) }
            let span = (stamps.last ?? 0) - (stamps.first ?? 0)
            let fps: Double = span > 0 ? Double(stamps.count - 1) / span : 0
            let mild = gaps.filter { $0 > nominal * 1.5 }.count
            let bad = gaps.filter { $0 > nominal * 2.5 }.count
            let worst = gaps.max() ?? 0

            let fpsText: String = String(format: "%.1f", fps)
            let nominalText: String = String(format: "%.2f", nominal * 1000)
            let worstText: String = String(format: "%.1f", worst * 1000)
            let mildPct: String = String(format: "%.1f", Double(mild) / Double(max(gaps.count, 1)) * 100)
            let badPct: String = String(format: "%.1f", Double(bad) / Double(max(gaps.count, 1)) * 100)
            print("[DEBUG-frame] \(run.label) 宽=\(Int(run.width))pt " +
                  "标称=\(run.screen.screen.maximumFramesPerSecond)Hz(\(nominalText)ms) " +
                  "实测=\(fpsText)fps 帧数=\(stamps.count) " +
                  ">1.5×=\(mild)(\(mildPct)%) >2.5×=\(bad)(\(badPct)%) 最长=\(worstText)ms")

            panel.orderOut(nil)
            pump(0.3)
        }
        XCTAssertFalse(NSScreen.screens.isEmpty)
    }
}

extension SummonPanelScreenPerfDiagTests {
    /// 关键对照：把「滚动扫卡实时选中」也驱动起来。前两个用例的合成事件流里物理光标
    /// 根本不在面板上，SwiftUI 的 onHover 不会触发 → hoverSelect 从未跑过，因此
    /// 「选中每隔几十毫秒切一次 + 每次切换带 124pt 宽度变化的 0.12s 动画」这条真实
    /// 负载被整个漏掉了。这里按滚动位移折算出真实换卡节奏显式调 hoverSelect 补上。
    ///
    /// 判据：若同一负载在 120Hz 内屏不掉帧、在 60Hz 副屏掉帧，则卡顿是**动画节奏与
    /// 刷新率不匹配**（代码问题）而非算力不足（性能问题）。
    func testReportFrameRegularityWithLiveHoverSelect() throws {
        let itemCount = 50
        let infos = screenInfos()
        let builtIn = infos.first { $0.isBuiltIn } ?? infos[0]
        let external = infos.first { !$0.isBuiltIn }

        var runs: [(label: String, screen: ScreenInfo, width: CGFloat)] = [
            ("A 内屏@内屏宽", builtIn, builtIn.panelWidth(itemCount: itemCount))
        ]
        if let external {
            runs.append(("B 副屏@副屏宽", external, external.panelWidth(itemCount: itemCount)))
            runs.append(("C 副屏@内屏宽", external, builtIn.panelWidth(itemCount: itemCount)))
        }

        for run in runs {
            try setUpPanel(itemCount: itemCount, on: run.screen.screen, panelWidth: run.width)
            model.wave.preparePresentation(enabled: true)
            model.wave.pointerMoved(to: run.width / 2)
            // 滚动相位置真：hoverSelect 的位移判据只在非滚动时挡被动悬停。
            model.scrollPhaseChanged(isScrolling: true)
            pump(0.4)

            let recorder = FrameRecorder()
            let link = try XCTUnwrap(panel.contentView).displayLink(
                target: recorder, selector: #selector(FrameRecorder.tick(_:))
            )
            link.add(to: .main, forMode: .default)
            recorder.stamps.removeAll()

            // 卡片节距 138pt（未选中 128 + 间距 10），每事件滚 40pt → 约每 3.5 个事件
            // 换一张卡。取 3 事件换一次，接近真实「扫卡」节奏。
            let cpuBefore = cpuSeconds()
            var hoverChanges = 0
            var eventIndex = 0
            var cursor = 0
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                send(deltaX: 0, scrollPhase: 1)
                for _ in 0..<20 {
                    send(deltaX: -40, scrollPhase: 2)
                    eventIndex += 1
                    if eventIndex % 3 == 0 {
                        cursor = (cursor + 1) % itemCount
                        model.hoverSelect(at: cursor)
                        hoverChanges += 1
                    }
                }
                send(deltaX: 0, scrollPhase: 4)
            }
            let appCPU = cpuSeconds() - cpuBefore
            link.invalidate()

            let nominal = 1.0 / Double(max(run.screen.screen.maximumFramesPerSecond, 1))
            let stamps = recorder.stamps
            var gaps: [Double] = []
            for index in 1..<max(stamps.count, 1) { gaps.append(stamps[index] - stamps[index - 1]) }
            let span = (stamps.last ?? 0) - (stamps.first ?? 0)
            let fps: Double = span > 0 ? Double(stamps.count - 1) / span : 0
            let mild = gaps.filter { $0 > nominal * 1.5 }.count
            let bad = gaps.filter { $0 > nominal * 2.5 }.count
            let worst = gaps.max() ?? 0
            let selectRate: Double = span > 0 ? Double(hoverChanges) / span : 0

            let fpsText: String = String(format: "%.1f", fps)
            let worstText: String = String(format: "%.1f", worst * 1000)
            let mildPct: String = String(format: "%.1f", Double(mild) / Double(max(gaps.count, 1)) * 100)
            let badPct: String = String(format: "%.1f", Double(bad) / Double(max(gaps.count, 1)) * 100)
            let rateText: String = String(format: "%.1f", selectRate)
            // 每次换卡带一条 0.12s 的 124pt 宽度动画；换卡间隔 / 帧长 = 动画被重定向前
            // 能显示的帧数。低于 2 就意味着「每帧看到的都是一条刚被打断的新动画」。
            let framesPerSelect: String = selectRate > 0
                ? String(format: "%.1f", 1.0 / selectRate / nominal) : "n/a"
            let cpuText: String = String(format: "%.3f", appCPU)
            print("[DEBUG-hover] \(run.label) 标称=\(run.screen.screen.maximumFramesPerSecond)Hz " +
                  "实测=\(fpsText)fps 换卡=\(rateText)次/s 换卡间隔=\(framesPerSelect)帧 " +
                  ">1.5×=\(mild)(\(mildPct)%) >2.5×=\(bad)(\(badPct)%) 最长=\(worstText)ms " +
                  "主线程CPU=\(cpuText)s")

            panel.orderOut(nil)
            pump(0.3)
        }
        XCTAssertFalse(NSScreen.screens.isEmpty)
    }
}

/// display link 回调只记时刻，不做任何计算（自身开销要远小于被测帧长）。
private final class FrameRecorder: NSObject {
    nonisolated(unsafe) var stamps: [Double] = []

    @objc func tick(_ link: CADisplayLink) {
        stamps.append(link.timestamp)
    }
}
