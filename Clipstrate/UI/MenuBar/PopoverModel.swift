import SwiftUI

/// Popover 主界面的数据源（01 §5）：横向卡片流 keyset 分页（每页 50）、常驻搜索框
/// 防抖 150ms、底部统计。DB 读取全 async；点击条目走 `onCopy`（复制到剪贴板顶部）。
@MainActor
final class PopoverModel: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published var query = ""
    @Published private(set) var totalCount = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var isLoadingPage = false

    /// 点击条目回调（复制到剪贴板顶部 + toast，由 App 层接 PasteService）。
    var onCopy: ((ClipItem) -> Void)?

    private let historyStore: HistoryStore?
    private let pageSize = 50
    private var canPaginate = true
    private var searchTask: Task<Void, Never>?

    init(historyStore: HistoryStore?) {
        self.historyStore = historyStore
    }

    /// 打开 Popover 时调用：回到全量首页 + 刷新统计。
    func reload() async {
        query = ""
        await loadFirstPage()
        await refreshStats()
    }

    func loadFirstPage() async {
        guard let historyStore else { return }
        canPaginate = true
        let page = (try? await historyStore.page(limit: pageSize)) ?? []
        items = page
        canPaginate = page.count == pageSize
    }

    /// 滚到末尾时加载下一页（仅全量态、还有更多、未在加载中）。
    func loadNextPage() async {
        guard let historyStore, canPaginate, query.isEmpty, !isLoadingPage,
              let last = items.last else { return }
        isLoadingPage = true
        let next = (try? await historyStore.page(after: last, limit: pageSize)) ?? []
        items.append(contentsOf: next)
        canPaginate = next.count == pageSize
        isLoadingPage = false
    }

    /// 查询变化：防抖 150ms 后搜索（01 §5）。空查询回到全量首页。
    func queryDidChange() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.performSearch()
        }
    }

    func performSearch() async {
        guard let historyStore else { return }
        let q = query
        let results = (try? await historyStore.search(q, limit: pageSize)) ?? []
        guard q == query else { return }            // 期间又改了查询词，丢弃过期结果
        items = results
        canPaginate = q.isEmpty && results.count == pageSize
    }

    func refreshStats() async {
        guard let historyStore else { return }
        totalCount = (try? await historyStore.count()) ?? 0
        totalBytes = (try? await historyStore.totalByteSize()) ?? 0
    }

    func copy(_ item: ClipItem) {
        onCopy?(item)
    }

    func tearDown() {
        searchTask?.cancel()
        searchTask = nil
    }
}
