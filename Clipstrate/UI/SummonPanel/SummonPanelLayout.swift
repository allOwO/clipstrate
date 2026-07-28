import CoreGraphics

/// 变体 C 的纯布局计算，供 NSPanel 尺寸与 SwiftUI 内容共用。
enum SummonPanelLayout {
    /// 浏览显示的绝对上限（用户可在设置里调，但不超过此值，见 Settings.panelItemCount）。
    static let maximumItemCount = 200
    /// 设置里可选的「面板显示条数」档位。
    static let itemCountOptions = [20, 50, 100, 200]
    /// 面板窗口最多按这么多张卡计算宽度（带鱼屏也不铺满整屏）；更多条目在条内横向滚动，
    /// LazyHStack 只实体化视口内的卡，实体化数量因此有上界（内存不随历史条数线性增长）。
    static let maxVisibleCards = 20
    /// 搜索结果上限，与显示上限解耦：搜索本就扫全库，这里给更大的返回上限，
    /// 避免命中很多时把较旧的匹配截断（>此值才会截断，一般够用）。
    static let searchResultLimit = 300
    static let screenInset: CGFloat = 16
    static let shadowPadding: CGFloat = 16
    /// 卡片玻璃阴影允许铺出卡片条视口的纵向距离。Liquid Glass 的投影向下重偏
    /// （原型变体 C：未选中 `0 14px 36px` 约到卡底以下 32pt，选中 `0 28px 64px` 约 60pt），
    /// 远超 shadowPadding，靠加大留白是补不上的——只能让它铺出视口自然淡出（见
    /// SummonPanelView 的横向裁剪）。取 72：够容下 60pt 的羽化，多出的部分由窗口边界收掉。
    static let shadowBleed: CGFloat = 72
    static let verticalPadding: CGFloat = 8
    static let minimumPanelWidth: CGFloat = 720
    static let normalPanelHeight: CGFloat = 292
    static let overlayPanelHeight: CGFloat = 460
    static let searchCapsuleHeight: CGFloat = 46

    static func cardStripWidth(itemCount: Int, selectedIndex: Int = 0) -> CGFloat {
        let count = min(max(0, itemCount), maximumItemCount)
        guard count > 0 else { return 0 }
        let selectedCount = (0..<count).contains(selectedIndex) ? 1 : 0
        let unselectedCount = count - selectedCount
        return CGFloat(selectedCount) * DS.Metrics.cardSelected.width
            + CGFloat(unselectedCount) * DS.Metrics.cardUnselected.width
            + CGFloat(max(0, count - 1)) * DS.Metrics.cardSpacing
    }

    static func panelSize(
        itemCount: Int,
        selectedIndex: Int = 0,
        availableWidth: CGFloat,
        overlayPresented: Bool = false,
        searching: Bool = false
    ) -> CGSize {
        let usableWidth = max(DS.Metrics.cardSelected.width, availableWidth - screenInset * 2)
        // 窗口宽度最多按 maxVisibleCards 张卡计；更多条目滚动查看，窗口尺寸稳定不随条数增长。
        let widthCount = min(itemCount, maxVisibleCards)
        let cardsWidth = cardStripWidth(itemCount: widthCount,
                                        selectedIndex: min(selectedIndex, max(0, widthCount - 1)))
            + shadowPadding * 2
        let overlayWidth = DS.Metrics.chopOverlayMaxWidth + shadowPadding * 2
        let desiredWidth = overlayPresented
            ? max(minimumPanelWidth, max(cardsWidth, overlayWidth))
            : max(minimumPanelWidth, cardsWidth)
        let baseHeight = overlayPresented ? overlayPanelHeight : normalPanelHeight
        let height = baseHeight + (searching && !overlayPresented ? searchCapsuleHeight : 0)
        return CGSize(
            width: min(desiredWidth, usableWidth),
            height: height
        )
    }
}
