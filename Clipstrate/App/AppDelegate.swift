import AppKit

/// 应用生命周期与顶层持有者。持有唯一的 `StatusItemController`（菜单栏图标）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    // 采集链路（M1 面板/Popover 会复用 historyStore）。
    private var historyStore: HistoryStore?
    private var blobStore: BlobStore?
    private var clipboardMonitor: ClipboardMonitor?
    private var retentionJanitor: RetentionJanitor?
    private var janitorTask: Task<Void, Never>?
    private var onboardingController: OnboardingController?
    private let hotkeyCenter = HotkeyCenter()
    private var panelController: PanelController?
    private var popoverController: PopoverController?
    private var pasteService: PasteService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 与 LSUIElement 双保险：无 Dock 图标、不抢激活态。
        NSApp.setActivationPolicy(.accessory)

        // 设置项默认值必须在任何读取之前注册（02 §5 基线）。
        Settings.registerDefaults()

        statusItemController = StatusItemController()
        startCapture()

        // 预热唤出面板（常驻隐藏），⌥V 切换显示（不抢焦点）。
        let panel = PanelController(historyStore: historyStore, blobStore: blobStore, chopOverlayBuilder: nil)
        let paste = PasteService(blobStore: blobStore)
        pasteService = paste
        panelController = panel
        hotkeyCenter.setSummonHandler { [weak panel] in panel?.toggle() }
        panel.setPasteHandler { [weak panel, weak paste] item, plainText, source in
            Task { @MainActor [weak panel, weak paste] in
                guard let paste else { return }
                // 数字键走「按下后」设置，⏎/点击走「双击/回车」设置（01 §3.5）。
                let action = source == .press ? Settings.pressAction : Settings.returnAction
                let result = await paste.perform(
                    item: item,
                    plainText: plainText || Settings.plainTextDefault,
                    action: action
                )
                if result.didWritePasteboard, Settings.autoClose { panel?.hide() }
                switch result {
                case .copiedNeedsManualPaste: ToastPresenter.shared.show("已复制，请 ⌘V 粘贴")
                case .copied: ToastPresenter.shared.show("已复制 ✓")
                case .unavailable: ToastPresenter.shared.show("无法粘贴该条目")
                case .pasted: break
                }
            }
        }

        // 菜单栏 Popover：左键图标弹出，右键弹菜单（设置…/关于/退出）。
        let popover = PopoverController(historyStore: historyStore, blobStore: blobStore)
        popoverController = popover
        statusItemController?.onLeftClick = { [weak popover] button in popover?.toggle(relativeTo: button) }
        statusItemController?.onSettings = { [weak self] in self?.openSettings() }
        statusItemController?.onAbout = { [weak self] in self?.openAbout() }
        popover.onSettings = { [weak self] in self?.openSettings() }
        popover.onAbout = { [weak self] in self?.openAbout() }
        popover.setCopyHandler { [weak paste] item in
            Task { @MainActor [weak paste] in
                guard let paste else { return }
                // 点击条目 = 复制到剪贴板顶部（仅复制，不合成 ⌘V）。
                let result = await paste.perform(item: item, plainText: Settings.plainTextDefault, action: .copy)
                switch result {
                case .copied, .pasted: ToastPresenter.shared.show("已复制 ✓")
                case .unavailable, .copiedNeedsManualPaste: ToastPresenter.shared.show("无法复制该条目")
                }
            }
        }

        if !Settings.onboardingDone {
            showOnboarding()
        }
        refreshAttention()

        Log.app.info("Clipstrate launched (v\(Bundle.main.shortVersion, privacy: .public))")
    }

    /// 打开历史库与 blob 存储并启动剪贴板轮询。任一步失败仅记录降级，不崩溃。
    private func startCapture() {
        do {
            let store = try HistoryStore.makeDefault()
            let blobs = try BlobStore.makeDefault()
            let monitor = ClipboardMonitor(store: store, blobs: blobs)
            let janitor = RetentionJanitor(store: store, blobs: blobs)
            historyStore = store
            blobStore = blobs
            clipboardMonitor = monitor
            retentionJanitor = janitor
            Task { await monitor.start() }
            startJanitor(janitor)
        } catch {
            Log.app.error("capture 初始化失败：\(String(describing: error), privacy: .public)")
        }
    }

    /// 启动即清一次，之后每小时一次（01 §2）。
    private func startJanitor(_ janitor: RetentionJanitor) {
        janitorTask = Task {
            while !Task.isCancelled {
                do { try await janitor.runOnce() }
                catch { Log.store.error("retention 清理失败：\(String(describing: error), privacy: .public)") }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        janitorTask?.cancel()
        janitorTask = nil
        panelController?.tearDown()
        popoverController?.tearDown()
        ToastPresenter.shared.tearDown()
    }

    // 设置窗口属 B 线（UI/Settings/）、关于页属 T4.2，尚未并入 main：先给占位反馈。
    private func openSettings() { ToastPresenter.shared.show("设置即将推出") }
    private func openAbout() { ToastPresenter.shared.show("关于即将推出") }

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
