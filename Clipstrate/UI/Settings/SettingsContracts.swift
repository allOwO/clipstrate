import Foundation
import ServiceManagement

enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case shortcuts
    case interaction
    case display
    case storage
    case backup
    case permissions
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "通用"
        case .shortcuts: "快捷键"
        case .interaction: "交互"
        case .display: "显示"
        case .storage: "历史与存储"
        case .backup: "数据备份"
        case .permissions: "权限"
        case .about: "关于"
        }
    }

    /// 线性（非 fill）符号：配合极简单色 + 玻璃薄片的侧栏图标。
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "command"
        case .interaction: "arrow.left.arrow.right"
        case .display: "rectangle.on.rectangle"
        case .storage: "clock.arrow.circlepath"
        case .backup: "icloud"
        case .permissions: "lock.shield"
        case .about: "scissors"
        }
    }
}

enum SettingsScrollSpy {
    nonisolated static func section(
        offsets: [SettingsSection: CGFloat],
        isAtBottom: Bool,
        threshold: CGFloat = 80
    ) -> SettingsSection {
        if isAtBottom { return .about }
        return offsets
            .filter { $0.value <= threshold }
            .max(by: { $0.value < $1.value })?
            .key ?? .general
    }
}

enum SettingsCatalog {
    static let defaultWindowSize = CGSize(width: 780, height: 560)
    static let diskCapsMB = [256, 512, 1_024, 2_048]
    static let retentions = Retention.allCases

    /// Every UserDefaults key surfaced by the settings window. Hotkey recorder
    /// values are owned and persisted by KeyboardShortcuts.Name.
    static let windowKeys = [
        SettingsKey.launchAtLogin,
        SettingsKey.digitModifier,
        SettingsKey.pressAction,
        SettingsKey.returnAction,
        SettingsKey.plainTextDefault,
        SettingsKey.panelStyle,
        SettingsKey.panelItemCount,
        SettingsKey.diskCapMB,
        SettingsKey.retention,
        SettingsKey.backupAutoICloud,
        SettingsKey.backupIncludeSettings,
        SettingsKey.backupIncludeIgnoreList,
        SettingsKey.backupIncludeHistory,
        SettingsKey.backupLastUploadAt,
    ]
}

enum SettingsBackupState: Equatable, Sendable {
    case unavailable
    case available(status: String)
}

@MainActor
struct SettingsActions {
    var settingChanged: (String) -> Void
    var backupState: SettingsBackupState
    var backupNow: () -> Void
    var restoreFromCloud: () -> Void
    var importBackup: () -> Void
    var exportBackup: () -> Void

    init(
        settingChanged: @escaping (String) -> Void = { _ in },
        backupState: SettingsBackupState = .unavailable,
        backupNow: @escaping () -> Void = {},
        restoreFromCloud: @escaping () -> Void = {},
        importBackup: @escaping () -> Void = {},
        exportBackup: @escaping () -> Void = {}
    ) {
        self.settingChanged = settingChanged
        self.backupState = backupState
        self.backupNow = backupNow
        self.restoreFromCloud = restoreFromCloud
        self.importBackup = importBackup
        self.exportBackup = exportBackup
    }
}

@MainActor
protocol LoginItemManaging {
    var state: LoginItemState { get }
    func setEnabled(_ enabled: Bool) throws
}

enum LoginItemState: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isSelected: Bool {
        self == .enabled || self == .requiresApproval
    }

    var notice: String? {
        switch self {
        case .requiresApproval:
            "已添加登录项，请在“系统设置 › 通用 › 登录项与扩展”中允许 Clipstrate。"
        case .unavailable:
            "当前构建无法注册登录项。"
        case .disabled, .enabled:
            nil
        }
    }
}

@MainActor
struct SystemLoginItemManager: LoginItemManaging {
    var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            switch service.status {
            case .notRegistered, .notFound:
                try service.register()
            case .enabled, .requiresApproval:
                break
            @unknown default:
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }
}

extension Retention {
    var settingsLabel: String {
        switch self {
        case .day: "天"
        case .week: "周"
        case .month: "月"
        case .quarter: "季度"
        case .halfYear: "半年"
        case .year: "年"
        case .unlimited: "无限制"
        }
    }
}

extension DigitModifier {
    var settingsLabel: String {
        switch self {
        case .none: "暂无"
        case .cmd: "⌘ + 1~9"
        case .opt: "⌥ + 1~9"
        }
    }
}

extension ClickAction {
    var settingsLabel: String {
        switch self {
        case .paste: "输入剪贴板内容"
        case .copy: "仅复制"
        }
    }
}
