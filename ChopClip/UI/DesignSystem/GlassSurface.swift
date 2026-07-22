import SwiftUI

/// 接缝①（02 §8）：Liquid Glass 观感集中隔离于此。内部用 macOS 26 的 `glassEffect`。
///
/// 部署目标 26 下 `glassEffect` 恒可用，当前零 `#available`；将来若下调部署目标或
/// 支持「兼容模式」(display.panelStyle=compat)，只在本文件内加 `.regularMaterial` /
/// `NSVisualEffectView` 分支——业务代码永远只写 `.glassSurface(...)`。
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = DS.Metrics.cardCornerRadius
    var tint: Color? = nil
    var interactive: Bool = false

    func body(content: Content) -> some View {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return content.glassEffect(
            glass,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

extension View {
    /// 应用 Liquid Glass 表面（接缝①）。卡片、玻璃胶囊、分词层容器统一走这里。
    func glassSurface(cornerRadius: CGFloat = DS.Metrics.cardCornerRadius,
                      tint: Color? = nil,
                      interactive: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}
