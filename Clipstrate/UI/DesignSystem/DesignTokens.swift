import SwiftUI
import AppKit

/// 设计 token（颜色 / 尺寸 / 动效 / 字体）。数值取自 `prototype/index.html` 与 01 §3。
/// A/B 两线共用；接口保持稳定。
enum DS {
    enum Colors {
        /// 强调色：跟随系统强调色（默认蓝，与原型 #007AFF/#0A84FF 一致）。
        static let accent = Color(nsColor: .controlAccentColor)
        /// 选中描边（卡片焦点层 2.5pt）。
        static let selectionRing = Color(nsColor: .controlAccentColor)
        /// 分隔线。
        static let divider = Color.primary.opacity(0.08)
        /// 次级文字。
        static let secondaryText = Color.secondary
    }

    enum Metrics {
        static let cardCornerRadius: CGFloat = 20
        static let cardSpacing: CGFloat = 10
        /// 未选中 / 选中卡片尺寸（01 §3.2）。
        static let cardUnselected = CGSize(width: 128, height: 126)
        static let cardSelected = CGSize(width: 252, height: 196)
        /// 卡片条底边距光标/鼠标上方（01 §3.1）。
        static let caretGap: CGFloat = 12
        /// 快捷键提示胶囊距卡片条下方（01 §3.2）。
        static let hintPillGap: CGFloat = 18
        /// 卡片焦点层描边宽度（01 §3.3）。
        static let selectionRingWidth: CGFloat = 2.5
        /// 进入动作层时选中卡描边淡化到的透明度（01 §3.3）。
        static let actionLayerRingOpacity: Double = 0.28
        /// 分词层打开时背后卡片条降到的透明度（01 §4.2 / 02 §6）。
        static let overlayDimOpacity: Double = 0.25
        /// 胶囊 / 词块圆角。
        static let chipCornerRadius: CGFloat = 10
        /// 分词层容器最大宽度（01 §4.2）。
        static let chopOverlayMaxWidth: CGFloat = 640
    }

    enum Anim {
        /// 卡片生长（未选中→选中）过渡（01 §3.2：0.28s spring）。
        static let cardGrow = Animation.spring(response: 0.28, dampingFraction: 0.82)
        /// 进场：自基线上浮 26pt + scale 0.92→1，逐张错开 45ms（01 §3.2）。
        static let entranceRise: CGFloat = 26
        static let entranceScale: CGFloat = 0.92
        static let entranceStagger: Double = 0.045
        /// 关闭反向 0.15s。
        static let closeDuration: Double = 0.15
        /// 描边淡化过渡（01 §3.3：0.2s）。
        static let ringFadeDuration: Double = 0.2
    }

    enum Typography {
        static let cardTypeLabel = Font.caption.weight(.medium)
        static let cardBody = Font.system(size: 13)
        static let cardMeta = Font.caption2
        static let entityValue = Font.system(size: 13, weight: .medium)
        static let badge = Font.caption2.weight(.semibold).monospacedDigit()
    }
}
