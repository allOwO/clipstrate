import AppKit

/// 滚动事件营救（macOS 26 滚动事件坐标损坏的最小工作区）。
///
/// 取证结论（复现与判定见 SummonPanelScrollDiagTests）：在无边框非激活透明面板上
/// 双指滚动时，部分滚动事件的 `locationInWindow` 会以错误的基准计算 y（x 正确、
/// y 相对某个错误原点翻转，如 `mouse.y − 656`），事件落点因此掉出窗口边界 →
/// 窗口按坏坐标 hitTest 无命中 → 事件被静默丢弃，手势冻结。体感即
/// 「慢速拖动一小段后卡住不动」（慢拖事件密、必然撞上坏坐标窗口期；快扫事件疏，常能幸免）。
///
/// 本类以 App 级 local monitor 拦截：仅当「事件坐标掉出窗口而物理光标仍在窗口内」
/// 时，按光标真实位置解析目标滚动视图并把事件直接投递给它（绕过按坏坐标 hitTest
/// 的窗口路由；直投不再检查坐标）。坐标正常的事件原样放行，零行为改变。
@MainActor
final class ScrollEventRescue {
    private var monitor: Any?

    /// App 级安装：所有窗口（唤出面板 / 设置 / Popover）统一覆盖。与 uninstall 成对（零泄露清单）。
    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.rescueIfNeeded(event) ? nil : event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// 返回 true = 事件已直接投递给目标视图，调用方应吞掉原事件。
    /// `assumeWindow` / `pointerOverride` 供测试注入（合成事件无窗口关联、测试机光标位置不可控）。
    func rescueIfNeeded(
        _ event: NSEvent,
        assumeWindow: NSWindow? = nil,
        pointerOverride: NSPoint? = nil
    ) -> Bool {
        guard event.type == .scrollWheel, let window = assumeWindow ?? event.window else { return false }
        // 判定「事件坐标是否还在窗口内」：留 2pt 容差，避免边缘抖动误判。
        let location = event.locationInWindow
        let windowBounds = NSRect(origin: .zero, size: window.frame.size).insetBy(dx: -2, dy: -2)
        guard !windowBounds.contains(location) else { return false }
        // 物理光标必须仍在窗口上：光标真的在窗口外时，事件本不属于本窗口，不营救。
        let pointer = pointerOverride ?? NSEvent.mouseLocation
        guard window.frame.contains(pointer) else { return false }
        guard let target = Self.scrollTarget(atScreenPoint: pointer, in: window) else { return false }
        // 低频：仅坏坐标事件走到这里。留证据便于观察系统缺陷是否仍在触发。
        Log.panel.debug("scroll rescue: loc=\(location.y, format: .fixed(precision: 0), privacy: .public) 掉出窗口，已按光标位置直投")
        target.scrollWheel(with: event)
        return true
    }

    /// 光标下的事件投递目标：优先 hitTest；落点在透明区（卡片间隙 / 阴影留白）时，
    /// 窗口内滚动视图唯一则直接投给它。
    private static func scrollTarget(atScreenPoint point: NSPoint, in window: NSWindow) -> NSView? {
        guard let content = window.contentView else { return nil }
        let inWindow = window.convertPoint(fromScreen: point)
        if let hit = content.superview?.hitTest(inWindow) {
            return hit
        }
        let scrollViews = scrollViews(in: content)
        return scrollViews.count == 1 ? scrollViews.first : nil
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
