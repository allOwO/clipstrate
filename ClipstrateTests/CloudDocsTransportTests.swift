import XCTest
@testable import Clipstrate

final class CloudDocsTransportTests: XCTestCase {
    func testUnavailableCloudDocsDoesNotCreateRoot() throws {
        let root = temporaryRoot("unavailable")
        let transport = CloudDocsTransport(cloudDocsRoot: root)

        XCTAssertFalse(transport.isAvailable)
        XCTAssertThrowsError(try transport.prepareDirectory()) { error in
            XCTAssertEqual(error as? BackupError, .cloudDriveUnavailable)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testListsRegularAndPlaceholderBackupsNewestFirst() throws {
        let root = temporaryRoot("listing")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transport = CloudDocsTransport(cloudDocsRoot: root)
        try transport.prepareDirectory()

        let older = transport.directoryURL.appendingPathComponent("older.clipstrate")
        let newer = transport.directoryURL.appendingPathComponent(".newer.clipstrate.icloud")
        XCTAssertTrue(FileManager.default.createFile(atPath: older.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: newer.path, contents: Data()))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: older.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newer.path
        )

        let files = try transport.backups()
        XCTAssertEqual(files.map(\.displayName), ["newer.clipstrate", "older.clipstrate"])
        XCTAssertTrue(files[0].isPlaceholder)
        XCTAssertFalse(files[1].isPlaceholder)
    }

    func testRetentionKeepsRecentThreeAndWeeklyBackupsUpToEight() throws {
        let root = temporaryRoot("retention")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transport = CloudDocsTransport(cloudDocsRoot: root)
        try transport.prepareDirectory()

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<12 {
            let url = transport.directoryURL.appendingPathComponent("\(index).clipstrate")
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
            let date = calendar.date(byAdding: .day, value: -(index * 8), to: base)!
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: url.path
            )
        }

        try transport.pruneBackups(calendar: calendar)

        let remaining = try transport.backups()
        XCTAssertEqual(remaining.count, 8)
        XCTAssertEqual(Set(remaining.prefix(3).map(\.displayName)), Set(["0.clipstrate", "1.clipstrate", "2.clipstrate"]))
    }

    func testCloudFilenameSanitizesDeviceName() {
        let name = BackupNaming.cloudFilename(
            now: Date(timeIntervalSince1970: 0),
            deviceName: "Liu / Mac"
        )
        XCTAssertTrue(name.hasPrefix("Clipstrate-Liu-Mac-"))
        XCTAssertTrue(name.hasSuffix(".clipstrate"))
        XCTAssertFalse(name.contains(" / "))
    }

    private func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ClipstrateCloudDocsTests-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
    }
}
