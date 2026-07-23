import Foundation

enum BackupChange: Hashable, Sendable {
    case settings
    case ignoreList
    case history
}

struct BackupSelection: Codable, Equatable, Sendable {
    var settings: Bool
    var ignoreList: Bool
    var history: Bool

    var isEmpty: Bool {
        !settings && !ignoreList && !history
    }

    static var currentSettings: BackupSelection {
        BackupSelection(
            settings: Settings.backupIncludeSettings,
            ignoreList: Settings.backupIncludeIgnoreList,
            history: Settings.backupIncludeHistory
        )
    }
}

struct BackupFile: Identifiable, Equatable, Sendable {
    let url: URL
    let displayName: String
    let modifiedAt: Date
    let isPlaceholder: Bool

    var id: URL { url }
}

struct BackupManifest: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let appVersion: String
    let createdAt: Date
    let deviceName: String
    let contents: BackupSelection
}

struct BackupImportResult: Equatable, Sendable {
    var history = HistoryMergeResult(insertedCount: 0, duplicateCount: 0)
    var restoredSettings = false
    var restoredIgnoreList = false
    var requestedLaunchAtLogin: Bool?
}

enum BackupError: LocalizedError, Equatable {
    case emptySelection
    case invalidArchive
    case unsupportedFormat(Int)
    case missingComponent(String)
    case archiveToolFailed(String)
    case cloudDriveUnavailable
    case cloudDownloadTimedOut

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            "请至少选择一种要备份的数据。"
        case .invalidArchive:
            "这不是有效的 Clipstrate 备份文件。"
        case let .unsupportedFormat(version):
            "暂不支持此备份格式（版本 \(version)）。"
        case let .missingComponent(name):
            "备份文件缺少 \(name)。"
        case let .archiveToolFailed(message):
            "无法处理备份文件：\(message)"
        case .cloudDriveUnavailable:
            "请先在系统设置中开启 iCloud 云盘。"
        case .cloudDownloadTimedOut:
            "iCloud 下载超时，请稍后重试。"
        }
    }
}

enum BackupNaming {
    static func cloudFilename(
        now: Date = Date(),
        deviceName: String = Host.current().localizedName ?? "Mac"
    ) -> String {
        let safeDevice = deviceName
            .replacingOccurrences(
                of: #"[^A-Za-z0-9\p{Han}._-]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "Clipstrate-\(safeDevice.isEmpty ? "Mac" : safeDevice)-\(formatter.string(from: now)).clipstrate"
    }

    static func restoreSnapshotFilename(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Clipstrate-before-restore-\(formatter.string(from: now)).clipstrate"
    }
}
