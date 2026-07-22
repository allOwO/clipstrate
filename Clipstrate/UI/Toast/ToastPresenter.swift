import AppKit
import SwiftUI

@MainActor
final class ToastModel: ObservableObject {
    @Published var message = ""
}

private struct ToastView: View {
    @ObservedObject var model: ToastModel

    var body: some View {
        Text(model.message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .fixedSize()
            .glassSurface(cornerRadius: 999)
    }
}

/// 底部居中的玻璃提示胶囊（01 §9）：非激活、不拦截点击、单一持有者复用一个 NSPanel，
/// 默认 1.4s 自动消失。用于「已复制，请 ⌘V 粘贴」等反馈。
@MainActor
final class ToastPresenter {
    static let shared = ToastPresenter()

    private let panel: NSPanel
    private let model = ToastModel()
    private var dismissTask: Task<Void, Never>?

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isReleasedWhenClosed = false           // 复用不重建（零泄露清单）
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                       // 玻璃自带阴影
        panel.ignoresMouseEvents = true               // 纯提示，不拦截点击
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: ToastView(model: model))
        panel.orderOut(nil)
    }

    func show(_ message: String, duration: Double = 1.4) {
        model.message = message
        guard let host = panel.contentView else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let origin = CGPoint(x: visibleFrame.midX - size.width / 2,
                             y: visibleFrame.minY + 96)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()                  // 不激活、不抢焦点

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    /// App 终止时显式拆除（零泄露清单）。
    func tearDown() {
        dismissTask?.cancel()
        dismissTask = nil
        panel.orderOut(nil)
    }
}
