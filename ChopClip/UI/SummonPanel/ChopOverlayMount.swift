import SwiftUI

/// 分词层挂载契约（A↔B 边界）。
///
/// 唤出面板（A 线）在卡片条**上层**留一个 overlay 槽位。当用户对文本卡触发拆词
/// （Tab / ↓→「✂︎分词」/ 全局 ⌥X）时，面板调用 `ChopOverlayBuilder` 构造 ChopOverlay
/// （B 线 UI/ChopOverlay/），挂到槽位、把背后卡片条降到 `DS.Metrics.overlayDimOpacity`；
/// ChopOverlay 完成（复制 / ⏎ / esc）时调用 `onClose`，面板据此收起 overlay、恢复卡片条与焦点。
///
/// 契约在此定稿并保持稳定：面板侧的挂载/降透明/焦点接管实现随 T1.3 落地，
/// B 线现在即可按此实现 ChopOverlay 视图与工厂。

/// 分词层的输入（被拆的条目；文本取 `item.plainText`）。
struct ChopOverlayRequest: Sendable {
    let item: ClipItem

    /// 待分词的纯文本（富文本条目取其纯文本副本）。
    var text: String { item.plainText ?? "" }
}

/// 分词层视图工厂（B 线 ChopOverlay 提供，App 启动时注入面板）。
/// - 参数 request：拆词请求。
/// - 参数 onClose：完成回调；ChopOverlay 结束时必须调用它，面板据此关闭 overlay。
/// - 返回：覆盖在卡片条之上的分词层视图（玻璃容器请用 `.glassSurface(...)`）。
typealias ChopOverlayBuilder = @MainActor (
    _ request: ChopOverlayRequest,
    _ onClose: @escaping () -> Void
) -> AnyView
