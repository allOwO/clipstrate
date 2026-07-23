import AppKit
import SwiftUI

/// 唤出面板的唯一持有者与控制器（02 §6、01 §3.1）。启动即创建并常驻隐藏（预热），
/// 唤出仅定位 + orderFrontRegardless + makeKey（不激活 App、不抢焦点）。
/// esc / 点击面板外 / 失焦 / 再按 ⌥V 关闭。键盘两层焦点属 T1.4，本任务只处理 esc。
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: SummonPanel
    private let model: SummonPanelModel
    private var localKeyMonitor: Any?
    private var globalClickMonitor: Any?
    private var hideTask: Task<Void, Never>?
    private var placementAnchor: CGRect?
    private(set) var isVisible = false

    override convenience init() {
        self.init(historyStore: nil, blobStore: nil, chopOverlayBuilder: nil)
    }

    init(historyStore: HistoryStore?, blobStore: BlobStore? = nil, chopOverlayBuilder: ChopOverlayBuilder?) {
        model = SummonPanelModel(
            historyStore: historyStore,
            blobStore: blobStore,
            overlayBuilder: chopOverlayBuilder
        )
        let initialSize = SummonPanelLayout.panelSize(
            itemCount: 0,
            availableWidth: NSScreen.main?.visibleFrame.width ?? SummonPanelLayout.minimumPanelWidth
        )
        panel = SummonPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
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
        panel.contentView = NSHostingView(rootView: SummonPanelView(model: model))
        model.onLayoutChange = { [weak self] in self?.updateLayout() }
        model.onIMEInputRequested = { [weak self] in self?.activateIMEInput() }
        model.onRequestClose = { [weak self] in self?.hide() }
        model.prewarm()
        // 预热：先离屏渲染一次，唤出时只需定位 + 前置
        panel.orderOut(nil)
    }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard !isVisible else { return }
        hideTask?.cancel()
        hideTask = nil
        let signpost = Log.signposter.beginInterval("summon.show")
        defer { Log.signposter.endInterval("summon.show", signpost) }

        model.beginPresentation()
        placementAnchor = SelectionGrabber.caretRect()
            ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        updateLayout()
        panel.orderFrontRegardless()
        panel.makeKey()                              // 接收键盘但不激活 App
        installMonitors()
        isVisible = true
        Log.panel.info("summon panel shown")
    }

    func hide() {
        guard isVisible else { return }
        removeMonitors()
        isVisible = false
        model.endPresentation()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(DS.Anim.closeDuration))
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    func setChopOverlayBuilder(_ builder: @escaping ChopOverlayBuilder) {
        model.setOverlayBuilder(builder)
    }

    /// 全局 ⌥X（EntityHUD 展开，01 §4.1 B）：显示面板并直接挂上该条目的分词层。
    func presentChopOverlay(for item: ClipItem) {
        if !isVisible { show() }
        model.presentChopOverlay(for: item)
    }

    func setPasteHandler(_ handler: @escaping SummonPasteHandler) {
        model.setPasteHandler(handler)
    }

    /// App 终止时显式拆除监听器与异步任务（零泄露清单）。
    func tearDown() {
        removeMonitors()
        hideTask?.cancel()
        hideTask = nil
        model.tearDown()
        panel.orderOut(nil)
        isVisible = false
    }

    // MARK: - 定位

    private func updateLayout() {
        let anchor = placementAnchor
            ?? SelectionGrabber.caretRect()
            ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let panelSize = SummonPanelLayout.panelSize(
            itemCount: model.items.count,
            selectedIndex: model.selectedIndex,
            availableWidth: visibleFrame.width,
            overlayPresented: model.overlayView != nil,
            searching: model.isSearching
        )
        let frame = PanelPlacement.frame(
            panelSize: panelSize,
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
            return self.handleKeyDown(event)
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let command = Self.command(for: event)

        // IME 态（搜索框聚焦，接管中文输入）：仅 esc 由面板处理（降级回全量）；
        // 其余键交给搜索框（含输入法组合与字段内导航）。
        if model.imeInputActive {
            if command == .escape {
                if !model.handle(.escape) { hide() }
                return nil
            }
            return event
        }

        if let command {
            let consumed = model.handle(command)
            if command == .escape, !consumed { hide(); return nil }
            return consumed ? nil : event
        }

        return handleSearchKey(event)
    }

    /// 非 IME 态的搜索输入：`⌫` 删字符、`/` 升级接管输入法、可打印 ASCII 并入查询（01 §3.6）。
    private func handleSearchKey(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 51 {                     // delete / backspace
            return model.deleteSearchCharacter() ? nil : event
        }
        if event.charactersIgnoringModifiers == "/" {
            model.beginIMEInput()
            return nil
        }
        guard let characters = event.characters, characters.count == 1,
              let character = characters.first, character.isASCII,
              character.isLetter || character.isNumber || character.isPunctuation
                || character.isSymbol || character == " " else {
            return event
        }
        model.appendSearchCharacter(character)
        return nil
    }

    /// 输入法组合需要应用处于激活态，并由承载 TextField 的 panel 保持 key。
    /// `/` 与点击搜索胶囊统一走这里，避免鼠标入口只改状态却没有可输入窗口。
    private func activateIMEInput() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func removeMonitors() {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localKeyMonitor = nil
        globalClickMonitor = nil
    }

    private static func command(for event: NSEvent) -> SummonPanelCommand? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return SummonKeyMap.command(
            keyCode: event.keyCode,
            option: flags.contains(.option),
            command: flags.contains(.command),
            digitModifier: Settings.digitModifier
        )
    }

    // MARK: - 失焦即关

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

}
