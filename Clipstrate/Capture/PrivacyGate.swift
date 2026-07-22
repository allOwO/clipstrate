import AppKit

/// 剪贴板访问态（对 accessBehavior 的语义封装）。
enum PasteboardAccess: Sendable, Equatable {
    case allowed   // .alwaysAllow
    case ask       // .default / .ask（读取会弹系统提示）
    case denied    // .alwaysDeny
    case unknown
}

/// 接缝②（02 §8）：剪贴板隐私 API（`accessBehavior` / `detect`）集中隔离于此。
///
/// 部署目标 macOS 26 起 `accessBehavior`（macOS 15.4+）恒可用，当前无需 `#available`；
/// 将来若下调部署目标，版本判断只在本文件内加——业务代码永远零 `#available`。
/// 旧系统兼容模式下本门短路为 `.allowed`。
enum PrivacyGate {
    static var pasteboardAccess: PasteboardAccess {
        map(NSPasteboard.general.accessBehavior)
    }

    static var isPasteboardAllowed: Bool {
        pasteboardAccess == .allowed
    }

    /// accessBehavior → 语义态的纯映射（便于单测）。
    static func map(_ behavior: NSPasteboard.AccessBehavior) -> PasteboardAccess {
        switch behavior {
        case .alwaysAllow: return .allowed
        case .alwaysDeny: return .denied
        case .ask, .default: return .ask
        @unknown default: return .unknown
        }
    }

    /// 触发一次真实读取，促使系统弹出「允许访问其他 App 的剪贴板」提示（Onboarding 第 1 步）。
    static func triggerPasteboardPrompt() {
        _ = NSPasteboard.general.string(forType: .string)
    }

    /// 打开「系统设置 › 隐私与安全性」（剪贴板被拒时引导）。
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
