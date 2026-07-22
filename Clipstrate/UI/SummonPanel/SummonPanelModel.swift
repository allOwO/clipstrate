import Combine
import SwiftUI

/// 卡片条的轻量 UI 状态。数据库读取保持 async；面板唤出只展示已预热的快照并触发刷新。
@MainActor
final class SummonPanelModel: ObservableObject {
    @Published private(set) var items: [ClipItem]
    @Published private(set) var selectedIndex = 0
    @Published private(set) var focus: SummonPanelFocus = .card
    @Published private(set) var presentationEpoch = 0
    @Published private(set) var isPanelPresented = false
    @Published private(set) var overlayView: AnyView?

    var onLayoutChange: (() -> Void)?
    let blobStore: BlobStore?

    private let historyStore: HistoryStore?
    private var overlayBuilder: ChopOverlayBuilder?
    private var pasteHandler: SummonPasteHandler?
    private var refreshTask: Task<Void, Never>?

    init(
        historyStore: HistoryStore?,
        blobStore: BlobStore? = nil,
        overlayBuilder: ChopOverlayBuilder? = nil,
        pasteHandler: SummonPasteHandler? = nil,
        initialItems: [ClipItem] = []
    ) {
        self.historyStore = historyStore
        self.blobStore = blobStore
        self.overlayBuilder = overlayBuilder
        self.pasteHandler = pasteHandler
        items = Array(initialItems.prefix(SummonPanelLayout.maximumItemCount))
    }

    func prewarm() {
        refresh()
    }

    func beginPresentation() {
        selectedIndex = 0
        focus = .card
        isPanelPresented = true
        presentationEpoch &+= 1
        refresh()
    }

    func endPresentation() {
        isPanelPresented = false
        dismissOverlay()
    }

    func setOverlayBuilder(_ builder: @escaping ChopOverlayBuilder) {
        overlayBuilder = builder
    }

    func setPasteHandler(_ handler: @escaping SummonPasteHandler) {
        pasteHandler = handler
    }

    /// 返回 true 表示该键已由面板消费；卡片层的 esc 返回 false，由 Controller 关闭面板。
    @discardableResult
    func handle(_ command: SummonPanelCommand) -> Bool {
        if overlayView != nil {
            if command == .escape {
                dismissOverlay()
                return true
            }
            // 分词层拥有自己的键盘状态机；除 esc 返回外，把事件交给其 responder。
            return false
        }

        if command == .escape {
            if focus != .card {
                focus = .card
                return true
            }
            return false
        }

        guard !items.isEmpty else { return true }
        switch command {
        case .moveLeft:
            moveSelection(by: -1)
        case .moveRight:
            moveSelection(by: 1)
        case .moveDown:
            cycleActionFocus(forward: true)
        case .moveUp:
            cycleActionFocus(forward: false)
        case .activate:
            performFocusedAction()
        case .activatePlainText:
            pasteSelected(plainText: true)
        case .openChop:
            presentSelectedChopOverlay()
        case .escape:
            break
        }
        return true
    }

    func activateCard(at index: Int) {
        guard items.indices.contains(index) else { return }
        if index == selectedIndex {
            focus = .card
            pasteSelected(plainText: false)
        } else {
            selectedIndex = index
            focus = .card
        }
    }

    func activateAction(_ index: Int) {
        guard selectedItem?.kind == .text, (0...1).contains(index) else { return }
        focus = .action(index)
        index == 0 ? pasteSelected(plainText: true) : presentSelectedChopOverlay()
    }

    func presentChopOverlay(for item: ClipItem) {
        guard item.kind == .text, !(item.plainText ?? "").isEmpty, let overlayBuilder else { return }
        overlayView = overlayBuilder(ChopOverlayRequest(item: item)) { [weak self] in
            Task { @MainActor [weak self] in self?.dismissOverlay() }
        }
        onLayoutChange?()
    }

    func dismissOverlay() {
        guard overlayView != nil else { return }
        overlayView = nil
        focus = .card
        onLayoutChange?()
    }

    func tearDown() {
        refreshTask?.cancel()
        refreshTask = nil
        onLayoutChange = nil
    }

    private func refresh() {
        guard let historyStore else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self, historyStore] in
            do {
                let page = try await historyStore.page(limit: SummonPanelLayout.maximumItemCount)
                guard !Task.isCancelled, let self else { return }
                let previousCount = items.count
                items = page
                selectedIndex = min(selectedIndex, max(0, page.count - 1))
                if previousCount != page.count { onLayoutChange?() }
            } catch is CancellationError {
                return
            } catch {
                Log.panel.error("加载面板历史失败：\(String(describing: error), privacy: .public)")
            }
        }
    }

    private var selectedItem: ClipItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    private func moveSelection(by delta: Int) {
        selectedIndex = (selectedIndex + delta + items.count) % items.count
        focus = .card
    }

    private func cycleActionFocus(forward: Bool) {
        guard selectedItem?.kind == .text else { return }
        switch (focus, forward) {
        case (.card, true): focus = .action(0)
        case (.action(0), true): focus = .action(1)
        case (.action, true): focus = .card
        case (.card, false): focus = .action(1)
        case (.action(1), false): focus = .action(0)
        case (.action, false): focus = .card
        }
    }

    private func performFocusedAction() {
        switch focus {
        case .card:
            pasteSelected(plainText: false)
        case .action(0):
            pasteSelected(plainText: true)
        case .action:
            presentSelectedChopOverlay()
        }
    }

    private func pasteSelected(plainText: Bool) {
        guard let item = selectedItem else { return }
        if plainText, item.kind != .text { return }
        pasteHandler?(item, plainText)
    }

    private func presentSelectedChopOverlay() {
        guard let item = selectedItem else { return }
        presentChopOverlay(for: item)
    }
}
