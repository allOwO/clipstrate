import CoreGraphics

/// 变体 C 的纯布局计算，供 NSPanel 尺寸与 SwiftUI 内容共用。
enum SummonPanelLayout {
    static let maximumItemCount = 9
    static let screenInset: CGFloat = 16
    static let shadowPadding: CGFloat = 16
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
        let cardsWidth = cardStripWidth(itemCount: itemCount, selectedIndex: selectedIndex)
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
