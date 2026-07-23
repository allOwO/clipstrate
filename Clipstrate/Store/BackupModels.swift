import Foundation

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
        }
    }
}
