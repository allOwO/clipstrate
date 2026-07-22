import CoreGraphics

/// 唤出面板定位（01 §3.1）：底边位于锚点上方 `gap`、水平居中于锚点、clamp 进屏幕
/// visibleFrame；上方放不下则翻到锚点下方。纯函数（Cocoa 坐标，bottom-left 原点），便于单测。
enum PanelPlacement {
    static func frame(panelSize: CGSize, anchor: CGRect, gap: CGFloat, visibleFrame: CGRect) -> CGRect {
        var x = anchor.midX - panelSize.width / 2
        var y = anchor.maxY + gap                       // 底边在锚点上方 gap（y 向上）

        // 上方放不下 → 翻到锚点下方
        if y + panelSize.height > visibleFrame.maxY {
            y = anchor.minY - gap - panelSize.height
        }

        x = clamp(x, visibleFrame.minX, visibleFrame.maxX - panelSize.width)
        y = clamp(y, visibleFrame.minY, visibleFrame.maxY - panelSize.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
    }

    /// 面板可能比屏幕还大（hi < lo）：此时取 lo（贴左/贴下），不产生 NaN。
    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        max(lo, min(v, hi))
    }
}
