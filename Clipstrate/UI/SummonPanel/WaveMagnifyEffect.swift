import os
import SwiftUI

/// 「完整特效」波浪放大（01 §3.2）：光标附近的卡片按余弦衰减轻微放大，Dock 放大镜风格。
/// 参数由 prototype/wave-magnify.html 拍板：幅度 1.08×、半径 220pt、余弦衰减、
/// 跟随平滑 τ≈80ms、选中卡不参与（保持「选中 = ⏎ 粘贴目标」的语义）。
///
/// 纯变换驱动：只经 `.visualEffect { scaleEffect(_, anchor: .bottom) }` 施加，绝不改
/// frame——布局驱动会触发 LazyHStack 整条重排，正是 2026-07-27 修掉的滚动卡顿根源
/// （见 SummonPanelView 注释与 SummonPanelScrollDiagTests）。滚动几何（stripWidth /
/// contentSize）与事件层修复（ScrollEventRescue / MomentumScrollAssist）零接触。
enum WaveMagnify {
    /// 卡片条的命名坐标空间：定义在 ScrollView 容器上（不随内容滚动）。指针位置与
    /// 卡片 frame 都以它为参照，滚动时卡片 frame 逐帧变化即自动驱动波浪，无需指针事件。
    static let coordinateSpaceName = "summon-wave"

    /// 未选中卡最大放大。约束：必须明显小于选中态放大（252/128≈1.97）避免语义混淆；
    /// 底对齐向上生长的裁剪上限约 1.12×，选中卡 1.08× 即顶到 shadowPadding 裁剪线。
    static let maxScale: CGFloat = 1.08
    /// 光标影响半径（与卡中心的水平距离，pt）：约覆盖左右各一张半未选中卡。
    static let radius: CGFloat = 220
    /// 波浪整体淡入淡出（光标进出卡片条 / 分词层打开时退场）。
    static let fadeDuration: Double = 0.18
    /// 光标移动的跟随平滑：以短 easeOut 连续重定向近似原型的 τ≈80ms 指数趋近。
    static let followDuration: Double = 0.08

    /// 余弦衰减权重：d=0 → 1，|d|≥radius → 0（Dock 风，肩部圆润）。
    static func falloff(distance: CGFloat, radius: CGFloat = radius) -> CGFloat {
        let t = min(abs(distance) / radius, 1)
        return 0.5 + 0.5 * cos(.pi * t)
    }

    /// 卡片缩放：d=0 → maxScale，|d|≥radius → 1。gain ∈ [0,1] 为全局波浪权重。
    static func scale(distance: CGFloat, gain: CGFloat) -> CGFloat {
        guard gain > 0 else { return 1 }
        return 1 + (maxScale - 1) * falloff(distance: distance) * gain
    }
}

/// 波浪的可观察状态：指针 x（容器坐标）+ 全局权重。独立于 SummonPanelModel 的
/// @Published，指针高频移动只重求值观察它的 `waveMagnify` 修饰器，面板 body 不动。
@MainActor
final class WaveMagnifyState: ObservableObject {
    @Published private(set) var pointerX: CGFloat?
    @Published private(set) var gain: CGFloat = 0
    /// 每次唤出时按设置 + 减弱动态快照（MotionPolicy.fullEffectsActive）；显示期间不变。
    private(set) var isEnabled = false

    /// 波浪激活区间打点（gain 0↔1 翻转，低频），供 Instruments 与滚动帧率对照。
    private var signpostState: OSSignpostIntervalState?

    func preparePresentation(enabled: Bool) {
        isEnabled = enabled
        pointerX = nil
        setGain(0, animated: false)
    }

    func pointerMoved(to x: CGFloat) {
        guard isEnabled else { return }
        withAnimation(.easeOut(duration: WaveMagnify.followDuration)) {
            pointerX = x
        }
        setGain(1, animated: true)
    }

    func pointerExited() {
        setGain(0, animated: true)
    }

    private func setGain(_ value: CGFloat, animated: Bool) {
        guard gain != value else { return }
        if animated {
            withAnimation(.easeOut(duration: WaveMagnify.fadeDuration)) { gain = value }
        } else {
            gain = value
        }
        if value > 0, signpostState == nil {
            signpostState = Log.signposter.beginInterval("summon.wave")
        } else if value == 0, let state = signpostState {
            Log.signposter.endInterval("summon.wave", state)
            signpostState = nil
        }
    }
}

/// 施加到每张卡（玻璃 / 描边组合完成之后）：按「卡中心 ↔ 光标水平距离」缩放，锚点
/// 底边中心（基线不动，向上生长）。visualEffect 不参与布局与命中测试——选中判定、
/// 点击与滚动几何都仍按未缩放的布局盒，与原型拍板时的行为一致。
struct WaveMagnifyModifier: ViewModifier {
    @ObservedObject var wave: WaveMagnifyState
    /// 选中卡不参与波浪（拍板决定）。
    let excluded: Bool

    func body(content: Content) -> some View {
        // 闭包按值捕获快照；滚动中卡片 frame 逐帧变化会重跑闭包，指针不动波浪也跟着卡走。
        let pointerX = excluded ? nil : wave.pointerX
        let gain = wave.gain
        return content.visualEffect { view, proxy in
            let scale: CGFloat = if let pointerX, gain > 0 {
                WaveMagnify.scale(
                    distance: proxy.frame(in: .named(WaveMagnify.coordinateSpaceName)).midX - pointerX,
                    gain: gain
                )
            } else {
                1
            }
            return view.scaleEffect(scale, anchor: .bottom)
        }
    }
}

extension View {
    /// 波浪放大（「完整特效」）。挂在卡片视觉组合的最外层、槽位 frame 之内。
    func waveMagnify(_ wave: WaveMagnifyState, excluded: Bool) -> some View {
        modifier(WaveMagnifyModifier(wave: wave, excluded: excluded))
    }
}
