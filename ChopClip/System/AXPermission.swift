import AppKit
import ApplicationServices

/// 辅助功能（Accessibility）授权。用于自动粘贴 ⌘V（CGEvent）、光标定位、划词（AX）。
/// 非 macOS-26-only API（10.9+），不属兼容接缝。
enum AXPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 弹出系统辅助功能授权提示（不阻塞；用户在系统设置里勾选后 isTrusted 变 true）。
    static func promptIfNeeded() {
        // 直接用常量值字面量：导入的 C 全局 `kAXTrustedCheckOptionPrompt` 在 Swift 6
        // strict concurrency 下被判为共享可变状态而报错；其值恒为该字符串。
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 直接打开「系统设置 › 隐私与安全性 › 辅助功能」。
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
