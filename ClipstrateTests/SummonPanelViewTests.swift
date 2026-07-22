import XCTest
@testable import Clipstrate

final class SummonPanelViewTests: XCTestCase {
    func testVariantCCardStripWidthMatchesSpec() {
        XCTAssertEqual(SummonPanelLayout.cardStripWidth(itemCount: 1), 252)
        XCTAssertEqual(SummonPanelLayout.cardStripWidth(itemCount: 2), 390)
        XCTAssertEqual(SummonPanelLayout.cardStripWidth(itemCount: 9), 1_356)
        XCTAssertEqual(SummonPanelLayout.cardStripWidth(itemCount: 12), 1_356)
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
