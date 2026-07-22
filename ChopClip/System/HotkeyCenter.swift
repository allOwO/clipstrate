import AppKit
import KeyboardShortcuts

/// 全局热键名与默认值（02 §5）。快捷键本体由 KeyboardShortcuts 持久化管理，
/// 录制控件（设置窗口，B 线 T3.4）直接绑定这些 Name。
extension KeyboardShortcuts.Name {
    /// 唤出/关闭面板，默认 ⌥V。
    static let summon = Self("hotkey.summon", default: .init(.v, modifiers: [.option]))
    /// 划词拆词，默认 ⌥X（动作由 ChopOverlay / B 线提供）。
    static let chop = Self("hotkey.chop", default: .init(.x, modifiers: [.option]))
    /// 〔P1〕堆栈 开启/关闭，默认 ⌃⇧C。
    static let stackToggle = Self("hotkey.stackToggle", default: .init(.c, modifiers: [.control, .shift]))
    /// 〔P1〕堆栈 单条粘贴，默认 ⌃⇧V。
    static let stackPaste = Self("hotkey.stackPaste", default: .init(.v, modifiers: [.control, .shift]))
}

/// KeyboardShortcuts 的薄封装（02 §2 System）。注册全局热键、绑定动作回调。
/// 动作在按下时于主线程调用。
@MainActor
final class HotkeyCenter {
    /// 绑定唤出热键（⌥V）动作。T1.2 会把它接到 PanelController.toggle。
    func setSummonHandler(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .summon, action: handler)
    }

    /// 绑定拆词热键（⌥X）动作（ChopOverlay 入口 B / 全局，属 B 线）。
    func setChopHandler(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .chop, action: handler)
    }
}
