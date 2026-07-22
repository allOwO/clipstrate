import XCTest
@testable import Clipstrate

@MainActor
final class BlobStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: BlobStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipstrateBlobTests-\(UUID().uuidString)")
        store = try BlobStore(blobsDir: tempDir.appendingPathComponent("blobs"),
                              thumbsDir: tempDir.appendingPathComponent("thumbs"))
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testWriteReadDeleteBlob() throws {
        let data = Data("payload".utf8)
        let name = try store.writeBlob(data, name: "hashA")
        XCTAssertEqual(name, "hashA")
        XCTAssertTrue(store.blobExists("hashA"))
        XCTAssertEqual(try store.readBlob("hashA"), data)

        store.deleteBlob("hashA")
        XCTAssertFalse(store.blobExists("hashA"))
    }

    func testDeleteMissingBlobIsNoop() {
        store.deleteBlob("does-not-exist")
        XCTAssertFalse(store.blobExists("does-not-exist"))
    }

    func testThumbRoundTrip() throws {
        let data = Data([0xFF, 0xD8, 0xFF, 0xE0])
        _ = try store.writeThumb(data, name: "t1")
        XCTAssertTrue(store.thumbExists("t1"))
        XCTAssertEqual(try store.readThumb("t1"), data)

        store.deleteThumb("t1")
        XCTAssertFalse(store.thumbExists("t1"))
    }
}
