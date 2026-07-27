import AppKit

/// 双指快速轻扫的惯性救援（macOS 26 SwiftUI ScrollView 缺陷的最小工作区）。
///
/// 取证结论（复现与判定见 SummonPanelScrollDiagTests）：SwiftUI 的 HostingScrollView
/// 并不逐事件应用系统惯性滚动事件，而是用「手势段」估计的速度自行驱动减速动画；
/// 快速轻扫（手指触板极短，手势段 changed 事件 ≤3）的速度估计约等于零，
/// 随后整列系统惯性事件虽到达窗口却被整体丢弃——体感即「滑一段卡住不动、滑不下去」。
///
/// 本类挂在 NSWindow.sendEvent 层观察惯性列，采用「实测死亡才介入」判据：
/// 惯性事件连续到达若干个而 NSClipView 纹丝不动时，才把累计及后续 delta 直接
/// 应用到 NSClipView 并吞掉事件（避免与 SwiftUI 自身物理双重应用）。
/// 正常滑翔（SwiftUI 动画在跑）绝不介入；框架将来修复后本类自然失活。
@MainActor
final class MomentumScrollAssist {
    private var monitor: Any?
    private weak var scrollView: NSScrollView?
    private var originAtMomentumStart: CGPoint = .zero
    private var pendingDelta: CGPoint = .zero
    private var eventCount = 0
    private var assisting = false

    /// 惯性列已到达这么多事件仍无位移 → 判死、开始接管。
    private static let deadEventThreshold = 3
    /// 累计 |delta| 低于该值的惯性尾巴不值得接管（也避免边缘橡皮筋误判）。
    private static let minimumPendingDelta: CGFloat = 8

    /// App 级安装：本地 scrollWheel monitor 一处覆盖所有窗口（唤出面板 / 设置 / Popover——
    /// 缺陷是框架级的，任何 SwiftUI ScrollView 都会中招）。与 uninstall 成对（零泄露清单）。
    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = event.window else { return event }
            return self.handle(event, in: window) ? nil : event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        reset()
    }

    /// 返回 true 表示事件已被接管消费，调用方不应再转发。
    func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard event.type == .scrollWheel else { return false }
        let momentum = event.momentumPhase
        if momentum.isEmpty {
            // 手势段 / 普通滚轮：一律放行；手指重新触板即复位接管状态。
            if event.phase.contains(.mayBegin) || event.phase.contains(.began) { reset() }
            return false
        }
        if momentum.contains(.began) {
            reset()
            scrollView = Self.resolveScrollView(for: event, in: window)
            guard let clip = scrollView?.contentView else { return false }
            originAtMomentumStart = clip.bounds.origin
            accumulate(event)
            return false
        }
        if momentum.contains(.changed) {
            guard let scrollView else { return false }
            accumulate(event)
            if !assisting,
               eventCount >= Self.deadEventThreshold,
               magnitude(pendingDelta) > Self.minimumPendingDelta,
               magnitude(offset(of: scrollView.contentView.bounds.origin,
                                from: originAtMomentumStart)) < 1 {
                assisting = true
            }
            if assisting {
                apply(pendingDelta, to: scrollView)
                pendingDelta = .zero
                return true
            }
            return false
        }
        // .ended / .cancelled：接管中的收尾事件一并吞掉，然后复位。
        let consumed = assisting
        reset()
        return consumed
    }

    private func accumulate(_ event: NSEvent) {
        pendingDelta.x += event.scrollingDeltaX
        pendingDelta.y += event.scrollingDeltaY
        eventCount += 1
    }

    /// 与真实滚动同向：AppKit 惯性事件 delta 为正时内容向起点方向回退（origin 减小）。
    private func apply(_ delta: CGPoint, to scrollView: NSScrollView) {
        let clip = scrollView.contentView
        guard let doc = scrollView.documentView else { return }
        var origin = clip.bounds.origin
        origin.x = min(max(origin.x - delta.x, 0), max(0, doc.frame.width - clip.bounds.width))
        origin.y = min(max(origin.y - delta.y, 0), max(0, doc.frame.height - clip.bounds.height))
        clip.setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(clip)
    }

    private func offset(of point: CGPoint, from other: CGPoint) -> CGPoint {
        CGPoint(x: point.x - other.x, y: point.y - other.y)
    }

    private func magnitude(_ point: CGPoint) -> CGFloat {
        abs(point.x) + abs(point.y)
    }

    private func reset() {
        scrollView = nil
        originAtMomentumStart = .zero
        pendingDelta = .zero
        eventCount = 0
        assisting = false
    }

    /// 事件命中的最近 NSScrollView（惯性列在 began 时锁定，与 AppKit 手势路由一致）。
    /// 合成事件（无窗口关联，坐标换算不成立）hitTest 会落空：窗口内滚动视图唯一时直接采用。
    private static func resolveScrollView(for event: NSEvent, in window: NSWindow) -> NSScrollView? {
        if let frameView = window.contentView?.superview,
           let hit = frameView.hitTest(event.locationInWindow) {
            var view: NSView? = hit
            while let current = view {
                if let scrollView = current as? NSScrollView { return scrollView }
                view = current.superview
            }
        }
        guard let content = window.contentView else { return nil }
        let all = scrollViews(in: content)
        return all.count == 1 ? all.first : nil
    }

    private static func scrollViews(in root: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scrollView = root as? NSScrollView { result.append(scrollView) }
        for sub in root.subviews {
            result.append(contentsOf: scrollViews(in: sub))
        }
        return result
    }
}
