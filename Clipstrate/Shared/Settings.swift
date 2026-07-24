import Foundation

/// UserDefaults key 常量表（02 §5）。所有键集中于此，禁止在别处写裸字符串。
///
/// SwiftUI 视图用 `@AppStorage(SettingsKey.xxx)` 绑定；非 UI 代码用
/// `Settings.xxx` 读取（见下）。两者共用同一批键，保证一致。
enum SettingsKey {
    // general
    static let launchAtLogin = "general.launchAtLogin"
    // hotkey（快捷键本体由 KeyboardShortcuts 管理，见 T1.1；此处仅数字直贴修饰键）
    static let digitModifier = "hotkey.digitModifier"
    // interaction
    static let pressAction = "interaction.pressAction"
    static let returnAction = "interaction.returnAction"
    static let plainTextDefault = "interaction.plainTextDefault"
    // display
    static let panelStyle = "display.panelStyle"
    static let panelItemCount = "display.itemCount"
    // store
    static let diskCapMB = "store.diskCapMB"
    static let retention = "store.retention"
    // backup
    static let backupAutoICloud = "backup.autoICloud"
    static let backupIncludeSettings = "backup.include.settings"
    static let backupIncludeIgnoreList = "backup.include.ignoreList"
    static let backupIncludeHistory = "backup.include.history"
    static let backupLastUploadAt = "backup.lastUploadAt"
    // 自动备份内部状态，不在设置窗口展示，也不写入备份包。
    static let backupLastFullUploadAt = "backup.lastFullUploadAt"
    static let backupLastSmallSignature = "backup.lastSmallSignature"
    static let backupLastFullSignature = "backup.lastFullSignature"
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

struct SettingsBackupDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var formatVersion = currentVersion
    var booleans: [String: Bool]
    var integers: [String: Int]
    var strings: [String: String]

    var requestedLaunchAtLogin: Bool? {
        booleans[SettingsKey.launchAtLogin]
    }
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
            SettingsKey.digitModifier: DigitModifier.cmd.rawValue,
            SettingsKey.pressAction: ClickAction.paste.rawValue,
            SettingsKey.returnAction: ClickAction.paste.rawValue,
            SettingsKey.plainTextDefault: false,
            SettingsKey.panelStyle: PanelStyle.glass.rawValue,
            SettingsKey.panelItemCount: 50,
            SettingsKey.diskCapMB: 512,
            SettingsKey.retention: Retention.month.rawValue,
            SettingsKey.backupAutoICloud: true,
            SettingsKey.backupIncludeSettings: true,
            SettingsKey.backupIncludeIgnoreList: true,
            SettingsKey.backupIncludeHistory: true,
            SettingsKey.backupLastUploadAt: 0.0,
            SettingsKey.backupLastFullUploadAt: 0.0,
            SettingsKey.backupLastSmallSignature: "",
            SettingsKey.backupLastFullSignature: "",
            SettingsKey.onboardingDone: false,
        ])
    }

    // MARK: 读取

    /// `register(defaults:)` 不会写入持久域；借此区分“首次启动使用默认值”
    /// 与用户已经明确设置过登录项偏好。
    static var hasPersistedLaunchAtLoginPreference: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        return hasLaunchAtLoginPreference(
            in: store.persistentDomain(forName: bundleIdentifier)
        )
    }

    static func hasLaunchAtLoginPreference(in persistentDomain: [String: Any]?) -> Bool {
        persistentDomain?[SettingsKey.launchAtLogin] != nil
    }

    static var launchAtLogin: Bool { store.bool(forKey: SettingsKey.launchAtLogin) }
    static var plainTextDefault: Bool { store.bool(forKey: SettingsKey.plainTextDefault) }
    static var diskCapMB: Int { store.integer(forKey: SettingsKey.diskCapMB) }

    /// 唤出面板默认展示的最近条数（限幅 10–200；搜索不受此限，见 searchResultLimit）。
    static var panelItemCount: Int {
        let value = store.integer(forKey: SettingsKey.panelItemCount)
        return value == 0 ? 50 : min(max(value, 10), 200)
    }

    static var digitModifier: DigitModifier {
        DigitModifier(rawValue: store.string(forKey: SettingsKey.digitModifier) ?? "") ?? .cmd
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
    static var backupLastFullUploadAt: Double {
        store.double(forKey: SettingsKey.backupLastFullUploadAt)
    }
    static var backupLastSmallSignature: String {
        store.string(forKey: SettingsKey.backupLastSmallSignature) ?? ""
    }
    static var backupLastFullSignature: String {
        store.string(forKey: SettingsKey.backupLastFullSignature) ?? ""
    }
    static var onboardingDone: Bool { store.bool(forKey: SettingsKey.onboardingDone) }

    // MARK: 写入（非 UI 代码早期写入的少量键；其余由设置窗口经 @AppStorage 写）

    static func setLaunchAtLogin(_ value: Bool) {
        store.set(value, forKey: SettingsKey.launchAtLogin)
    }

    static func setOnboardingDone(_ value: Bool) {
        store.set(value, forKey: SettingsKey.onboardingDone)
    }
    static func setBackupLastUploadAt(_ value: Double) {
        store.set(value, forKey: SettingsKey.backupLastUploadAt)
    }
    static func setBackupLastFullUploadAt(_ value: Double) {
        store.set(value, forKey: SettingsKey.backupLastFullUploadAt)
    }
    static func setBackupLastSmallSignature(_ value: String) {
        store.set(value, forKey: SettingsKey.backupLastSmallSignature)
    }
    static func setBackupLastFullSignature(_ value: String) {
        store.set(value, forKey: SettingsKey.backupLastFullSignature)
    }

    // MARK: 备份

    static func makeBackupDocument() -> SettingsBackupDocument {
        let allValues = store.dictionaryRepresentation()
        let hotkeys = allValues.reduce(into: [String: String]()) { result, pair in
            guard pair.key.hasPrefix("KeyboardShortcuts_"),
                  let value = pair.value as? String else { return }
            result[pair.key] = value
        }
        var strings: [String: String] = [
            SettingsKey.digitModifier: digitModifier.rawValue,
            SettingsKey.pressAction: pressAction.rawValue,
            SettingsKey.returnAction: returnAction.rawValue,
            SettingsKey.panelStyle: panelStyle.rawValue,
            SettingsKey.retention: retention.rawValue,
        ]
        strings.merge(hotkeys) { _, latest in latest }

        return SettingsBackupDocument(
            booleans: [
                SettingsKey.launchAtLogin: launchAtLogin,
                SettingsKey.plainTextDefault: plainTextDefault,
                SettingsKey.backupAutoICloud: backupAutoICloud,
                SettingsKey.backupIncludeSettings: backupIncludeSettings,
                SettingsKey.backupIncludeIgnoreList: backupIncludeIgnoreList,
                SettingsKey.backupIncludeHistory: backupIncludeHistory,
            ],
            integers: [
                SettingsKey.diskCapMB: diskCapMB,
                SettingsKey.panelItemCount: panelItemCount,
            ],
            strings: strings
        )
    }

    static func restore(from document: SettingsBackupDocument) throws {
        guard document.formatVersion == SettingsBackupDocument.currentVersion else {
            throw CocoaError(.fileReadUnknown)
        }
        for (key, value) in document.booleans where backupBooleanKeys.contains(key) {
            store.set(value, forKey: key)
        }
        for (key, value) in document.integers where backupIntegerKeys.contains(key) {
            guard key != SettingsKey.diskCapMB || [256, 512, 1_024, 2_048].contains(value) else {
                continue
            }
            guard key != SettingsKey.panelItemCount || [20, 30, 50, 80, 100].contains(value) else {
                continue
            }
            store.set(value, forKey: key)
        }
        for (key, value) in document.strings where isAllowedBackupString(key: key, value: value) {
            store.set(value, forKey: key)
        }
    }

    private static let backupBooleanKeys: Set<String> = [
        SettingsKey.launchAtLogin,
        SettingsKey.plainTextDefault,
        SettingsKey.backupAutoICloud,
        SettingsKey.backupIncludeSettings,
        SettingsKey.backupIncludeIgnoreList,
        SettingsKey.backupIncludeHistory,
    ]

    private static let backupIntegerKeys: Set<String> = [
        SettingsKey.diskCapMB,
        SettingsKey.panelItemCount,
    ]

    private static let backupHotkeyKeys: Set<String> = [
        "KeyboardShortcuts_hotkey.summon",
        "KeyboardShortcuts_hotkey.chop",
        "KeyboardShortcuts_hotkey.stackToggle",
        "KeyboardShortcuts_hotkey.stackPaste",
    ]

    private static func isAllowedBackupString(key: String, value: String) -> Bool {
        switch key {
        case SettingsKey.digitModifier:
            DigitModifier(rawValue: value) != nil
        case SettingsKey.pressAction, SettingsKey.returnAction:
            ClickAction(rawValue: value) != nil
        case SettingsKey.panelStyle:
            PanelStyle(rawValue: value) != nil
        case SettingsKey.retention:
            Retention(rawValue: value) != nil
        default:
            backupHotkeyKeys.contains(key)
        }
    }
}
