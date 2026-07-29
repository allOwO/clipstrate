import AppKit
import SwiftUI
import XCTest
@testable import Clipstrate

/// 卡片阴影裁剪回归：把真实 SummonPanelView 装进真实窗口，量卡片条外围的**裁剪边界**。
///
/// 说明一下这里为什么不是像素断言：Liquid Glass 及其投影由窗口服务器合成，进程内
/// `cacheDisplay` / `CALayer.render` 都只拿到文字与描边（玻璃是空的），而能真正拍到合成结果的
/// ScreenCaptureKit 需要 TCC 录屏授权（`CGWindowListCreateImage` 在 macOS 26 已移除），
/// 无人值守的测试拿不到。于是退一层，断言阴影**有没有地方铺**：
/// 卡底以下 requiredDepth 内不允许存在任何裁剪边界。原来的 bug 正是边界压在卡底下方
/// shadowPadding(16pt) 处，把 60pt 的羽化切成一条横线。
@MainActor
final class SummonPanelShadowClipTests: XCTestCase {
    /// 阴影需要的向下空间：原型变体 C 选中卡 `0 28px 64px` ≈ 卡底以下 60pt。
    private let requiredDepth: CGFloat = 60

    func testNoClipBoundaryWithinShadowDepthBelowCards() throws {
        let model = SummonPanelModel(historyStore: nil, initialItems: makeItems(50))
        let window = try mountPanel(model: model, width: 1_000)
        defer { window.orderOut(nil) }

        let root = try XCTUnwrap(window.contentView)
        let scrollView = try XCTUnwrap(
            findViews(in: root) { $0 is NSScrollView }.first as? NSScrollView
        )
        let viewport = scrollView.convert(scrollView.bounds, to: nil)
        // 卡片条底对齐，视口底边再往上 shadowPadding 就是卡片底边。
        let cardBottom = viewport.minY + SummonPanelLayout.shadowPadding

        XCTAssertGreaterThanOrEqual(
            SummonPanelLayout.shadowBleed, requiredDepth,
            "放行距离不足以容下阴影羽化"
        )

        // ① 卡片条自身的裁剪必须放开纵向，否则阴影连视口都出不去。
        XCTAssertFalse(scrollView.contentView.clipsToBounds, "NSClipView 仍在裁剪（scrollClipDisabled 失效？）")

        // ② 从卡片条往上到窗口，任何裁剪边界都不能落在卡底以下 requiredDepth 之内。
        let clippers = ancestorClippers(from: scrollView, upTo: root)
        XCTAssertFalse(clippers.isEmpty, "一个裁剪边界都没有——横向裁剪没了，滚出视口的卡片会铺到窗口边上")
        for clipper in clippers {
            XCTAssertLessThanOrEqual(
                clipper.frame.minY, cardBottom - requiredDepth,
                """
                \(clipper.label) 的下边界在卡底以下 \
                \(String(format: "%.1f", cardBottom - clipper.frame.minY))pt \
                （需要 ≥ \(requiredDepth)pt），阴影会在这里被切成横线
                """
            )
        }

        // ③ 横向仍需贴住视口：否则滚出视口的卡片会画到窗口边上（放开纵向不等于两轴都放开）。
        let horizontallyTight = clippers.contains { clipper in
            clipper.frame.minX >= viewport.minX - 0.5 && clipper.frame.maxX <= viewport.maxX + 0.5
        }
        XCTAssertTrue(
            horizontallyTight,
            "没有任何裁剪边界贴住视口横向范围：\(clippers.map(\.description).joined(separator: " / "))"
        )
    }

    // MARK: - 夹具

    private struct Clipper {
        let label: String
        let frame: CGRect

        var description: String {
            String(format: "%@(%.0f,%.0f %.0fx%.0f)", label, frame.minX, frame.minY, frame.width, frame.height)
        }
    }

    /// 自 `view` 向上直到 `root`（含）收集会裁剪的祖先，frame 换算到窗口坐标。
    private func ancestorClippers(from view: NSView, upTo root: NSView) -> [Clipper] {
        var clippers: [Clipper] = []
        var cursor: NSView? = view
        while let current = cursor {
            let clips = current.clipsToBounds || (current.layer?.masksToBounds ?? false)
            if clips {
                clippers.append(
                    Clipper(label: "\(type(of: current))", frame: current.convert(current.bounds, to: nil))
                )
            }
            if current === root { break }
            cursor = current.superview
        }
        return clippers
    }

    private func makeItems(_ count: Int) -> [ClipItem] {
        (0..<count).map { index in
            ClipItem(
                kind: .text,
                plainText: "条目 \(index) 的示例文本，用来占据卡片正文若干行。",
                contentHash: "shadow-hash-\(index)",
                appName: "ShadowApp"
            )
        }
    }

    /// 与生产同款的无边框透明面板窗口（尺寸走 SummonPanelLayout，裁剪链才有可比性）。
    private func mountPanel(model: SummonPanelModel, width: CGFloat) throws -> NSWindow {
        let size = CGSize(width: width, height: SummonPanelLayout.normalPanelHeight)
        let window = NSWindow(
            contentRect: NSRect(origin: CGPoint(x: 40, y: 200), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.animationBehavior = .none
        window.contentView = NSHostingView(rootView: SummonPanelView(model: model))

        model.beginPresentation()
        window.orderFrontRegardless()
        pump(0.8)                       // 等入场动画与布局落定，裁剪视图才建好
        return window
    }

    private func findViews(in root: NSView, matching predicate: (NSView) -> Bool) -> [NSView] {
        var found: [NSView] = predicate(root) ? [root] : []
        for subview in root.subviews {
            found += findViews(in: subview, matching: predicate)
        }
        return found
    }

    private func pump(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
}
