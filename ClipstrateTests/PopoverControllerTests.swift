import AppKit
import XCTest
@testable import Clipstrate

/// Popover 生命周期回归：面板常驻复用（`isReleasedWhenClosed = false`），SwiftUI 视图层级
/// 不随开关重建，`.task` 一生只跑一次。因此每次 `show()` 都必须重新加载首页与统计——
/// 否则第二次打开起永远是旧列表（曾经是空列表 +"暂无历史"）+ 过期统计。
@MainActor
final class PopoverControllerTests: XCTestCase {
    private var tempDir: URL!
    private var store: HistoryStore!
    private var controller: PopoverController!
    private var buttonWindow: NSWindow!
    private var button: NSStatusBarButton!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipstratePopoverController-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try HistoryStore(path: tempDir.appendingPathComponent("history.sqlite").path)
        for i in 1...3 {
            _ = try await store.upsert(
                ClipItem(kind: .text, plainText: "item-\(i)", contentHash: "h\(i)", byteSize: 10),
                at: Int64(i))
        }

        controller = PopoverController(historyStore: store, blobStore: nil)

        // show(relativeTo:) 只要求按钮挂在窗口上（用于坐标换算），无需真实菜单栏。
        button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 28, height: 22))
        buttonWindow = NSWindow(
            contentRect: NSRect(x: 200, y: 600, width: 28, height: 22),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        buttonWindow.isReleasedWhenClosed = false
        buttonWindow.contentView?.addSubview(button)
    }

    override func tearDown() async throws {
        controller?.tearDown()
        controller = nil
        buttonWindow?.orderOut(nil)
        buttonWindow = nil
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testReopenReloadsItemsAndStats() async throws {
        controller.show(relativeTo: button)
        try await waitUntil("首次打开加载出条目") { [self] in !controller.model.items.isEmpty }

        controller.hide()

        // 关闭期间又复制了新内容——重开时列表和统计都必须反映出来。
        _ = try await store.upsert(
            ClipItem(kind: .text, plainText: "item-4", contentHash: "h4", byteSize: 10), at: 999)

        controller.show(relativeTo: button)
        try await waitUntil("再次打开加载出新条目") { [self] in
            controller.model.items.first?.contentHash == "h4"
        }
        try await waitUntil("再次打开刷新统计") { [self] in controller.model.totalCount == 4 }
    }

    func testHideTrimsAccumulatedPagesToFirstPage() async throws {
        for i in 4...120 {
            _ = try await store.upsert(
                ClipItem(kind: .text, plainText: "item-\(i)", contentHash: "h\(i)", byteSize: 10),
                at: Int64(i))
        }

        controller.show(relativeTo: button)
        try await waitUntil("首次打开加载出首页") { [self] in controller.model.items.count == 50 }
        await controller.model.loadNextPage()
        XCTAssertEqual(controller.model.items.count, 100)

        controller.hide()
        XCTAssertEqual(controller.model.items.count, 50, "收起后只保留首页的量，重开不闪空态")
    }

    /// 轮询直到条件成立（挂起主 actor 让排队的加载任务运行）；超时报出未满足的条件。
    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("等待超时：\(what)")
    }
}
