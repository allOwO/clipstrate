import AppKit

/// 应用生命周期与顶层持有者。持有唯一的 `StatusItemController`（菜单栏图标）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    // 采集链路（M1 面板/Popover 会复用 historyStore）。
    private var historyStore: HistoryStore?
    private var blobStore: BlobStore?
    private var clipboardMonitor: ClipboardMonitor?
    private var onboardingController: OnboardingController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 与 LSUIElement 双保险：无 Dock 图标、不抢激活态。
        NSApp.setActivationPolicy(.accessory)

        // 设置项默认值必须在任何读取之前注册（02 §5 基线）。
        Settings.registerDefaults()

        statusItemController = StatusItemController()
        startCapture()

        if !Settings.onboardingDone {
            showOnboarding()
        }
        refreshAttention()

        Log.app.info("ChopClip launched (v\(Bundle.main.shortVersion, privacy: .public))")
    }

    /// 打开历史库与 blob 存储并启动剪贴板轮询。任一步失败仅记录降级，不崩溃。
    private func startCapture() {
        do {
            let store = try HistoryStore.makeDefault()
            let blobs = try BlobStore.makeDefault()
            let monitor = ClipboardMonitor(store: store, blobs: blobs)
            historyStore = store
            blobStore = blobs
            clipboardMonitor = monitor
            Task { await monitor.start() }
        } catch {
            Log.app.error("capture 初始化失败：\(String(describing: error), privacy: .public)")
        }
    }

    private func showOnboarding() {
        let controller = OnboardingController { [weak self] in
            Settings.setOnboardingDone(true)
            self?.refreshAttention()
            self?.onboardingController = nil
        }
        onboardingController = controller
        controller.show()
    }

    /// 权限齐全则去掉黄点，缺失则标黄点（01 §8）。
    private func refreshAttention() {
        let ok = PrivacyGate.isPasteboardAllowed && AXPermission.isTrusted
        statusItemController?.setNeedsAttention(!ok)
    }
}
