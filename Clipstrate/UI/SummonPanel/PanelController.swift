import AppKit
import SwiftUI

/// 唤出面板的唯一持有者与控制器（02 §6、01 §3.1）。启动即创建并常驻隐藏（预热），
/// 唤出仅定位 + orderFrontRegardless + makeKey（不激活 App、不抢焦点）。
/// esc / 点击面板外 / 失焦 / 再按 ⌥V 关闭。键盘两层焦点属 T1.4，本任务只处理 esc。
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: SummonPanel
    private var localKeyMonitor: Any?
    private var globalClickMonitor: Any?
    private(set) var isVisible = false

    override init() {
        panel = SummonPanel(
            contentRect: NSRect(origin: .zero, size: SummonPanelView.placeholderSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.level = .floating
        panel.isMovable = false
        panel.isReleasedWhenClosed = false          // 复用不重建（零泄露清单）
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                      // 玻璃自带阴影
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: SummonPanelView())
        // 预热：先离屏渲染一次，唤出时只需定位 + 前置
        panel.orderOut(nil)
    }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard !isVisible else { return }
        let signpost = Log.signposter.beginInterval("summon.show")
        defer { Log.signposter.endInterval("summon.show", signpost) }

        positionPanel()
        panel.orderFrontRegardless()
        panel.makeKey()                              // 接收键盘但不激活 App
        installMonitors()
        isVisible = true
        Log.panel.info("summon panel shown")
    }

    func hide() {
        guard isVisible else { return }
        removeMonitors()
        panel.orderOut(nil)
        isVisible = false
    }

    // MARK: - 定位

    private func positionPanel() {
        let anchor = SelectionGrabber.caretRect()
            ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let frame = PanelPlacement.frame(
            panelSize: panel.frame.size,
            anchor: anchor,
            gap: DS.Metrics.caretGap,
            visibleFrame: visibleFrame
        )
        panel.setFrame(frame, display: false)
    }

    // MARK: - 监听器（成对安装/移除，零泄露清单）

    private func installMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {                 // esc
                self.hide()
                return nil
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeMonitors() {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localKeyMonitor = nil
        globalClickMonitor = nil
    }

    // MARK: - 失焦即关

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
