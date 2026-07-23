import AppKit

/// 菜单栏状态项的唯一持有者。左键单击 → Popover 主界面；右键 / ⌃点击 → 最小菜单
/// （设置… / 关于 / 退出）。退出是唯一入口，必须有（01 §5）。
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private var attentionDot: CALayer?

    /// 左键点击回调（弹 Popover，传状态项按钮作锚点）。
    var onLeftClick: ((NSStatusBarButton) -> Void)?
    var onSettings: () -> Void = {}
    var onAbout: () -> Void = {}

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        configureButton()
        configureMenu()
    }

    /// 权限缺失时在图标右上角标黄点（01 §8）。保持底图为模板图以正确适配深浅色，
    /// 黄点用彩色 layer 叠加。
    func setNeedsAttention(_ on: Bool) {
        guard let button = statusItem.button else { return }
        if on {
            button.wantsLayer = true
            let dot = attentionDot ?? CALayer()
            let size: CGFloat = 5
            let bounds = button.bounds
            dot.frame = CGRect(x: bounds.maxX - size - 1, y: bounds.maxY - size - 2,
                               width: size, height: size)
            dot.cornerRadius = size / 2
            dot.backgroundColor = NSColor.systemYellow.cgColor
            if attentionDot == nil {
                button.layer?.addSublayer(dot)
                attentionDot = dot
            }
        } else {
            attentionDot?.removeFromSuperlayer()
            attentionDot = nil
        }
    }

    // 状态项随 App 生命周期常驻，由 AppDelegate 单一持有；App 退出时系统回收，
    // 故不在 deinit 里调用 removeStatusItem（避免 @MainActor 隔离下的清理歧义）。

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(named: "StatusIcon") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            button.image = image
            button.setAccessibilityLabel("Clipstrate")
        } else if let image = NSImage(systemSymbolName: "list.clipboard",
                                      accessibilityDescription: "Clipstrate") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "CC"
        }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        let about = NSMenuItem(title: "关于 Clipstrate", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        let quit = NSMenuItem(title: "退出 Clipstrate",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(settings)
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(quit)
    }

    @objc private func handleClick() {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        if isRight {
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: button.bounds.height + 4),
                       in: button)
        } else {
            onLeftClick?(button)
        }
    }

    @objc private func openSettings() { onSettings() }
    @objc private func openAbout() { onAbout() }
}
