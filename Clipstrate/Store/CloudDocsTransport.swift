import Foundation

protocol BackupTransport: Sendable {
    var directoryURL: URL { get }
    var isAvailable: Bool { get }

    func prepareDirectory() throws
    func backups() throws -> [BackupFile]
    func pruneBackups(calendar: Calendar) throws
    func materialize(
        _ file: BackupFile,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL
}

/// 免费版 iCloud Drive 备份通道。
///
/// Clipstrate 是非沙盒的个人工具，无法在不加入 Apple Developer Program 的前提下
/// 申请应用专属 ubiquity container。这里使用 macOS 的本地 iCloud Drive 挂载点，
/// 自动写入 `iCloud Drive/Clipstrate`，云端传输由系统负责。
struct CloudDocsTransport: BackupTransport {
    let cloudDocsRoot: URL

    init(cloudDocsRoot: URL = CloudDocsTransport.defaultCloudDocsRoot) {
        self.cloudDocsRoot = cloudDocsRoot
    }

    static var defaultCloudDocsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Mobile Documents/com~apple~CloudDocs",
                isDirectory: true
            )
    }

    var directoryURL: URL {
        cloudDocsRoot.appendingPathComponent(AppPaths.appFolderName, isDirectory: true)
    }

    var isAvailable: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: cloudDocsRoot.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    func prepareDirectory() throws {
        guard isAvailable else { throw BackupError.cloudDriveUnavailable }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func backups() throws -> [BackupFile] {
        guard isAvailable else { throw BackupError.cloudDriveUnavailable }
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: []
        )
        .compactMap(Self.backupFile)
        .sorted { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt {
                return lhs.displayName > rhs.displayName
            }
            return lhs.modifiedAt > rhs.modifiedAt
        }
    }

    /// 保留最近三份；更早的文件按自然周各留最新一份，总量最多八份。
    func pruneBackups(calendar: Calendar = .current) throws {
        let files = try backups()
        guard files.count > 3 else { return }

        var kept = Set(files.prefix(3).map(\.url))
        var keptWeeks = Set<DateComponents>()
        for file in files.dropFirst(3) where kept.count < 8 {
            let week = calendar.dateComponents(
                [.calendar, .yearForWeekOfYear, .weekOfYear],
                from: file.modifiedAt
            )
            if keptWeeks.insert(week).inserted {
                kept.insert(file.url)
            }
        }
        for file in files where !kept.contains(file.url) {
            try FileManager.default.removeItem(at: file.url)
        }
    }

    func materialize(
        _ file: BackupFile,
        progress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) async throws -> URL {
        let destination = Self.materializedURL(for: file)
        if !file.isPlaceholder { return file.url }

        try FileManager.default.startDownloadingUbiquitousItem(at: file.url)
        var lastReportedBucket = -1
        for _ in 0..<1_500 {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: destination.path) {
                let values = try? destination.resourceValues(
                    forKeys: [.ubiquitousItemDownloadingStatusKey]
                )
                if values?.ubiquitousItemDownloadingStatus == .current
                    || !FileManager.default.fileExists(atPath: file.url.path) {
                    progress(100)
                    return destination
                }
                let metadata = NSMetadataItem(url: destination)
                if let number = metadata?.value(
                    forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey
                ) as? NSNumber {
                    let percent = number.doubleValue
                    let bucket = Int(percent / 10)
                    if bucket != lastReportedBucket {
                        lastReportedBucket = bucket
                        progress(percent)
                    }
                } else if lastReportedBucket < 0 {
                    lastReportedBucket = 0
                    progress(nil)
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw BackupError.cloudDownloadTimedOut
    }

    private static func backupFile(_ url: URL) -> BackupFile? {
        let values = try? url.resourceValues(
            forKeys: [
                .contentModificationDateKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        )
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else { return nil }

        let name = url.lastPathComponent
        let placeholder = name.hasPrefix(".") && name.hasSuffix(".clipstrate.icloud")
        let regular = url.pathExtension.lowercased() == "clipstrate"
        guard placeholder || regular else { return nil }
        let displayName = placeholder
            ? String(name.dropFirst().dropLast(".icloud".count))
            : name
        return BackupFile(
            url: url,
            displayName: displayName,
            modifiedAt: values?.contentModificationDate ?? .distantPast,
            isPlaceholder: placeholder
        )
    }

    private static func materializedURL(for file: BackupFile) -> URL {
        guard file.isPlaceholder else { return file.url }
        return file.url.deletingLastPathComponent()
            .appendingPathComponent(file.displayName)
    }
}
