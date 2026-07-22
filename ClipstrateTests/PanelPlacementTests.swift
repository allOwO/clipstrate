import XCTest
@testable import Clipstrate

final class PanelPlacementTests: XCTestCase {
    // 一块 1440×900、原点 (0,0)、无 Dock/菜单栏遮挡的可见区域用于计算。
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 400, height: 200)
    private let gap: CGFloat = 12

    func testCenteredAboveAnchor() {
        // 锚点在屏幕中部，上方空间充足。
        let anchor = CGRect(x: 700, y: 400, width: 2, height: 16)
        let f = PanelPlacement.frame(panelSize: size, anchor: anchor, gap: gap, visibleFrame: screen)
        XCTAssertEqual(f.midX, anchor.midX, accuracy: 0.5, "水平居中于锚点")
        XCTAssertEqual(f.minY, anchor.maxY + gap, accuracy: 0.5, "底边在锚点上方 gap")
        XCTAssertTrue(screen.contains(f))
    }

    func testClampsToRightEdge() {
        let anchor = CGRect(x: 1430, y: 400, width: 2, height: 16)
        let f = PanelPlacement.frame(panelSize: size, anchor: anchor, gap: gap, visibleFrame: screen)
        XCTAssertEqual(f.maxX, screen.maxX, accuracy: 0.5, "贴右边界不越界")
        XCTAssertLessThanOrEqual(f.minX, screen.maxX - size.width + 0.5)
    }

    func testClampsToLeftEdge() {
        let anchor = CGRect(x: 5, y: 400, width: 2, height: 16)
        let f = PanelPlacement.frame(panelSize: size, anchor: anchor, gap: gap, visibleFrame: screen)
        XCTAssertEqual(f.minX, screen.minX, accuracy: 0.5, "贴左边界不越界")
    }

    func testFlipsBelowWhenNoRoomAbove() {
        // 锚点贴近顶部，上方放不下 → 翻到锚点下方。
        let anchor = CGRect(x: 700, y: 880, width: 2, height: 16)
        let f = PanelPlacement.frame(panelSize: size, anchor: anchor, gap: gap, visibleFrame: screen)
        XCTAssertLessThan(f.maxY, anchor.minY, "翻到锚点下方")
        XCTAssertTrue(screen.contains(f))
    }

    func testFlipYConvertsQuartzToCocoa() {
        // 主屏高 900；Quartz rect 顶部 y=100、高 20 → Cocoa 底边 y = 900-(100+20)=780。
        let quartz = CGRect(x: 300, y: 100, width: 2, height: 20)
        let cocoa = SelectionGrabber.flipY(quartz: quartz, primaryHeight: 900)
        XCTAssertEqual(cocoa.minX, 300, accuracy: 0.5)
        XCTAssertEqual(cocoa.minY, 780, accuracy: 0.5)
        XCTAssertEqual(cocoa.height, 20, accuracy: 0.5)
    }
}
