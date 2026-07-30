import AppKit
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
    /// 面板显示期间预先聚焦隐藏输入客户端，中英文都可直接输入。
    @Published var imeInputActive = false

    /// 输入客户端可以常驻准备；只有实际存在查询词时才显示搜索胶囊、进入搜索态。
    var isSearching: Bool { !searchQuery.isEmpty }

    /// 波浪放大状态（「完整特效」）。刻意不并入本 model 的 @Published：指针 120Hz 移动
    /// 只重求值观察它的 waveMagnify 修饰器，不触发面板 body / 卡片内容重算。
    let wave = WaveMagnifyState()

    var onLayoutChange: (() -> Void)?
    /// 由 Controller 完成 App 激活与 panel 置 key；View/Model 不直接操纵窗口。
    var onIMEInputRequested: (() -> Void)?
    /// 分词层完成（复制 / 复制并粘贴 / 返回）时请求关闭整个面板（01 §4.3）。
    var onRequestClose: (() -> Void)?
    let blobStore: BlobStore?

    private let historyStore: HistoryStore?
    private var overlayBuilder: ChopOverlayBuilder?
    private var pasteHandler: SummonPasteHandler?
    private var refreshTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    /// 悬停触发的选中变更只放大、不滚动（见 hoverSelect / shouldAutoScrollToSelection）。
    private var suppressNextAutoScroll = false
    /// 上一次被接受的悬停选择时的指针位置，供 hoverSelect 的位移判据用。
    private var lastHoverLocation: CGPoint?
    /// 滚动进行中：滚动是明确的浏览意图，悬停实时选中；位移判据只在非滚动时生效。
    /// 对外可见（@Published）是因为卡片生长曲线要按它切档：滚动中换卡频率远高于
    /// 生长时长，必须换短曲线才追得上（见 DS.Anim.cardGrowScrolling）。
    /// 只在 idle↔scrolling 翻转时发布，一次手势两次，不是高频源。
    @Published private(set) var isScrolling = false

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

    /// 隐藏期间保持快照新鲜。`show()` 是同步的，`beginPresentation()` 里的 refresh 是
    /// Task，绝不可能在 orderFrontRegardless() 之前落地——所以只在唤出时刷新，等于
    /// 「先按过期快照把面板显示出去，再在用户眼前修正」：条数变了窗口就改尺寸，
    /// contentHash 变了新卡还会重放错开的进场 spring（冷库读盘 200–300ms 时尤其明显，
    /// 复现与机制见 SummonPanelColdSummonDiagTests）。
    /// 捕获新剪贴板 / 清理过期条目之后调用本方法，唤出时的 refresh 就退化成空操作。
    /// 面板可见时不刷：那会让卡片在用户正看着的时候变动。
    func refreshWhileHidden() {
        guard !isPanelPresented else { return }
        refresh()
    }

    func beginPresentation() {
        selectedIndex = 0
        focus = .card
        isPanelPresented = true
        // 面板常出现在光标处，卡片会「自己跑到指针下」；以当前指针位置起算，
        // 唤出瞬间的悬停不算用户意图，默认选中仍是第一条。
        lastHoverLocation = NSEvent.mouseLocation
        isScrolling = false
        presentationEpoch &+= 1
        // 设置与「减弱动态」在唤出时快照；面板显示期间改设置下次唤出生效。
        wave.preparePresentation(enabled: MotionPolicy.fullEffectsActive)
        resetSearchState()
        refresh()
    }

    func endPresentation() {
        isPanelPresented = false
        wave.pointerExited()
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

        // 数字命令只在「数字修饰键」满足时才产生（默认 ⌘+数字）；裸数字已放行给搜索框，
        // 不再走这里。因此 .digit 一律表示「快速粘贴第 N 条」——即便在搜索结果中也快贴当前第 N 条。
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

    /// 单击任意卡片 = 直接粘贴（默认动作，走 returnAction）。不再需要「先选中再点一次」。
    func activateCard(at index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        focus = .card
        pasteSelected(plainText: false, source: .return)
    }

    /// 鼠标悬停即聚焦：把选中切到光标所在卡使其放大，与键盘左右选择齐平。
    /// 悬停触发的变更不自动滚动（滚动只应由键盘导航触发，否则鼠标会追着卡跑）。
    func hoverSelect(at index: Int) {
        guard isPanelPresented, overlayView == nil,
              items.indices.contains(index), index != selectedIndex else { return }
        // 双指滑动时指针不动，卡片从指针下经过一样会触发 onHover——滚动是用户在「扫」
        // 卡片，光标下的卡要实时放大跟手（选中卡宽度 128↔252 切换时下游卡有一次平移，
        // 但被选卡自身尾边不动、指针仍留在卡内，不会连锁振荡）。位移判据只挡非滚动
        // 场景的被动悬停：唤出瞬间面板出现在光标下、刷新重排让卡片滑到指针下。
        let location = NSEvent.mouseLocation
        if !isScrolling, let last = lastHoverLocation,
           abs(last.x - location.x) < 1, abs(last.y - location.y) < 1 {
            return
        }
        lastHoverLocation = location
        suppressNextAutoScroll = true
        selectedIndex = index
        focus = .card
    }

    /// 卡片条滚动相位（onScrollPhaseChange）：滚动中悬停实时选中，这里维护
    /// isScrolling，供 hoverSelect 的位移判据区分「滚动扫卡」与「被动悬停」，
    /// 并给卡片生长切换短曲线（DS.Anim.cardGrowScrolling）。
    func scrollPhaseChanged(isScrolling scrolling: Bool) {
        guard isScrolling != scrolling else { return }   // 等值短路：不给相同相位起发布
        isScrolling = scrolling
    }

    /// 供卡片条 `scrollTo` 判定：消费一次「悬停抑制」标记；hover 触发的选中变更返回 false（不滚动）。
    func shouldAutoScrollToSelection() -> Bool {
        if suppressNextAutoScroll { suppressNextAutoScroll = false; return false }
        return true
    }

    func activateAction(_ index: Int) {
        guard selectedItem?.kind == .text, (0...1).contains(index) else { return }
        focus = .action(index)
        index == 0 ? pasteSelected(plainText: true, source: .return) : presentSelectedChopOverlay()
    }

    func presentChopOverlay(for item: ClipItem) {
        guard item.kind == .text, !(item.plainText ?? "").isEmpty, overlayBuilder != nil else { return }
        imeInputActive = false
        // 列表条目只带预览文本；分词需完整全文，按 id 补全后再构建 overlay（DB 读在后台）。
        Task { [weak self] in
            guard let self else { return }
            let fullItem = await self.itemWithFullText(item)
            self.buildChopOverlay(for: fullItem)
        }
    }

    /// 用完整 `plain_text` 补全列表条目（列表只带预览）；取不到则原样返回。
    /// 短内容（预览未顶到上限）即完整，直接返回、不回源。
    private func itemWithFullText(_ item: ClipItem) async -> ClipItem {
        if let preview = item.plainText, preview.count < HistoryStore.previewTextLength {
            return item
        }
        guard let id = item.id, let historyStore,
              let full = try? await historyStore.fullText(id: id) else {
            return item
        }
        var copy = item
        copy.plainText = full
        return copy
    }

    private func buildChopOverlay(for item: ClipItem) {
        guard let overlayBuilder, !(item.plainText ?? "").isEmpty else { return }
        // 分词层打开后卡片条禁点（allowsHitTesting=false），hover 的 .ended 可能收不到，
        // 这里主动让波浪退场，避免卡片条在 overlay 背后保持隆起。
        wave.pointerExited()
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
        if isPanelPresented { beginIMEInput() }
        onLayoutChange?()
    }

    // MARK: - 面板内搜索（01 §3.6）

    /// ASCII 快速搜索：keyDown 直接并入查询字符。
    func appendSearchCharacter(_ character: Character) {
        searchQuery.append(character)
        scheduleFilter()
        onLayoutChange?()
    }

    /// 隐藏 TextField 绑定：中英文输入及输入法提交文本都由此驱动查询。
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

    /// 准备输入法客户端；面板显示时自动调用，点击搜索胶囊时也可恢复焦点。
    func beginIMEInput() {
        guard !imeInputActive else { return }
        imeInputActive = true
        onLayoutChange?()
        onIMEInputRequested?()
    }

    /// 退出搜索、回全量（第一次 esc）。
    func exitSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchQuery = ""
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
            results = (try? await historyStore.page(limit: Settings.panelItemCount)) ?? []
        } else {
            // 搜索用更大的结果上限（与浏览显示解耦），避免命中较多时截断较旧匹配。
            results = (try? await historyStore.search(query, limit: SummonPanelLayout.searchResultLimit)) ?? []
        }
        guard query == searchQuery else { return }   // 期间查询词已变，丢弃过期结果
        // 渲染条数守住 maximumItemCount（与 init 一致）：searchResultLimit(300) 高于它，
        // 不截断会让卡片条实际卡数超出 cardStripWidth 的计量上限，滚动范围随之算短。
        // 命中总数仍按未截断的结果显示。
        items = Array(results.prefix(SummonPanelLayout.maximumItemCount))
        matchCount = results.count
        selectedIndex = min(selectedIndex, max(0, items.count - 1))
        focus = .card
        onLayoutChange?()
    }

    func tearDown() {
        refreshTask?.cancel()
        refreshTask = nil
        searchTask?.cancel()
        searchTask = nil
        onLayoutChange = nil
        onIMEInputRequested = nil
    }

    private func refresh() {
        guard let historyStore else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self, historyStore] in
            do {
                let page = try await historyStore.page(limit: Settings.panelItemCount)
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
