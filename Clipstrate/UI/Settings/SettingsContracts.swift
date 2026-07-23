import Foundation
import ServiceManagement

enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case shortcuts
    case interaction
    case display
    case storage
    case backup
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
        case .about: "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .shortcuts: "command"
        case .interaction: "arrow.left.arrow.right"
        case .display: "rectangle.on.rectangle"
        case .storage: "clock.arrow.circlepath"
        case .backup: "icloud.fill"
        case .about: "scissors"
        }
    }

    var tintRGB: (red: Double, green: Double, blue: Double) {
        switch self {
        case .general: (0x8e / 255, 0x8e / 255, 0x93 / 255)
        case .shortcuts: (1, 0x9f / 255, 0x0a / 255)
        case .interaction: (0xbf / 255, 0x5a / 255, 0xf2 / 255)
        case .display: (0x0a / 255, 0x84 / 255, 1)
        case .storage: (0x30 / 255, 0xb0 / 255, 0xc7 / 255)
        case .backup: (0x34 / 255, 0xc7 / 255, 0x59 / 255)
        case .about: (1, 0x37 / 255, 0x5f / 255)
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
        SettingsKey.autoClose,
        SettingsKey.plainTextDefault,
        SettingsKey.panelStyle,
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
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
struct SystemLoginItemManager: LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled { try service.register() }
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
