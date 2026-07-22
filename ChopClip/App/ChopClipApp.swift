import SwiftUI

/// App 入口。ChopClip 是无 Dock 图标的菜单栏常驻 App（`LSUIElement`），
/// 不拥有主窗口——生命周期与状态栏图标都在 `AppDelegate` 里。
@main
struct ChopClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Agent App：没有 WindowGroup。`Settings` 场景只用来接系统 “设置…”
        // 命令；真正的设置窗口是独立 NSWindow（见 02 §6），由后续任务交付。
        // 这里限定 `SwiftUI.Settings` 以避开本模块的 `Settings`（Shared）同名类型。
        SwiftUI.Settings { EmptyView() }
    }
}
