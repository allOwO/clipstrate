import AppKit
import SwiftUI

/// 承载 Onboarding 的标准窗口（02 §6：居中、完成后释放）。窗口关闭（完成/跳过/点 X）
/// 统一经 `windowWillClose` 触发一次 `onComplete`（写 onboarding.done 由回调方处理）。
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var didComplete = false
    private let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        super.init()
    }

    func show() {
        let model = OnboardingModel()
        let root = OnboardingView(model: model) { [weak self] in
            self?.window?.close()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.styleMask = [.titled, .closable]
        window.title = "欢迎使用 Clipstrate"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        // Agent App 平时不激活；引导是前台设置动作，临时激活让窗口可交互。
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Log.app.info("onboarding shown")
    }

    func windowWillClose(_ notification: Notification) {
        guard !didComplete else { return }
        didComplete = true
        window = nil
        onComplete()
        Log.app.info("onboarding finished")
    }
}
