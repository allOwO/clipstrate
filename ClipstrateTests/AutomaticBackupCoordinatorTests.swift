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

    func testAutomaticHistoryBackupRunsAtMostOncePerDay() async throws {
        let defaults = UserDefaults.standard
        let saved = snapshotDefaults(defaults)
        defer { restoreDefaults(saved, in: defaults) }
        defaults.set(true, forKey: SettingsKey.backupAutoICloud)
        defaults.set(false, forKey: SettingsKey.backupIncludeSettings)
        defaults.set(false, forKey: SettingsKey.backupIncludeIgnoreList)
        defaults.set(true, forKey: SettingsKey.backupIncludeHistory)
        defaults.set(0, forKey: SettingsKey.backupLastFullUploadAt)
        defaults.set("", forKey: SettingsKey.backupLastFullSignature)

        let fixture = try makeFixture("daily")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let coordinator = AutomaticBackupCoordinator(
            backupService: fixture.service,
            transport: fixture.transport,
            debounceDuration: .milliseconds(20),
            now: { date }
        )

        try await fixture.history.upsert(
            ClipItem(kind: .text, plainText: "one", contentHash: "one")
        )
        await coordinator.schedule(.history)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(try fixture.transport.backups().count, 1)

        for file in try fixture.transport.backups() {
            try FileManager.default.removeItem(at: file.url)
        }
        try await fixture.history.upsert(
            ClipItem(kind: .text, plainText: "two", contentHash: "two")
        )
        await coordinator.schedule(.history)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(try fixture.transport.backups().isEmpty)
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
