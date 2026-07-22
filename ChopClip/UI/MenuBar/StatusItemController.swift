import AppKit

/// 菜单栏状态项与其右键菜单的唯一持有者。
///
/// T0.1 范围：显示图标 + 一个可退出 App 的菜单。
/// T1.8 会让左键弹出 Popover 主界面，本菜单退居右键使用。
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let menu: NSMenu

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = StatusItemController.makeMenu()
        configureButton()
    }

    // 状态项随 App 生命周期常驻，由 AppDelegate 单一持有；App 退出时系统回收，
    // 故不在 deinit 里调用 removeStatusItem（避免 @MainActor 隔离下的清理歧义）。

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: "list.clipboard",
                               accessibilityDescription: "ChopClip") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "CC"
        }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private static func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let quit = NSMenuItem(title: "退出 ChopClip",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    @objc private func handleClick() {
        // T0.1：左右键都弹出菜单。T1.8 将拆分：左键 → Popover，右键 → 本菜单。
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }
}
