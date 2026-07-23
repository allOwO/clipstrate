import SwiftUI

struct TokenFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 7
    var verticalSpacing: CGFloat = 8

    nonisolated var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }

    nonisolated func makeCache(subviews: Subviews) -> () {}

    nonisolated func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    nonisolated func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews
        )
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    nonisolated private func layout(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> LayoutResult {
        let maxWidth = proposal.width ?? DS.Metrics.chopOverlayMaxWidth
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - horizontalSpacing)
        }

        return LayoutResult(
            size: CGSize(width: min(maxWidth, usedWidth), height: y + rowHeight),
            points: points
        )
    }
}

private struct LayoutResult {
    let size: CGSize
    let points: [CGPoint]
}
