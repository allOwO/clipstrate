import AppKit
import SwiftUI

/// 菜单栏 Popover 的唯一持有者（02 §6：锚定 statusItem 按钮下方的玻璃 NSPanel，
/// 非 NSPopover、无箭头；失焦即关）。预热常驻隐藏，点击图标 toggle。
@MainActor
final class PopoverController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let model: PopoverModel
    private var globalClickMonitor: Any?
    private(set) var isVisible = false

    var onSettings: () -> Void = {}
    var onAbout: () -> Void = {}

    init(historyStore: HistoryStore?, blobStore: BlobStore?) {
        model = PopoverModel(historyStore: historyStore)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: PopoverView.width, height: PopoverView.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.level = .popUpMenu
        panel.isMovable = false
        panel.isReleasedWhenClosed = false           // 复用不重建（零泄露清单）
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self

        let root = PopoverView(
            model: model,
            blobStore: blobStore,
            onSettings: { [weak self] in self?.hide(); self?.onSettings() },
            onAbout: { [weak self] in self?.hide(); self?.onAbout() }
        )
        panel.contentView = NSHostingView(rootView: root)
        panel.orderOut(nil)
    }

    func setCopyHandler(_ handler: @escaping (ClipItem) -> Void) {
        model.onCopy = { [weak self] item in
            handler(item)
            self?.hide()
        }
    }

    /// 点击菜单栏图标：显示则关，隐藏则锚定按钮下方弹出。
    func toggle(relativeTo button: NSStatusBarButton) {
        isVisible ? hide() : show(relativeTo: button)
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard !isVisible, let buttonWindow = button.window else { return }

        // 按钮在屏幕坐标下的 frame，据此把 Popover 顶边对齐按钮下方、右缘对齐。
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = CGPoint(
            x: buttonRect.maxX - PopoverView.width,
            y: buttonRect.minY - PopoverView.height - 6
        )
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - PopoverView.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.makeKey()                              // 允许搜索框接收键盘输入
        installMonitors()
        isVisible = true
    }

    func hide() {
        guard isVisible else { return }
        removeMonitors()
        isVisible = false
        panel.orderOut(nil)
    }

    /// App 终止时显式拆除（零泄露清单）。
    func tearDown() {
        removeMonitors()
        model.tearDown()
        panel.orderOut(nil)
        isVisible = false
    }

    private func installMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeMonitors() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        globalClickMonitor = nil
    }

    // MARK: - 失焦即关

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
