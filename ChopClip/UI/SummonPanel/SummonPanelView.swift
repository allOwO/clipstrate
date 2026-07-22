import SwiftUI

/// 唤出面板内容。T1.2 为占位（验证定位/焦点/开合）；T1.3 替换为变体 C 卡片条。
struct SummonPanelView: View {
    static let placeholderSize = CGSize(width: 420, height: 160)

    var body: some View {
        VStack(spacing: 6) {
            Text("ChopClip")
                .font(.headline)
            Text("卡片条 UI（变体 C）见 T1.3")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: Self.placeholderSize.width, height: Self.placeholderSize.height)
        .glassSurface(cornerRadius: DS.Metrics.cardCornerRadius)
    }
}
