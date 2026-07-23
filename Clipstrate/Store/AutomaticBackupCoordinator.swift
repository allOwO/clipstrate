import Foundation

/// 事件驱动的自动备份调度器：无轮询。只有捕获/设置/忽略名单发生变化时，
/// 才创建一个可取消的延迟任务；同日已有全量备份时只保留一个跨日单次任务。
actor AutomaticBackupCoordinator {
    private let backupService: BackupService
    private let transport: any BackupTransport
    private let debounceDuration: Duration
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    private var pendingChanges: Set<BackupChange> = []
    private var scheduledTask: Task<Void, Never>?

    init(
        backupService: BackupService,
        transport: any BackupTransport,
        debounceDuration: Duration = .seconds(300),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.backupService = backupService
        self.transport = transport
        self.debounceDuration = debounceDuration
        self.calendar = calendar
        self.now = now
    }

    func schedule(_ change: BackupChange) {
        guard Settings.backupAutoICloud else {
            cancel()
            return
        }
        pendingChanges.insert(change)
        schedule(after: debounceDuration)
    }

    func schedule(_ changes: Set<BackupChange>) {
        guard Settings.backupAutoICloud else {
            cancel()
            return
        }
        pendingChanges.formUnion(changes)
        schedule(after: debounceDuration)
    }

    func cancel() {
        scheduledTask?.cancel()
        scheduledTask = nil
        pendingChanges.removeAll()
    }

    @discardableResult
    func backupNow(selection: BackupSelection) async throws -> URL {
        let date = now()
        let signature = try await backupService.contentSignature(for: selection)
        let destination = try await writeBackup(selection: selection, at: date)
        try await recordSuccess(
            selection: selection,
            signature: signature,
            at: date
        )
        return destination
    }

    private func schedule(after duration: Duration) {
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                await self?.performPendingBackup()
            } catch {
                // Cancellation is the normal debounce path.
            }
        }
    }

    private func performPendingBackup() async {
        guard Settings.backupAutoICloud, transport.isAvailable else { return }
        let date = now()
        let changes = pendingChanges
        pendingChanges.removeAll()

        let historyRequested = changes.contains(.history) && Settings.backupIncludeHistory
        let canWriteFull = historyRequested && !calendar.isDate(
            Date(timeIntervalSince1970: Settings.backupLastFullUploadAt),
            inSameDayAs: date
        )
        if historyRequested && !canWriteFull {
            pendingChanges.insert(.history)
            scheduleAtStartOfNextDay(after: date)
        }

        let selection = BackupSelection(
            settings: Settings.backupIncludeSettings
                && (changes.contains(.settings) || canWriteFull),
            ignoreList: Settings.backupIncludeIgnoreList
                && (changes.contains(.ignoreList) || canWriteFull),
            history: canWriteFull
        )
        guard !selection.isEmpty else { return }

        do {
            let signature = try await backupService.contentSignature(for: selection)
            let previous = selection.history
                ? Settings.backupLastFullSignature
                : Settings.backupLastSmallSignature
            guard signature != previous else { return }
            _ = try await writeBackup(selection: selection, at: date)
            try await recordSuccess(
                selection: selection,
                signature: signature,
                at: date
            )
        } catch {
            pendingChanges.formUnion(changes)
            Log.store.error(
                "自动 iCloud 备份失败：\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func writeBackup(
        selection: BackupSelection,
        at date: Date
    ) async throws -> URL {
        try transport.prepareDirectory()
        let destination = transport.directoryURL.appendingPathComponent(
            BackupNaming.cloudFilename(now: date)
        )
        try await backupService.exportArchive(
            to: destination,
            selection: selection
        )
        try transport.pruneBackups(calendar: calendar)
        return destination
    }

    private func recordSuccess(
        selection: BackupSelection,
        signature: String,
        at date: Date
    ) async throws {
        Settings.setBackupLastUploadAt(date.timeIntervalSince1970)
        if selection.history {
            Settings.setBackupLastFullUploadAt(date.timeIntervalSince1970)
            Settings.setBackupLastFullSignature(signature)
            let small = BackupSelection(
                settings: selection.settings,
                ignoreList: selection.ignoreList,
                history: false
            )
            if !small.isEmpty {
                let smallSignature = try await backupService.contentSignature(for: small)
                Settings.setBackupLastSmallSignature(smallSignature)
            }
        } else {
            Settings.setBackupLastSmallSignature(signature)
        }
    }

    private func scheduleAtStartOfNextDay(after date: Date) {
        guard let nextDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) else { return }
        let delay = max(1, nextDay.timeIntervalSince(date))
        schedule(after: .seconds(delay))
    }
}
