import XCTest
@testable import Clipstrate

final class AutomaticBackupCoordinatorTests: XCTestCase {
    private let managedKeys = [
        SettingsKey.backupAutoICloud,
        SettingsKey.backupIncludeSettings,
        SettingsKey.backupIncludeIgnoreList,
        SettingsKey.backupIncludeHistory,
        SettingsKey.backupLastUploadAt,
        SettingsKey.backupLastFullUploadAt,
        SettingsKey.backupLastSmallSignature,
        SettingsKey.backupLastFullSignature,
        SettingsKey.plainTextDefault,
    ]

    func testAutomaticBackupDebouncesAndSkipsUnchangedContent() async throws {
        let defaults = UserDefaults.standard
        let saved = snapshotDefaults(defaults)
        defer { restoreDefaults(saved, in: defaults) }
        defaults.set(true, forKey: SettingsKey.backupAutoICloud)
        defaults.set(true, forKey: SettingsKey.backupIncludeSettings)
        defaults.set(false, forKey: SettingsKey.backupIncludeIgnoreList)
        defaults.set(false, forKey: SettingsKey.backupIncludeHistory)
        defaults.set("", forKey: SettingsKey.backupLastSmallSignature)

        let fixture = try makeFixture("debounce")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let coordinator = AutomaticBackupCoordinator(
            backupService: fixture.service,
            transport: fixture.transport,
            debounceDuration: .milliseconds(20),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        await coordinator.schedule(.settings)
        await coordinator.schedule(.settings)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(try fixture.transport.backups().count, 1)

        for file in try fixture.transport.backups() {
            try FileManager.default.removeItem(at: file.url)
        }
        await coordinator.schedule(.settings)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(try fixture.transport.backups().isEmpty)

        defaults.set(!Settings.plainTextDefault, forKey: SettingsKey.plainTextDefault)
        await coordinator.schedule(.settings)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(try fixture.transport.backups().count, 1)
        await coordinator.cancel()
    }

    func testRepeatedChangesDoNotPostponeScheduledBackup() async throws {
        let defaults = UserDefaults.standard
        let saved = snapshotDefaults(defaults)
        defer { restoreDefaults(saved, in: defaults) }
        defaults.set(true, forKey: SettingsKey.backupAutoICloud)
        defaults.set(true, forKey: SettingsKey.backupIncludeSettings)
        defaults.set(false, forKey: SettingsKey.backupIncludeIgnoreList)
        defaults.set(false, forKey: SettingsKey.backupIncludeHistory)
        defaults.set("", forKey: SettingsKey.backupLastSmallSignature)

        let fixture = try makeFixture("no-postpone")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let coordinator = AutomaticBackupCoordinator(
            backupService: fixture.service,
            transport: fixture.transport,
            debounceDuration: .milliseconds(400),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        // 每 100ms 一次新变化，旧实现会不断重置计时、迟迟不备份；
        // 新实现从首个变化起最多等一个 debounce。
        await coordinator.schedule(.settings)
        for _ in 0..<7 {
            try await Task.sleep(for: .milliseconds(100))
            await coordinator.schedule(.settings)
        }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(try fixture.transport.backups().count, 1)
        await coordinator.cancel()
    }

    func testRetriesWhileCloudDriveUnavailable() async throws {
        let defaults = UserDefaults.standard
        let saved = snapshotDefaults(defaults)
        defer { restoreDefaults(saved, in: defaults) }
        defaults.set(true, forKey: SettingsKey.backupAutoICloud)
        defaults.set(true, forKey: SettingsKey.backupIncludeSettings)
        defaults.set(false, forKey: SettingsKey.backupIncludeIgnoreList)
        defaults.set(false, forKey: SettingsKey.backupIncludeHistory)
        defaults.set("", forKey: SettingsKey.backupLastSmallSignature)

        let fixture = try makeFixture("retry")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let coordinator = AutomaticBackupCoordinator(
            backupService: fixture.service,
            transport: fixture.transport,
            debounceDuration: .milliseconds(20),
            retryDuration: .milliseconds(60),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        // 模拟 iCloud Drive 掉线：首个触发点落空，待办保留。
        try FileManager.default.removeItem(at: fixture.transport.cloudDocsRoot)
        await coordinator.schedule(.settings)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.transport.directoryURL.path)
        )

        // 恢复挂载点后，无需新的变化事件，重试自行完成备份。
        try FileManager.default.createDirectory(
            at: fixture.transport.cloudDocsRoot,
            withIntermediateDirectories: true
        )
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(try fixture.transport.backups().count, 1)
        await coordinator.cancel()
    }

    func testAutomaticHistoryBackupRespectsFullInterval() async throws {
        let defaults = UserDefaults.standard
        let saved = snapshotDefaults(defaults)
        defer { restoreDefaults(saved, in: defaults) }
        defaults.set(true, forKey: SettingsKey.backupAutoICloud)
        defaults.set(false, forKey: SettingsKey.backupIncludeSettings)
        defaults.set(false, forKey: SettingsKey.backupIncludeIgnoreList)
        defaults.set(true, forKey: SettingsKey.backupIncludeHistory)
        defaults.set(0, forKey: SettingsKey.backupLastFullUploadAt)
        defaults.set("", forKey: SettingsKey.backupLastFullSignature)

        let fixture = try makeFixture("interval")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let coordinator = AutomaticBackupCoordinator(
            backupService: fixture.service,
            transport: fixture.transport,
            debounceDuration: .milliseconds(20),
            fullBackupInterval: .milliseconds(500)
        )

        try await fixture.history.upsert(
            ClipItem(kind: .text, plainText: "one", contentHash: "one")
        )
        await coordinator.schedule(.history)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(try fixture.transport.backups().count, 1)

        // 间隔未满：新历史变化顺延，不立即产生第二份全量。
        for file in try fixture.transport.backups() {
            try FileManager.default.removeItem(at: file.url)
        }
        try await fixture.history.upsert(
            ClipItem(kind: .text, plainText: "two", contentHash: "two")
        )
        await coordinator.schedule(.history)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(try fixture.transport.backups().isEmpty)

        // 间隔期满后无需新的变化事件，顺延的全量自动补传。
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(try fixture.transport.backups().count, 1)
        await coordinator.cancel()
    }

    private struct Fixture {
        let root: URL
        let history: HistoryStore
        let service: BackupService
        let transport: CloudDocsTransport
    }

    private func makeFixture(_ name: String) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ClipstrateAutomaticBackupTests-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
        let cloudRoot = root.appendingPathComponent("CloudDocs", isDirectory: true)
        let dataRoot = root.appendingPathComponent("Data", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        let history = try HistoryStore(
            path: dataRoot.appendingPathComponent("history.sqlite").path
        )
        let blobs = try BlobStore(
            blobsDir: dataRoot.appendingPathComponent("blobs", isDirectory: true),
            thumbsDir: dataRoot.appendingPathComponent("thumbs", isDirectory: true)
        )
        let ignores = IgnoreListStore(
            fileURL: dataRoot.appendingPathComponent("ignore-list.json")
        )
        return Fixture(
            root: root,
            history: history,
            service: BackupService(
                historyStore: history,
                blobStore: blobs,
                ignoreListStore: ignores
            ),
            transport: CloudDocsTransport(cloudDocsRoot: cloudRoot)
        )
    }

    private func snapshotDefaults(_ defaults: UserDefaults) -> [String: Any] {
        managedKeys.reduce(into: [:]) { result, key in
            if let value = defaults.object(forKey: key) {
                result[key] = value
            }
        }
    }

    private func restoreDefaults(_ values: [String: Any], in defaults: UserDefaults) {
        for key in managedKeys {
            if let value = values[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
