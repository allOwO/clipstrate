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
    private var backupService: BackupService?
    private var janitorTask: Task<Void, Never>?
    private var onboardingController: OnboardingController?
    private let hotkeyCenter = HotkeyCenter()
    private let loginItemManager: any LoginItemManaging = SystemLoginItemManager()
    private var panelController: PanelController?
    private var popoverController: PopoverController?
    private var pasteService: PasteService?
    private var entityHUDController: EntityHUDController?
    // 〔P1〕忽略名单与堆栈（01 §7.3 / §10）。
    let ignoreListStore = IgnoreListStore.makeDefault()
    private let clipboardStack = ClipboardStack()
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 与 LSUIElement 双保险：无 Dock 图标、不抢激活态。
        NSApp.setActivationPolicy(.accessory)

        // 设置项默认值必须在任何读取之前注册（02 §5 基线）。
        Settings.registerDefaults()
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            synchronizeLaunchAtLogin()
        }

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
                // 面板是 key window：要自动粘贴，须先收起面板把 key 焦点交回原 App，
                // 否则合成的 ⌘V 会落在面板上（只复制不粘）。
                let willPaste = action == .paste && AXPermission.isTrusted
                if willPaste {
                    panel?.hideImmediately()
                    try? await Task.sleep(for: .milliseconds(60))   // 等原 App 重新激活、焦点归位
                } else {
                    panel?.hide()
                }
                let result = await paste.perform(
                    item: item,
                    plainText: plainText || Settings.plainTextDefault,
                    action: action
                )
                switch result {
                case .copiedNeedsManualPaste: ToastPresenter.shared.show("已复制，请 ⌘V 粘贴")
                case .copied: ToastPresenter.shared.show("已复制 ✓")
                case .unavailable: ToastPresenter.shared.show("无法粘贴该条目")
                case .pasted: break
                }
            }
        }

        // 分词层（B 线 ChopOverlay）挂载到面板 overlay 槽位；副作用注入到 UI/System 边界。
        let chopActions = ChopOverlayActions(
            copyText: { [weak paste] text in paste?.copyPlainText(text) },
            pasteText: { [weak paste] text in paste?.pastePlainText(text) },
            showToast: { text in ToastPresenter.shared.show(text) }
        )
        panel.setChopOverlayBuilder(ChopOverlayFactory.makeBuilder(actions: chopActions))

        // EntityHUD（入口 B，01 §4.1）：复制含实体文本 → 右上角胶囊；⌥X 全局展开分词层。
        let hud = EntityHUDController { [weak panel] payload in
            panel?.presentChopOverlay(for: payload.item)
        }
        entityHUDController = hud
        hotkeyCenter.setChopHandler { [weak hud] in hud?.expandIfVisible() }

        // 〔P1〕堆栈：⌃⇧C 开关、⌃⇧V 弹栈顶并粘贴（01 §10）。
        hotkeyCenter.setStackToggleHandler { [weak self] in self?.toggleStack() }
        hotkeyCenter.setStackPasteHandler { [weak self] in self?.popStackAndPaste() }

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
            let monitor = ClipboardMonitor(
                store: store,
                blobs: blobs,
                onCapture: { [weak self] item in
                    Task { @MainActor in self?.handleCaptured(item) }
                },
                isIgnored: { [ignoreListStore] bundleID in
                    (try? await ignoreListStore.contains(bundleIdentifier: bundleID)) ?? false
                }
            )
            let janitor = RetentionJanitor(store: store, blobs: blobs)
            historyStore = store
            blobStore = blobs
            clipboardMonitor = monitor
            retentionJanitor = janitor
            backupService = BackupService(
                historyStore: store,
                blobStore: blobs,
                ignoreListStore: ignoreListStore
            )
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
        entityHUDController?.dismiss()
        ToastPresenter.shared.tearDown()
    }

    /// 堆栈开启时入栈（enqueue 内部判 enabled）；文本条目再做实体检测弹 EntityHUD（01 §4.1 B / §10）。
    private func handleCaptured(_ item: ClipItem) {
        Task { [clipboardStack] in await clipboardStack.enqueue(item) }
        guard item.kind == .text, let text = item.plainText, !text.isEmpty else { return }
        Task { @MainActor [weak self] in
            let entities = await Task.detached(priority: .utility) {
                EntityDetector().entities(in: text)
            }.value
            guard !entities.isEmpty, let self else { return }
            self.entityHUDController?.show(item: item, entities: entities)
        }
    }

    /// 打开通铺式设置窗口（单例复用）。备份区属 M4，先以占位动作接线。
    private func openSettings() {
        if settingsWindowController == nil {
            let actions = SettingsActions(
                settingChanged: { key in Log.app.debug("setting changed: \(key, privacy: .public)") },
                backupState: .unavailable,
                backupNow: { ToastPresenter.shared.show("云备份即将推出") },
                restoreFromCloud: { ToastPresenter.shared.show("云备份即将推出") },
                importBackup: { [weak self] in self?.chooseBackupToImport() },
                exportBackup: { [weak self] in self?.chooseBackupDestination() }
            )
            settingsWindowController = SettingsWindowController(
                actions: actions,
                loginItemManager: loginItemManager,
                ignoreListStore: ignoreListStore
            )
        }
        settingsWindowController?.show()
    }

    private func chooseBackupDestination() {
        guard let backupService else {
            ToastPresenter.shared.show("历史库不可用，无法导出")
            return
        }
        let panel = NSSavePanel()
        panel.title = "导出 Clipstrate 备份"
        panel.nameFieldStringValue = Self.backupFilename()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let selection = BackupSelection.currentSettings
        Task { @MainActor in
            do {
                try await backupService.exportArchive(
                    to: destination,
                    selection: selection
                )
                ToastPresenter.shared.show("备份已导出 ✓")
            } catch {
                ToastPresenter.shared.show(error.localizedDescription)
                Log.store.error("导出备份失败：\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func chooseBackupToImport() {
        guard let backupService else {
            ToastPresenter.shared.show("历史库不可用，无法导入")
            return
        }
        let panel = NSOpenPanel()
        panel.title = "导入 Clipstrate 备份"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let source = panel.url else { return }
        guard source.pathExtension.lowercased() == "clipstrate" else {
            ToastPresenter.shared.show("请选择 .clipstrate 备份文件")
            return
        }

        let confirmation = NSAlert()
        confirmation.messageText = "导入此备份？"
        confirmation.informativeText = "设置和忽略名单将覆盖当前值；剪贴板历史会按内容去重合并。"
        confirmation.alertStyle = .warning
        confirmation.addButton(withTitle: "导入")
        confirmation.addButton(withTitle: "取消")
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor [weak self] in
            do {
                let result = try await backupService.importArchive(from: source)
                if let enabled = result.requestedLaunchAtLogin, let self {
                    try self.loginItemManager.setEnabled(enabled)
                    Settings.setLaunchAtLogin(self.loginItemManager.state.isSelected)
                }
                let inserted = result.history.insertedCount
                let duplicates = result.history.duplicateCount
                ToastPresenter.shared.show("导入完成：新增 \(inserted) 条，跳过 \(duplicates) 条重复")
            } catch {
                ToastPresenter.shared.show(error.localizedDescription)
                Log.store.error("导入备份失败：\(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func backupFilename(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return "Clipstrate-backup-\(formatter.string(from: now)).clipstrate"
    }

    private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel()
    }

    /// 首次启动应用规格默认值；之后始终以系统登录项状态为准，
    /// 避免 UserDefaults 显示“开”而 SMAppService 实际未注册。
    private func synchronizeLaunchAtLogin() {
        if !Settings.hasPersistedLaunchAtLoginPreference {
            do {
                try loginItemManager.setEnabled(true)
            } catch {
                Log.app.error("默认注册登录项失败：\(String(describing: error), privacy: .public)")
            }
        }
        Settings.setLaunchAtLogin(loginItemManager.state.isSelected)
    }

    private func toggleStack() {
        Task { [clipboardStack] in
            let state = await clipboardStack.toggle()
            ToastPresenter.shared.show(state.isEnabled ? "堆栈已开启" : "堆栈已关闭")
        }
    }

    private func popStackAndPaste() {
        Task { @MainActor [weak self, clipboardStack] in
            guard let item = await clipboardStack.dequeue() else {
                ToastPresenter.shared.show("堆栈为空")
                return
            }
            guard let paste = self?.pasteService else { return }
            _ = await paste.perform(item: item, plainText: Settings.plainTextDefault, action: .paste)
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
