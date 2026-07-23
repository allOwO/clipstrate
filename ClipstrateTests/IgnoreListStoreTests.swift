import XCTest
@testable import Clipstrate

final class IgnoreListStoreTests: XCTestCase {
    func testAddPersistsAndMatchesBundleIdentifierCaseInsensitively() async throws {
        let fixture = try Fixture()
        let store = IgnoreListStore(fileURL: fixture.fileURL)
        let app = try XCTUnwrap(IgnoredApplication(
            bundleIdentifier: "Com.Example.Writer",
            displayName: "Writer"
        ))

        let added = try await store.add(app)
        let matchesCanonical = try await store.contains(bundleIdentifier: "com.example.writer")
        let matchesAfterReload = try await IgnoreListStore(fileURL: fixture.fileURL)
            .contains(bundleIdentifier: "COM.EXAMPLE.WRITER")
        XCTAssertTrue(added)
        XCTAssertTrue(matchesCanonical)
        XCTAssertTrue(matchesAfterReload)
    }

    func testDuplicateAddDoesNotCreateSecondRowAndCanRefreshName() async throws {
        let fixture = try Fixture()
        let store = IgnoreListStore(fileURL: fixture.fileURL)
        let first = try XCTUnwrap(IgnoredApplication(
            bundleIdentifier: "com.example.app",
            displayName: "Old Name"
        ))
        let renamed = try XCTUnwrap(IgnoredApplication(
            bundleIdentifier: "com.example.app",
            displayName: "New Name"
        ))

        let firstAdd = try await store.add(first)
        let duplicateAdd = try await store.add(first)
        let rename = try await store.add(renamed)
        let applications = try await store.applications()
        XCTAssertTrue(firstAdd)
        XCTAssertFalse(duplicateAdd)
        XCTAssertTrue(rename)
        XCTAssertEqual(applications, [renamed])
    }

    func testRemoveIsIdempotentAndPersists() async throws {
        let fixture = try Fixture()
        let store = IgnoreListStore(fileURL: fixture.fileURL)
        let app = try XCTUnwrap(IgnoredApplication(
            bundleIdentifier: "com.example.app",
            displayName: "Example"
        ))
        _ = try await store.add(app)

        let removed = try await store.remove(bundleIdentifier: "COM.EXAMPLE.APP")
        let removedAgain = try await store.remove(bundleIdentifier: "com.example.app")
        let persisted = try await IgnoreListStore(fileURL: fixture.fileURL)
            .contains(bundleIdentifier: app.bundleIdentifier)
        XCTAssertTrue(removed)
        XCTAssertFalse(removedAgain)
        XCTAssertFalse(persisted)
    }

    func testMissingOrEmptyBundleIdentifierIsNeverIgnored() async throws {
        let fixture = try Fixture()
        let store = IgnoreListStore(fileURL: fixture.fileURL)

        let nilIdentifier = try await store.contains(bundleIdentifier: nil)
        let emptyIdentifier = try await store.contains(bundleIdentifier: "  ")
        XCTAssertFalse(nilIdentifier)
        XCTAssertFalse(emptyIdentifier)
        XCTAssertNil(IgnoredApplication(bundleIdentifier: "", displayName: "No ID"))
    }
}

private final class Fixture {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("ignore-list.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipstrateIgnoreList-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
