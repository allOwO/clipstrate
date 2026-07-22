import Foundation

/// UserDefaults key 常量表（02 §5）。所有键集中于此，禁止在别处写裸字符串。
///
/// SwiftUI 视图用 `@AppStorage(SettingsKey.xxx)` 绑定；非 UI 代码用
/// `Settings.xxx` 读取（见下）。两者共用同一批键，保证一致。
enum SettingsKey {
    // general
    static let launchAtLogin = "general.launchAtLogin"
    static let menuBarIconVisible = "general.menuBarIconVisible"
    static let soundEnabled = "general.soundEnabled"
    // hotkey（快捷键本体由 KeyboardShortcuts 管理，见 T1.1；此处仅数字直贴修饰键）
    static let digitModifier = "hotkey.digitModifier"
    // interaction
    static let pressAction = "interaction.pressAction"
    static let returnAction = "interaction.returnAction"
    static let autoClose = "interaction.autoClose"
    static let plainTextDefault = "interaction.plainTextDefault"
    // display
    static let panelStyle = "display.panelStyle"
    // store
    static let diskCapMB = "store.diskCapMB"
    static let retention = "store.retention"
    // backup
    static let backupAutoICloud = "backup.autoICloud"
    static let backupIncludeSettings = "backup.include.settings"
    static let backupIncludeIgnoreList = "backup.include.ignoreList"
    static let backupIncludeHistory = "backup.include.history"
    static let backupLastUploadAt = "backup.lastUploadAt"
    // onboarding
    static let onboardingDone = "onboarding.done"
}

// MARK: - 枚举型设置的取值域

/// 存储时限七档（01 §2/§6，升序）。`unlimited` 不清理。
enum Retention: String, CaseIterable, Sendable {
    case day, week, month, quarter, halfYear, year, unlimited

    /// 保留时长（秒）；`unlimited` → nil。月/季度/半年/年按固定天数近似。
    var maxAgeSeconds: TimeInterval? {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .quarter: return 90 * 86_400
        case .halfYear: return 182 * 86_400
        case .year: return 365 * 86_400
        case .unlimited: return nil
        }
    }
}

enum DigitModifier: String, CaseIterable, Sendable {
    case none, cmd, opt
}

/// press / return 动作：粘贴或仅复制。
enum ClickAction: String, CaseIterable, Sendable {
    case paste, copy
}

enum PanelStyle: String, CaseIterable, Sendable {
    case glass, compat
}

/// 设置读写的唯一入口（Shared）。基于 `UserDefaults.standard`（线程安全），
/// 非 actor 隔离，DB/后台任务亦可直接读。写入以 UI（`@AppStorage`）为主，
/// 少数早期由非 UI 代码写的键在此提供 setter。
enum Settings {
    private static var store: UserDefaults { .standard }

    /// 注册基线默认值（02 §5 表）。必须在任何读取前调用一次（AppDelegate 启动时）。
    static func registerDefaults() {
        store.register(defaults: [
            SettingsKey.launchAtLogin: true,
            SettingsKey.menuBarIconVisible: true,
            SettingsKey.soundEnabled: false,
            SettingsKey.digitModifier: DigitModifier.none.rawValue,
            SettingsKey.pressAction: ClickAction.paste.rawValue,
            SettingsKey.returnAction: ClickAction.paste.rawValue,
            SettingsKey.autoClose: true,
            SettingsKey.plainTextDefault: false,
            SettingsKey.panelStyle: PanelStyle.glass.rawValue,
            SettingsKey.diskCapMB: 512,
            SettingsKey.retention: Retention.month.rawValue,
            SettingsKey.backupAutoICloud: false,
            SettingsKey.backupIncludeSettings: true,
            SettingsKey.backupIncludeIgnoreList: true,
            SettingsKey.backupIncludeHistory: true,
            SettingsKey.backupLastUploadAt: 0.0,
            SettingsKey.onboardingDone: false,
        ])
    }

    // MARK: 读取

    static var launchAtLogin: Bool { store.bool(forKey: SettingsKey.launchAtLogin) }
    static var menuBarIconVisible: Bool { store.bool(forKey: SettingsKey.menuBarIconVisible) }
    static var soundEnabled: Bool { store.bool(forKey: SettingsKey.soundEnabled) }
    static var autoClose: Bool { store.bool(forKey: SettingsKey.autoClose) }
    static var plainTextDefault: Bool { store.bool(forKey: SettingsKey.plainTextDefault) }
    static var diskCapMB: Int { store.integer(forKey: SettingsKey.diskCapMB) }

    static var digitModifier: DigitModifier {
        DigitModifier(rawValue: store.string(forKey: SettingsKey.digitModifier) ?? "") ?? .none
    }
    static var pressAction: ClickAction {
        ClickAction(rawValue: store.string(forKey: SettingsKey.pressAction) ?? "") ?? .paste
    }
    static var returnAction: ClickAction {
        ClickAction(rawValue: store.string(forKey: SettingsKey.returnAction) ?? "") ?? .paste
    }
    static var panelStyle: PanelStyle {
        PanelStyle(rawValue: store.string(forKey: SettingsKey.panelStyle) ?? "") ?? .glass
    }
    static var retention: Retention {
        Retention(rawValue: store.string(forKey: SettingsKey.retention) ?? "") ?? .month
    }

    static var backupAutoICloud: Bool { store.bool(forKey: SettingsKey.backupAutoICloud) }
    static var backupIncludeSettings: Bool { store.bool(forKey: SettingsKey.backupIncludeSettings) }
    static var backupIncludeIgnoreList: Bool { store.bool(forKey: SettingsKey.backupIncludeIgnoreList) }
    static var backupIncludeHistory: Bool { store.bool(forKey: SettingsKey.backupIncludeHistory) }
    static var backupLastUploadAt: Double { store.double(forKey: SettingsKey.backupLastUploadAt) }
    static var onboardingDone: Bool { store.bool(forKey: SettingsKey.onboardingDone) }

    // MARK: 写入（非 UI 代码早期写入的少量键；其余由设置窗口经 @AppStorage 写）

    static func setOnboardingDone(_ value: Bool) {
        store.set(value, forKey: SettingsKey.onboardingDone)
    }
    static func setBackupLastUploadAt(_ value: Double) {
        store.set(value, forKey: SettingsKey.backupLastUploadAt)
    }
}
