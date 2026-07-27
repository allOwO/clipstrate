import AppKit

/// 唤出面板窗口（02 §6）：无边框、非激活；可成为 key 以接收键盘，但不抢 App 激活态。
/// 双指拖动冻结的工作区不在此处：ScrollEventRescue 以 App 级 monitor 覆盖所有窗口。
final class SummonPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
