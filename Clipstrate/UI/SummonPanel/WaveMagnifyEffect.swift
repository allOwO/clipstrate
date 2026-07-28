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

    /// 未选中卡最大放大（2026-07-28 试用后二次拍板 1.25 成凸形；三次拍板改为**只变高**：
    /// 均匀缩放会让邻卡边缘互相覆盖，改 y 轴单向缩放后宽度不动、永不交叠）。
    /// 高度上仍明显小于选中态（196/126≈1.56），裁剪上限（126×s≤212）未触及。
    static let maxScale: CGFloat = 1.25
    /// 光标影响半径（与卡中心的水平距离，pt）。按「选中卡在光标下」的常态几何标定：
    /// 邻卡中心距光标约 200pt（选中半宽 126 + 间距 10 + 未选中半宽 64），540pt 半径
    /// 使 ±1 张约 1.20×、±2 张约 1.08×、±3 张归位——凸形覆盖左右各两张。
    static let radius: CGFloat = 540
    /// 波浪整体淡入淡出（光标进出卡片条 / 分词层打开时退场）。
    static let fadeDuration: Double = 0.18
    /// 光标移动的跟随平滑：以短 easeOut 连续重定向近似原型的 τ≈80ms 指数趋近。
    static let followDuration: Double = 0.08

    /// 余弦衰减权重：d=0 → 1，|d|≥radius → 0（Dock 风，肩部圆润）。
    static func falloff(distance: CGFloat, radius: CGFloat = radius) -> CGFloat {
        let t = min(abs(distance) / radius, 1)
        return 0.5 + 0.5 * cos(.pi * t)
    }

    /// 卡片**高度**缩放（宽度恒为 1）：d=0 → maxScale，|d|≥radius → 1。
    /// gain ∈ [0,1] 为全局波浪权重。
    static func scale(distance: CGFloat, gain: CGFloat) -> CGFloat {
        guard gain > 0 else { return 1 }
        return 1 + (maxScale - 1) * falloff(distance: distance) * gain
    }

    /// 键盘凸（四次拍板）：指针不在条内时，凸形跟着键盘选中走。按「与选中卡的档位
    /// 距离」折算成布局距离，复用同一条余弦衰减——数值与「光标停在选中卡中心」时的
    /// 指针波浪完全一致（±1 约 1.20×、±2 约 1.08×、±3 归位），两种驱动观感同源。
    static func keyboardScale(indexDistance k: Int) -> CGFloat {
        guard k > 0 else { return 1 }
        let d = DS.Metrics.cardSelected.width / 2 + DS.Metrics.cardSpacing
            + DS.Metrics.cardUnselected.width / 2
            + CGFloat(k - 1) * (DS.Metrics.cardUnselected.width + DS.Metrics.cardSpacing)
        return scale(distance: d, gain: 1)
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

/// 施加到每张卡（玻璃 / 描边组合完成之后），锚点底边中心（基线不动，向上生长）。
/// 两个驱动源按 gain 互补交叉淡化，永不叠满：
///   - 指针波浪：按「卡中心 ↔ 光标水平距离」连续计算，权重 gain；
///   - 键盘凸：按档位距离纯算（不依赖几何），权重 1-gain——指针进场即让位、离场即接管。
/// visualEffect 不参与布局与命中测试——选中判定、点击与滚动几何都仍按未缩放的布局盒。
struct WaveMagnifyModifier: ViewModifier {
    @ObservedObject var wave: WaveMagnifyState
    /// 本卡与选中卡的档位距离（index - selectedIndex）；0 = 选中卡，不参与波浪。
    let indexDistance: Int

    func body(content: Content) -> some View {
        // 闭包按值捕获快照；滚动中卡片 frame 逐帧变化会重跑闭包，指针不动波浪也跟着卡走。
        let excluded = indexDistance == 0
        let pointerX = excluded ? nil : wave.pointerX
        let gain = wave.gain
        let keyboardDelta = (excluded || !wave.isEnabled)
            ? 0
            : WaveMagnify.keyboardScale(indexDistance: abs(indexDistance)) - 1
        return content.visualEffect { view, proxy in
            var delta: CGFloat = keyboardDelta * (1 - gain)
            if let pointerX, gain > 0 {
                delta += WaveMagnify.scale(
                    distance: proxy.frame(in: .named(WaveMagnify.coordinateSpaceName)).midX - pointerX,
                    gain: gain
                ) - 1
            }
            // 只变高（三次拍板）：均匀缩放会让邻卡边缘互相覆盖，y 轴单向缩放宽度不动、
            // 永不交叠；代价是内容随卡身轻微纵向拉伸，幅度内可接受。
            return view.scaleEffect(x: 1, y: 1 + delta, anchor: .bottom)
        }
        // 选中变更（档位距离变化）时，键盘凸的换挡和波浪交接与选中生长共用同一条
        // 曲线（DS.Anim.cardGrow）——同一张卡的「尺寸生长/回缩」与「波浪隆起/放平」
        // 必须同步，时长错位会互相打架。指针/滚动驱动的连续变化不经此键、不受影响。
        .animation(
            MotionPolicy.prefersReducedMotion ? nil : DS.Anim.cardGrow,
            value: indexDistance
        )
    }
}

extension View {
    /// 波浪放大（「完整特效」）。挂在卡片视觉组合的最外层、槽位 frame 之内。
    func waveMagnify(_ wave: WaveMagnifyState, indexDistance: Int) -> some View {
        modifier(WaveMagnifyModifier(wave: wave, indexDistance: indexDistance))
    }
}
