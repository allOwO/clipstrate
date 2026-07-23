import AppKit
import SwiftUI
import XCTest
@testable import Clipstrate

@MainActor
final class SummonPanelSearchTests: XCTestCase {
    private var tempDir: URL!
    private var store: HistoryStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipstrateSearch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try HistoryStore(path: tempDir.appendingPathComponent("history.sqlite").path)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func text(_ s: String, _ hash: String) -> ClipItem {
        ClipItem(kind: .text, plainText: s, contentHash: hash)
    }

    func testTypingEntersSearchState() {
        let model = SummonPanelModel(historyStore: store)
        model.appendSearchCharacter("a")
        XCTAssertEqual(model.searchQuery, "a")
        XCTAssertTrue(model.isSearching)
    }

    func testBareDigitAppendsToQueryWhenSearching() {
        let model = SummonPanelModel(historyStore: store)
        model.appendSearchCharacter("a")
        _ = model.handle(.digit(3))
        XCTAssertEqual(model.searchQuery, "a3", "搜索态裸数字并入查询")
    }

    func testBareDigitPastesWhenQueryEmpty() {
        var pasted: [String] = []
        let model = SummonPanelModel(
            historyStore: store,
            pasteHandler: { item, _, source in pasted.append("\(item.contentHash):\(source)") },
            initialItems: [text("only", "h1")]
        )
        _ = model.handle(.digit(1))
        XCTAssertEqual(pasted, ["h1:press"], "空查询时数字直贴（press 语义）")
    }

    func testEscExitsSearchThenRequestsClose() {
        let model = SummonPanelModel(historyStore: store)
        model.appendSearchCharacter("a")
        XCTAssertTrue(model.handle(.escape), "第一次 esc 清空搜索")
        XCTAssertFalse(model.isSearching)
        XCTAssertEqual(model.searchQuery, "")
        XCTAssertFalse(model.handle(.escape), "第二次 esc 请求关闭")
    }

    func testDeleteRemovesTrailingCharacter() {
        let model = SummonPanelModel(historyStore: store)
        model.appendSearchCharacter("a")
        model.appendSearchCharacter("b")
        XCTAssertTrue(model.deleteSearchCharacter())
        XCTAssertEqual(model.searchQuery, "a")
    }

    func testBeginIMEActivatesSearch() {
        let model = SummonPanelModel(historyStore: store)
        var requestCount = 0
        model.onIMEInputRequested = { requestCount += 1 }
        XCTAssertFalse(model.isSearching)
        model.beginIMEInput()
        XCTAssertTrue(model.imeInputActive)
        XCTAssertTrue(model.isSearching)
        XCTAssertEqual(requestCount, 1, "进入输入法态时请求 Controller 激活并置 key")

        model.beginIMEInput()
        XCTAssertEqual(requestCount, 1, "已在输入法态时不重复激活窗口")
    }

    func testIMEFieldBecomesFirstResponderWhenCapsuleFirstAppears() async throws {
        let model = SummonPanelModel(historyStore: nil)
        let panel = SummonPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: SummonPanelView(model: model))
        panel.orderFront(nil)
        panel.makeKey()
        defer { panel.orderOut(nil) }

        model.beginIMEInput()
        for _ in 0..<10 where !(panel.firstResponder is NSTextView) {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(
            panel.firstResponder is NSTextView,
            "胶囊由 / 首次插入时，TextField 必须立即成为输入法的 first responder"
        )
    }

    func testTypingFiltersItems() async throws {
        _ = try await store.upsert(text("这是一个验证码 8823", "h1"), at: 100)
        _ = try await store.upsert(text("完全无关的内容", "h2"), at: 200)

        let model = SummonPanelModel(historyStore: store)
        for character in "验证码" { model.appendSearchCharacter(character) }
        try await Task.sleep(for: .milliseconds(220)) // 越过 100ms 防抖

        XCTAssertEqual(model.items.map(\.contentHash), ["h1"], "打字实时过滤")
        XCTAssertEqual(model.matchCount, 1)
    }
}
