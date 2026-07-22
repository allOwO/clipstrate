import AppKit

/// 应用生命周期与顶层持有者。持有唯一的 `StatusItemController`（菜单栏图标）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 与 LSUIElement 双保险：无 Dock 图标、不抢激活态。
        NSApp.setActivationPolicy(.accessory)

        // 设置项默认值必须在任何读取之前注册（02 §5 基线）。
        Settings.registerDefaults()

        statusItemController = StatusItemController()

        Log.app.info("ChopClip launched (v\(Bundle.main.shortVersion, privacy: .public))")
    }
}
