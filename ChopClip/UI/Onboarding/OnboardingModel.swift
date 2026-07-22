import SwiftUI

/// Onboarding 的权限状态源。视图定时轮询 `refresh()` 更新 ✓（01 §8）。
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var pasteboardAllowed: Bool
    @Published var axTrusted: Bool

    init() {
        pasteboardAllowed = PrivacyGate.isPasteboardAllowed
        axTrusted = AXPermission.isTrusted
    }

    func refresh() {
        let allowed = PrivacyGate.isPasteboardAllowed
        let trusted = AXPermission.isTrusted
        if allowed != pasteboardAllowed { pasteboardAllowed = allowed }
        if trusted != axTrusted { axTrusted = trusted }
    }
}
