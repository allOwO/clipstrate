import Combine
import SwiftUI

/// 卡片条的轻量 UI 状态。数据库读取保持 async；面板唤出只展示已预热的快照并触发刷新。
@MainActor
final class SummonPanelModel: ObservableObject {
    @Published private(set) var items: [ClipItem]
    @Published private(set) var selectedIndex = 0
    @Published private(set) var presentationEpoch = 0
    @Published private(set) var isPanelPresented = false
    @Published private(set) var overlayView: AnyView?

    var onLayoutChange: (() -> Void)?

    private let historyStore: HistoryStore?
    private var overlayBuilder: ChopOverlayBuilder?
    private var refreshTask: Task<Void, Never>?

    init(
        historyStore: HistoryStore?,
        overlayBuilder: ChopOverlayBuilder? = nil,
        initialItems: [ClipItem] = []
    ) {
        self.historyStore = historyStore
        self.overlayBuilder = overlayBuilder
        items = Array(initialItems.prefix(SummonPanelLayout.maximumItemCount))
    }

    func prewarm() {
        refresh()
    }

    func beginPresentation() {
        selectedIndex = 0
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
}
