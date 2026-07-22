import AppKit
import ApplicationServices

/// 取文本光标屏幕矩形（AX），用于把唤出面板定位到插入点（01 §3.1）。
/// 划词取「选中文本」（入口 C）属 T2.6，本类先只做 caretRect。
@MainActor
enum SelectionGrabber {
    // kAX* 常量为导入的 C 全局 var，在 Swift 6 strict concurrency 下被判为共享可变状态；
    // 用其稳定字面值规避（值即 API 契约）。
    private static let axFocusedUIElement = "AXFocusedUIElement"
    private static let axSelectedTextRange = "AXSelectedTextRange"
    private static let axBoundsForRange = "AXBoundsForRange"

    /// 文本插入点的屏幕矩形（Cocoa 坐标，bottom-left 原点）。无权限 / 取不到时 nil。
    static func caretRect() -> CGRect? {
        guard AXPermission.isTrusted else { return nil }
        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, axFocusedUIElement as CFString, &focusedRef) == .success,
              let focusedRef else { return nil }
        let element = focusedRef as! AXUIElement

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, axSelectedTextRange as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, axBoundsForRange as CFString, rangeRef, &boundsRef) == .success,
              let boundsRef else { return nil }

        var quartzRect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &quartzRect) else { return nil }

        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first else {
            return nil
        }
        return Self.flipY(quartz: quartzRect, primaryHeight: primary.frame.height)
    }

    /// Quartz 全局坐标（top-left 原点，y 向下）→ Cocoa（bottom-left，y 向上）。纯函数，便于单测。
    nonisolated static func flipY(quartz q: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: q.minX, y: primaryHeight - q.maxY, width: q.width, height: q.height)
    }
}
