import Foundation

/// 自动备份排队状态快照，供设置页状态行展示（01 §7.2）。
struct AutomaticBackupQueueStatus: Sendable, Equatable {
    let nextFireAt: Date?
    let hasPendingChanges: Bool

    static let idle = AutomaticBackupQueueStatus(nextFireAt: nil, hasPendingChanges: false)
}

/// 事件驱动的自动备份调度器：无轮询。只有捕获/设置/忽略名单发生变化时，
/// 才创建一个可取消的延迟任务；含历史库的全量包距上次全量不足 fullBackupInterval
/// 时顺延到间隔期满。触发点只提前不推后（首个变化起最多等一个 debounce，
/// 持续复制不会无限顺延）；iCloud 不可用或写入失败时保留待办、按 retryDuration 重试。
actor AutomaticBackupCoordinator {
    private let backupService: BackupService
    private let transport: any BackupTransport
    private let debounceDuration: Duration
    private let retryDuration: Duration
    private let fullBackupInterval: Duration
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    private var pendingChanges: Set<BackupChange> = []
    private var scheduledTask: Task<Void, Never>?
    private var scheduledFireAt: Date?
    private var onQueueStatusChange: (@Sendable (AutomaticBackupQueueStatus) -> Void)?

    init(
        backupService: BackupService,
        transport: any BackupTransport,
        debounceDuration: Duration = .seconds(300),
        retryDuration: Duration = .seconds(600),
        fullBackupInterval: Duration = .seconds(600),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.backupService = backupService
        self.transport = transport
        self.debounceDuration = debounceDuration
        self.retryDuration = retryDuration
        self.fullBackupInterval = fullBackupInterval
        self.calendar = calendar
        self.now = now
    }

    /// 注册排队状态回调；注册时立即回放一次当前状态。
    func setQueueStatusHandler(
        _ handler: @escaping @Sendable (AutomaticBackupQueueStatus) -> Void
    ) {
        onQueueStatusChange = handler
        notifyQueueStatus()
    }

    func schedule(_ change: BackupChange) {
        schedule(Set([change]))
    }

    func schedule(_ changes: Set<BackupChange>) {
        guard Settings.backupAutoICloud else {
            cancel()
            return
        }
        pendingChanges.formUnion(changes)
        schedule(after: debounceDuration)
        notifyQueueStatus()
    }

    func cancel() {
        scheduledTask?.cancel()
        scheduledTask = nil
        scheduledFireAt = nil
        pendingChanges.removeAll()
        notifyQueueStatus()
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

    /// 只把触发点提前、不推后：已排定更早的任务时新变化只并入待办。
    private func schedule(after duration: Duration) {
        let target = now().addingTimeInterval(duration.timeInterval)
        if scheduledTask != nil, let fireAt = scheduledFireAt, fireAt <= target { return }
        scheduledTask?.cancel()
        scheduledFireAt = target
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
        defer { notifyQueueStatus() }
        scheduledTask = nil
        scheduledFireAt = nil
        guard Settings.backupAutoICloud else { return }
        guard transport.isAvailable else {
            // iCloud Drive 暂不可用：待办保留，稍后重试而不是等下一次变化。
            schedule(after: retryDuration)
            return
        }
        let date = now()
        let changes = pendingChanges
        pendingChanges.removeAll()

        let historyRequested = changes.contains(.history) && Settings.backupIncludeHistory
        let nextFullAt = Date(timeIntervalSince1970: Settings.backupLastFullUploadAt)
            .addingTimeInterval(fullBackupInterval.timeInterval)
        let canWriteFull = historyRequested && date >= nextFullAt
        if historyRequested && !canWriteFull {
            // 距上次全量不足间隔：历史留在待办，间隔期满自动补传。
            pendingChanges.insert(.history)
            schedule(after: .seconds(max(0.001, nextFullAt.timeIntervalSince(date))))
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
            schedule(after: retryDuration)
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

    private func notifyQueueStatus() {
        onQueueStatusChange?(AutomaticBackupQueueStatus(
            nextFireAt: scheduledTask == nil ? nil : scheduledFireAt,
            hasPendingChanges: !pendingChanges.isEmpty
        ))
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
