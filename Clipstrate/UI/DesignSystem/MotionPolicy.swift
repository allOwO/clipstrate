import SwiftUI
import AppKit

/// 接缝③（02 §8）：动效降级开关。「减弱动态效果」（或将来兼容模式）下，把炸开/聚拢/
/// morphing 等降级为淡入淡出。业务代码统一走 `MotionPolicy.animation(...)` / `.overlayTransition`。
@MainActor
enum MotionPolicy {
    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 减弱动态时把完整动画降级为短促淡入淡出。
    static func animation(_ full: Animation, reducedDuration: Double = DS.Anim.closeDuration) -> Animation {
        prefersReducedMotion ? .easeInOut(duration: reducedDuration) : full
    }

    /// 分词层进出过渡：统一淡入淡出（减弱动态时也一致，避免位移）。
    static var overlayTransition: AnyTransition { .opacity }

    /// 「完整特效」（波浪放大等纯装饰动效）是否生效：设置开、且未开减弱动态。
    /// 纯装饰效果在减弱动态下整体停用（不是降级），业务代码只问这一个口。
    static var fullEffectsActive: Bool {
        !prefersReducedMotion && Settings.fullEffects
    }
}
