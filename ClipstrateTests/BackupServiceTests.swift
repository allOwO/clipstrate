import XCTest
@testable import Clipstrate

final class BackupServiceTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let history: HistoryStore
        let blobs: BlobStore
        let ignores: IgnoreListStore
        let service: BackupService
    }

    private func makeFixture(named name: String) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipstrateBackupTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let history = try HistoryStore(path: root.appendingPathComponent("history.sqlite").path)
        let blobs = try BlobStore(
            blobsDir: root.appendingPathComponent("blobs", isDirectory: true),
            thumbsDir: root.appendingPathComponent("thumbs", isDirectory: true)
        )
        let ignores = IgnoreListStore(fileURL: root.appendingPathComponent("ignore-list.json"))
        return Fixture(
            root: root,
            history: history,
            blobs: blobs,
            ignores: ignores,
            service: BackupService(
                historyStore: history,
                blobStore: blobs,
                ignoreListStore: ignores
            )
        )
    }

    func testArchiveRoundTripMergesHistoryBlobsAndIgnoreList() async throws {
        let source = try makeFixture(named: "source")
        let destination = try makeFixture(named: "destination")
        defer {
            try? FileManager.default.removeItem(at: source.root)
            try? FileManager.default.removeItem(at: destination.root)
        }

        try source.blobs.writeBlob(Data("image".utf8), name: "asset.png")
        try source.blobs.writeThumb(Data("thumb".utf8), name: "asset-thumb.png")
        let item = ClipItem(
            kind: .image,
            blobPath: "asset.png",
            thumbPath: "asset-thumb.png",
            contentHash: "backup-image",
            byteSize: 5
        )
        try await source.history.upsert(item, at: 123)
        let ignored = try XCTUnwrap(
            IgnoredApplication(bundleIdentifier: "com.example.private", displayName: "Private")
        )
        try await source.ignores.add(ignored)

        let archive = source.root.appendingPathComponent("roundtrip.clipstrate")
        let manifest = try await source.service.exportArchive(
            to: archive,
            selection: BackupSelection(settings: false, ignoreList: true, history: true)
        )

        XCTAssertEqual(manifest.formatVersion, BackupManifest.currentFormatVersion)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))

        let first = try await destination.service.importArchive(from: archive)
        XCTAssertEqual(first.history, HistoryMergeResult(insertedCount: 1, duplicateCount: 0))
        XCTAssertTrue(first.restoredIgnoreList)
        let countAfterFirstImport = try await destination.history.count()
        XCTAssertEqual(countAfterFirstImport, 1)
        XCTAssertTrue(destination.blobs.blobExists("asset.png"))
        XCTAssertTrue(destination.blobs.thumbExists("asset-thumb.png"))
        let isIgnored = try await destination.ignores.contains(
            bundleIdentifier: "com.example.private"
        )
        XCTAssertTrue(isIgnored)

        let second = try await destination.service.importArchive(from: archive)
        XCTAssertEqual(second.history, HistoryMergeResult(insertedCount: 0, duplicateCount: 1))
        let countAfterSecondImport = try await destination.history.count()
        XCTAssertEqual(countAfterSecondImport, 1)
    }

    func testExportRejectsEmptySelection() async throws {
        let fixture = try makeFixture(named: "empty")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let archive = fixture.root.appendingPathComponent("empty.clipstrate")

        do {
            try await fixture.service.exportArchive(
                to: archive,
                selection: BackupSelection(settings: false, ignoreList: false, history: false)
            )
            XCTFail("Expected empty selection to fail")
        } catch let error as BackupError {
            XCTAssertEqual(error, .emptySelection)
        }
    }

    func testImportRejectsAssetPathOutsideStore() async throws {
        let source = try makeFixture(named: "unsafe-source")
        let destination = try makeFixture(named: "unsafe-destination")
        defer {
            try? FileManager.default.removeItem(at: source.root)
            try? FileManager.default.removeItem(at: destination.root)
        }

        try await source.history.upsert(
            ClipItem(
                kind: .image,
                blobPath: "../outside.png",
                contentHash: "unsafe-path",
                byteSize: 1
            )
        )
        let archive = source.root.appendingPathComponent("unsafe.clipstrate")
        try await source.service.exportArchive(
            to: archive,
            selection: BackupSelection(settings: false, ignoreList: false, history: true)
        )

        do {
            try await destination.service.importArchive(from: archive)
            XCTFail("Expected unsafe asset path to fail")
        } catch let error as BackupError {
            XCTAssertEqual(error, .invalidArchive)
        }
        let count = try await destination.history.count()
        XCTAssertEqual(count, 0)
    }
}
