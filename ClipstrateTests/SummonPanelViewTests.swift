import XCTest
@testable import Clipstrate

final class SummonPanelViewTests: XCTestCase {
    func testVariantCCardStripWidthMatchesSpec() {
        // 卡片条宽度随条数线性增长（1 张选中 252 + 其余各 128 + 间距 10），
        // 上限为 maximumItemCount(200)；面板窗口再由 panelSize 夹到屏幕可视宽度、超出部分横向滚动。
        XCTAssertEqual(SummonPanelLayout.cardStripWidth(itemCount: 1), 252)
        XCTAssertEqual(SummonPanelLayout.cardStripWidth(itemCount: 2), 390)
        XCTAssertEqual(SummonPanelLayout.cardStripWidth(itemCount: 9), 1_356)
        XCTAssertEqual(SummonPanelLayout.cardStripWidth(itemCount: 12), 1_770)
    }

    func testPanelWidthClampsToVisibleScreen() {
        let wide = SummonPanelLayout.panelSize(itemCount: 9, availableWidth: 1_200)
        XCTAssertEqual(wide.width, 1_168)
        XCTAssertEqual(wide.height, SummonPanelLayout.normalPanelHeight)

        let overlay = SummonPanelLayout.panelSize(
            itemCount: 1,
            availableWidth: 1_200,
            overlayPresented: true
        )
        XCTAssertGreaterThanOrEqual(overlay.width, DS.Metrics.chopOverlayMaxWidth)
        XCTAssertEqual(overlay.height, SummonPanelLayout.overlayPanelHeight)
    }

    func testCardShadowClipOpensVerticallyOnly() {
        // 玻璃阴影向下铺到卡底以下约 60pt（原型变体 C 选中卡 `0 28px 64px`），
        // 放行距离必须盖得住，否则又在视口边界切出横线。
        XCTAssertGreaterThanOrEqual(SummonPanelLayout.shadowBleed, 60)

        // 裁剪只放纵向：横向仍严格贴视口，滚出去的卡片不会铺到窗口边上。
        let viewport = CGRect(x: 0, y: 0, width: 720, height: 228)
        let clipped = HorizontalOnlyClip(verticalBleed: SummonPanelLayout.shadowBleed)
            .path(in: viewport)
            .boundingRect
        XCTAssertEqual(clipped.minX, viewport.minX)
        XCTAssertEqual(clipped.maxX, viewport.maxX)
        XCTAssertEqual(clipped.minY, viewport.minY - SummonPanelLayout.shadowBleed)
        XCTAssertEqual(clipped.maxY, viewport.maxY + SummonPanelLayout.shadowBleed)
    }

    func testCardPresentationLabelsAndSourceOmission() {
        let rich = ClipItem(
            kind: .text,
            isRich: true,
            plainText: "  Clipstrate  ",
            contentHash: "rich",
            appName: "Safari"
        )
        let presentation = ClipCardPresentation(item: rich)
        XCTAssertEqual(presentation.typeLabel, "富文本")
        XCTAssertEqual(presentation.body, "Clipstrate")
        XCTAssertEqual(presentation.sourceName, "Safari")
        XCTAssertEqual(presentation.symbolName, "text.alignleft")

        let unknownSource = ClipItem(kind: .image, label: "截图", contentHash: "image", appName: "  ")
        XCTAssertNil(ClipCardPresentation(item: unknownSource).sourceName)
    }

    func testFilePresentationFallsBackToFileName() {
        let item = ClipItem(
            kind: .file,
            fileURLs: ["/tmp/report.xlsx"],
            contentHash: "file"
        )
        let presentation = ClipCardPresentation(item: item)
        XCTAssertEqual(presentation.typeLabel, "文件")
        XCTAssertEqual(presentation.body, "report.xlsx")
    }
}
