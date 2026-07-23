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

    // 面板内搜索（type-to-search，01 §3.6）
    @Published private(set) var searchQuery = ""
    @Published private(set) var matchCount = 0
    /// `/` 或点击搜索胶囊后升级为 key window 接管输入法（中文）——绑定搜索框焦点。
    @Published var imeInputActive = false

    var isSearching: Bool { imeInputActive || !searchQuery.isEmpty }

    var onLayoutChange: (() -> Void)?
    /// 分词层完成（复制 / 复制并粘贴 / 返回）时请求关闭整个面板（01 §4.3）。
    var onRequestClose: (() -> Void)?
    let blobStore: BlobStore?

    private let historyStore: HistoryStore?
    private var overlayBuilder: ChopOverlayBuilder?
    private var pasteHandler: SummonPasteHandler?
    private var refreshTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

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
        resetSearchState()
        refresh()
    }

    func endPresentation() {
        isPanelPresented = false
        dismissOverlay()
        resetSearchState()
    }

    private func resetSearchState() {
        searchTask?.cancel()
        searchTask = nil
        searchQuery = ""
        imeInputActive = false
        matchCount = 0
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
            // 两段式 esc（01 §3.6）：先清空搜索回全量，再关面板。
            if isSearching {
                exitSearch()
                return true
            }
            return false
        }

        // 搜索态下裸数字并入查询（即使当前无匹配也要能继续输入，须在空 items 判断之前）。
        if case .digit(let oneBased) = command, !searchQuery.isEmpty {
            appendSearchCharacter(Character("\(oneBased)"))
            return true
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
            pasteSelected(plainText: true, source: .return)
        case .openChop:
            presentSelectedChopOverlay()
        case .digit(let oneBased):
            pasteDigit(oneBased)
        case .escape:
            break
        }
        return true
    }

    /// 数字直贴：选中第 N 条并粘贴（走「按下后（数字键）」设置）。越界忽略。
    private func pasteDigit(_ oneBased: Int) {
        let index = oneBased - 1
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        focus = .card
        pasteSelected(plainText: false, source: .press)
    }

    func activateCard(at index: Int) {
        guard items.indices.contains(index) else { return }
        if index == selectedIndex {
            focus = .card
            pasteSelected(plainText: false, source: .return)
        } else {
            selectedIndex = index
            focus = .card
        }
    }

    func activateAction(_ index: Int) {
        guard selectedItem?.kind == .text, (0...1).contains(index) else { return }
        focus = .action(index)
        index == 0 ? pasteSelected(plainText: true, source: .return) : presentSelectedChopOverlay()
    }

    func presentChopOverlay(for item: ClipItem) {
        guard item.kind == .text, !(item.plainText ?? "").isEmpty, let overlayBuilder else { return }
        // overlay 完成（复制/粘贴/返回按钮）→ 关闭整个面板；esc 由面板监听器走 dismissOverlay 回卡片层。
        overlayView = overlayBuilder(ChopOverlayRequest(item: item)) { [weak self] in
            Task { @MainActor [weak self] in self?.onRequestClose?() }
        }
        onLayoutChange?()
    }

    func dismissOverlay() {
        guard overlayView != nil else { return }
        overlayView = nil
        focus = .card
        onLayoutChange?()
    }

    // MARK: - 面板内搜索（01 §3.6）

    /// ASCII 快速搜索：keyDown 直接并入查询字符。
    func appendSearchCharacter(_ character: Character) {
        searchQuery.append(character)
        scheduleFilter()
        onLayoutChange?()
    }

    /// TextField 绑定（IME 态：中文经 `/` 升级后由搜索框驱动查询）。
    func setSearchQuery(_ text: String) {
        guard text != searchQuery else { return }
        searchQuery = text
        scheduleFilter()
        onLayoutChange?()
    }

    /// `⌫`：搜索态下删除一个字符（空查询也消费，不透传）。返回是否已消费。
    @discardableResult
    func deleteSearchCharacter() -> Bool {
        guard isSearching else { return false }
        if !searchQuery.isEmpty {
            searchQuery.removeLast()
            scheduleFilter()
            onLayoutChange?()
        }
        return true
    }

    /// `/` 或点击搜索胶囊：升级接管输入法（中文）。
    func beginIMEInput() {
        guard !imeInputActive else { return }
        imeInputActive = true
        onLayoutChange?()
    }

    /// 退出搜索、回全量（第一次 esc）。
    func exitSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchQuery = ""
        imeInputActive = false
        matchCount = 0
        selectedIndex = 0
        focus = .card
        refresh()
        onLayoutChange?()
    }

    private func scheduleFilter() {
        searchTask?.cancel()
        let query = searchQuery
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await self?.runFilter(query)
        }
    }

    private func runFilter(_ query: String) async {
        guard let historyStore else { return }
        let results: [ClipItem]
        if query.isEmpty {
            results = (try? await historyStore.page(limit: SummonPanelLayout.maximumItemCount)) ?? []
        } else {
            results = (try? await historyStore.search(query, limit: SummonPanelLayout.maximumItemCount)) ?? []
        }
        guard query == searchQuery else { return }   // 期间查询词已变，丢弃过期结果
        items = results
        matchCount = results.count
        selectedIndex = min(selectedIndex, max(0, results.count - 1))
        focus = .card
        onLayoutChange?()
    }

    func tearDown() {
        refreshTask?.cancel()
        refreshTask = nil
        searchTask?.cancel()
        searchTask = nil
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
            pasteSelected(plainText: false, source: .return)
        case .action(0):
            pasteSelected(plainText: true, source: .return)
        case .action:
            presentSelectedChopOverlay()
        }
    }

    private func pasteSelected(plainText: Bool, source: SummonPasteSource) {
        guard let item = selectedItem else { return }
        if plainText, item.kind != .text { return }
        pasteHandler?(item, plainText, source)
    }

    private func presentSelectedChopOverlay() {
        guard let item = selectedItem else { return }
        presentChopOverlay(for: item)
    }
}
