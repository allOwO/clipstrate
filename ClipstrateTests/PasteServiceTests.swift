import AppKit
import XCTest
@testable import Clipstrate

@MainActor
final class PasteServiceTests: XCTestCase {
    private struct Context {
        let tempDir: URL
        let blobs: BlobStore
        let pasteboard: NSPasteboard
    }

    private func makeContext() throws -> Context {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteServiceTests-\(UUID().uuidString)")
        let blobs = try BlobStore(
            blobsDir: tempDir.appendingPathComponent("blobs"),
            thumbsDir: tempDir.appendingPathComponent("thumbs")
        )
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        return Context(tempDir: tempDir, blobs: blobs, pasteboard: pasteboard)
    }

    private func cleanUp(_ context: Context) {
        context.pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: context.tempDir)
    }

    func testPlainTextWriteIncludesSelfMarkerAndCanCopyOnly() async {
        let context = try! makeContext()
        defer { cleanUp(context) }
        var posted = false
        let service = PasteService(
            pasteboard: context.pasteboard,
            blobStore: context.blobs,
            isAXTrusted: { true },
            postPasteKeystroke: { posted = true }
        )
        let item = ClipItem(kind: .text, plainText: "hello", contentHash: "text")

        let result = await service.perform(item: item, plainText: false, action: .copy)

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(context.pasteboard.string(forType: .string), "hello")
        XCTAssertTrue(context.pasteboard.types?.contains(.clipstrateSelfWrite) == true)
        XCTAssertFalse(posted)
    }

    func testRichTextWritesRichAndPlainRepresentations() async throws {
        let context = try makeContext()
        defer { cleanUp(context) }
        let rtf = Data("{\\rtf1 hello}".utf8)
        try context.blobs.writeBlob(rtf, name: "rich.rtf")
        let item = ClipItem(
            kind: .text,
            isRich: true,
            plainText: "hello",
            richType: "rtf",
            blobPath: "rich.rtf",
            contentHash: "rich"
        )
        let service = PasteService(pasteboard: context.pasteboard, blobStore: context.blobs)

        let richResult = await service.perform(item: item, plainText: false, action: .copy)
        XCTAssertEqual(richResult, .copied)
        XCTAssertEqual(context.pasteboard.data(forType: .rtf), rtf)
        XCTAssertEqual(context.pasteboard.string(forType: .string), "hello")

        let plainResult = await service.perform(item: item, plainText: true, action: .copy)
        XCTAssertEqual(plainResult, .copied)
        XCTAssertNil(context.pasteboard.data(forType: .rtf))
        XCTAssertEqual(context.pasteboard.string(forType: .string), "hello")
    }

    func testImageAndFileRepresentations() async throws {
        let context = try makeContext()
        defer { cleanUp(context) }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        try context.blobs.writeBlob(png, name: "image.png")
        let image = ClipItem(kind: .image, blobPath: "image.png", contentHash: "image")
        let service = PasteService(pasteboard: context.pasteboard, blobStore: context.blobs)

        let imageResult = await service.perform(item: image, plainText: false, action: .copy)
        XCTAssertEqual(imageResult, .copied)
        XCTAssertEqual(context.pasteboard.data(forType: .png), png)
        XCTAssertTrue(context.pasteboard.types?.contains(.clipstrateSelfWrite) == true)

        let file = ClipItem(kind: .file, fileURLs: ["/tmp/report.txt"], contentHash: "file")
        let fileResult = await service.perform(item: file, plainText: false, action: .copy)
        XCTAssertEqual(fileResult, .copied)
        let urls = context.pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        XCTAssertEqual(urls?.map(\.path), ["/tmp/report.txt"])
        XCTAssertTrue(context.pasteboard.types?.contains(.clipstrateSelfWrite) == true)
    }

    func testPasteAndAccessibilityFallback() async {
        let context = try! makeContext()
        defer { cleanUp(context) }
        var postedCount = 0
        let item = ClipItem(kind: .text, plainText: "hello", contentHash: "text")
        let trusted = PasteService(
            pasteboard: context.pasteboard,
            blobStore: context.blobs,
            isAXTrusted: { true },
            postPasteKeystroke: { postedCount += 1 }
        )
        let trustedResult = await trusted.perform(item: item, plainText: false, action: .paste)
        XCTAssertEqual(trustedResult, .pasted)
        XCTAssertEqual(postedCount, 1)

        let untrusted = PasteService(
            pasteboard: context.pasteboard,
            blobStore: context.blobs,
            isAXTrusted: { false },
            postPasteKeystroke: { postedCount += 1 }
        )
        let untrustedResult = await untrusted.perform(item: item, plainText: false, action: .paste)
        XCTAssertEqual(untrustedResult, .copiedNeedsManualPaste)
        XCTAssertEqual(postedCount, 1)
    }

    func testUnavailableImageDoesNotPostPaste() async {
        let context = try! makeContext()
        defer { cleanUp(context) }
        var posted = false
        let service = PasteService(
            pasteboard: context.pasteboard,
            blobStore: context.blobs,
            isAXTrusted: { true },
            postPasteKeystroke: { posted = true }
        )
        let item = ClipItem(kind: .image, blobPath: "missing.png", contentHash: "missing")
        let result = await service.perform(item: item, plainText: false, action: .paste)
        XCTAssertEqual(result, .unavailable)
        XCTAssertFalse(posted)
    }
}
