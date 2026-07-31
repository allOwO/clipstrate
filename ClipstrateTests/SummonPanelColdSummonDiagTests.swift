import AppKit
import SwiftUI
import XCTest
@testable import Clipstrate

/// 「长时间不用后唤出，面板有一段 0.2–0.3s 的怪动画、框在变动」诊断（2026-07-30）。
///
/// 机制：`PanelController.show()` 是同步的——`beginPresentation()` 里的 `refresh()`
/// 是个 Task，**绝不可能**在 `orderFrontRegardless()` 之前完成。所以每次唤出都是
/// 「先按上一次的快照把面板摆好、显示出来，再等刷新结果回来替换 items」。
///
/// 连续唤出时刷新结果与快照一致，替换在视觉上是空操作，所以平时看不见。空闲很久之后：
///   1) 期间捕获了新剪贴板 → contentHash 变了 → ForEach 身份churn → 新卡 onAppear
///      → 错开的进场 spring **重放一遍**（只有变动的那几张，其余不动，观感很怪）；
///   2) 条数也变了 → onLayoutChange → panel.setFrame → **窗口可见地改尺寸**；
///   3) 冷库读盘（page cache 已被清）要 200–300ms，于是这一切落在面板显示之后
///      两三百毫秒，正是用户描述的时长。
///
/// 本用例只钉机制（1 与 2），不做时长断言（冷读盘无法在进程内复现）。
@MainActor
final class SummonPanelColdSummonDiagTests: XCTestCase {
    private var tempDir: URL!
    private var store: HistoryStore!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cold-summon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try HistoryStore(path: tempDir.appendingPathComponent("history.sqlite").path)
    }

    override func tearDown() async throws {
        store = nil
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func insert(_ count: Int, prefix: String) async throws {
        for index in 0..<count {
            _ = try await store.upsert(ClipItem(
                kind: .text,
                plainText: "\(prefix) 条目 \(index)",
                contentHash: "\(prefix)-\(index)",
                appName: "DiagApp"
            ))
        }
    }

    /// 等 refresh 的 Task 落地（它没有完成回调，只能轮询到 items 变化）。
    private func waitForItems(_ model: SummonPanelModel, toReach count: Int) async {
        for _ in 0..<200 {
            if model.items.count == count { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// 钉「显示之后才刷新」这一步：beginPresentation() 同步返回时 items 还是旧快照，
    /// 面板已经按旧快照的尺寸显示出去了；新数据是之后才到的。
    func testRefreshLandsAfterPresentationIsAlreadyOnScreen() async throws {
        try await insert(3, prefix: "old")
        let model = SummonPanelModel(historyStore: store)
        model.prewarm()
        await waitForItems(model, toReach: 3)
        let snapshotHashes = model.items.map(\.contentHash)

        // 空闲期间捕获了新剪贴板：直接写库，模型不知情（AppDelegate.handleCaptured
        // 不刷新面板模型，这是本 bug 的前提）。
        try await insert(2, prefix: "new")

        var layoutChanges = 0
        model.onLayoutChange = { layoutChanges += 1 }

        model.beginPresentation()
        // 此刻 PanelController 已经 updateLayout() + orderFrontRegardless() 了。
        XCTAssertEqual(model.items.map(\.contentHash), snapshotHashes,
                       "beginPresentation 同步返回时应仍是旧快照——面板就是按它的尺寸显示的")
        XCTAssertEqual(layoutChanges, 0, "同步阶段不应有布局变更")

        await waitForItems(model, toReach: 5)
        XCTAssertEqual(layoutChanges, 1,
                       "刷新在面板已可见之后才改布局 → 窗口在用户眼前改尺寸")
        XCTAssertNotEqual(model.items.map(\.contentHash), snapshotHashes,
                          "items 被换成了不同的 contentHash 集合")
    }

    /// 钉「卡片身份churn → 进场动画重放」：新旧快照的 cardID 集合不同，
    /// 差集就是会跑一遍 onAppear 进场 spring 的卡。
    func testChangedItemsGetFreshCardIdentityAndReplayEntrance() async throws {
        try await insert(3, prefix: "old")
        let model = SummonPanelModel(historyStore: store)
        model.prewarm()
        await waitForItems(model, toReach: 3)

        model.beginPresentation()
        let epoch = model.presentationEpoch
        let idsBefore = Set(model.items.map { "\($0.contentHash)-\(epoch)" })

        try await insert(2, prefix: "new")
        model.beginPresentation()                        // 第二次唤出（epoch 再 +1）
        await waitForItems(model, toReach: 5)
        let idsAfter = Set(model.items.map { "\($0.contentHash)-\(model.presentationEpoch)" })

        // 面板可见期间新出现的 cardID：这些卡会跑 onAppear → updateEntrance(animate: true)。
        XCTAssertFalse(idsAfter.subtracting(idsBefore).isEmpty,
                       "刷新引入了新的 cardID → 这些卡会在面板已可见后重放进场动画")
        XCTAssertTrue(model.isPanelPresented,
                      "进场动画的 animate 条件是 presentationEpoch>0 && isPanelPresented，此时两者都成立")
    }

    /// 修复回归：捕获后（面板隐藏时）刷新快照，唤出时的 refresh 就是空操作——
    /// 不改布局、不换 cardID，用户眼前什么都不会动。
    func testWarmSnapshotMakesSummonRefreshANoOp() async throws {
        try await insert(3, prefix: "old")
        let model = SummonPanelModel(historyStore: store)
        model.prewarm()
        await waitForItems(model, toReach: 3)

        // 空闲期间捕获新剪贴板 → 生产代码此时会调 refreshSnapshotIfHidden。
        try await insert(2, prefix: "new")
        model.refreshWhileHidden()
        await waitForItems(model, toReach: 5)
        let warmHashes = model.items.map(\.contentHash)

        var layoutChanges = 0
        model.onLayoutChange = { layoutChanges += 1 }
        model.beginPresentation()
        let shownHashes = model.items.map(\.contentHash)
        await waitForItems(model, toReach: 5)

        XCTAssertEqual(shownHashes, warmHashes, "唤出时显示的就是已经预热好的那批")
        XCTAssertEqual(model.items.map(\.contentHash), warmHashes,
                       "刷新回来内容不变 → 没有 cardID churn → 不重放进场动画")
        XCTAssertEqual(layoutChanges, 0,
                       "条数没变 → 不触发 onLayoutChange → 窗口不在用户眼前改尺寸")
    }

    /// 面板可见时不刷快照：那会让卡片在用户正看着的时候变动。
    func testVisiblePanelSnapshotIsNotDisturbed() async throws {
        try await insert(3, prefix: "old")
        let model = SummonPanelModel(historyStore: store)
        model.prewarm()
        await waitForItems(model, toReach: 3)

        model.beginPresentation()
        await waitForItems(model, toReach: 3)
        try await insert(2, prefix: "new")
        model.refreshWhileHidden()                       // 可见期间应被忽略
        try? await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(model.items.count, 3, "面板可见时快照不应被后台捕获改动")
    }

    /// 钉「条数变化会改面板宽度」：这就是「框在变动」的量。
    func testItemCountChangeMovesPanelWidth() {
        let width3 = SummonPanelLayout.panelSize(itemCount: 3, availableWidth: 2560).width
        let width5 = SummonPanelLayout.panelSize(itemCount: 5, availableWidth: 2560).width
        print("[DEBUG-cold] 面板宽度 3 条=\(width3)pt → 5 条=\(width5)pt（差 \(width5 - width3)pt）")
        XCTAssertNotEqual(width3, width5, "条数变化直接改面板宽度 → setFrame 在眼前跳")
    }
}
