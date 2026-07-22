import XCTest
import SwiftUI
@testable import Clipstrate

@MainActor
final class DesignSystemTests: XCTestCase {
    func testMetricsMatchSpec() {
        XCTAssertEqual(DS.Metrics.cardCornerRadius, 20)
        XCTAssertEqual(DS.Metrics.cardSpacing, 10)
        XCTAssertEqual(DS.Metrics.cardUnselected, CGSize(width: 128, height: 126))
        XCTAssertEqual(DS.Metrics.cardSelected, CGSize(width: 252, height: 196))
        XCTAssertEqual(DS.Metrics.overlayDimOpacity, 0.25)
        XCTAssertEqual(DS.Metrics.selectionRingWidth, 2.5)
    }

    /// 编译期契约：GlassSurface 修饰器与 ChopOverlayBuilder 对 B 线可用且稳定。
    func testGlassSurfaceAndOverlayContract() {
        _ = Text("x").glassSurface()
        let item = ClipItem(kind: .text, plainText: "hi", contentHash: "h")
        let builder: ChopOverlayBuilder = { request, _ in AnyView(Text(request.text)) }
        _ = builder(ChopOverlayRequest(item: item), {})
        XCTAssertEqual(ChopOverlayRequest(item: item).text, "hi")
    }

    func testMotionPolicyUsable() {
        _ = MotionPolicy.animation(DS.Anim.cardGrow)
        _ = MotionPolicy.overlayTransition
    }
}
