import AppKit
import XCTest
@testable import Clipstrate

@MainActor
final class CardAssetLoaderTests: XCTestCase {
    private var tempDir: URL!
    private var blobs: BlobStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipstrateRich-\(UUID().uuidString)")
        blobs = try BlobStore(blobsDir: tempDir.appendingPathComponent("blobs"),
                              thumbsDir: tempDir.appendingPathComponent("thumbs"))
    }

    override func tearDownWithError() throws {
        blobs = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeRTF(_ string: String) throws -> Data {
        let attributed = NSAttributedString(string: string)
        return try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    func testParsesRichRTF() async throws {
        let name = "\(UUID().uuidString).rtf"
        let data = try makeRTF("富文本内容 hello")
        _ = try blobs.writeBlob(data, name: name)
        let item = ClipItem(kind: .text, isRich: true, plainText: "富文本内容 hello",
                            richType: "rtf", blobPath: name, contentHash: "r1", byteSize: data.count)

        let result = await CardAssetLoader.shared.richText(for: item, store: blobs)
        let attributed = try XCTUnwrap(result)
        XCTAssertTrue(String(attributed.characters).contains("富文本内容"))
    }

    func testRejectsOverLimitRichText() async {
        // byteSize 超 2MB → 直接降级为不渲染，不去读 blob。
        let item = ClipItem(kind: .text, isRich: true, plainText: "x",
                            richType: "rtf", blobPath: "\(UUID().uuidString).rtf",
                            contentHash: "r2", byteSize: 3 * 1024 * 1024)
        let result = await CardAssetLoader.shared.richText(for: item, store: blobs)
        XCTAssertNil(result, "超 2MB 富文本应降级为不渲染")
    }

    func testNilForNonRichText() async {
        let item = ClipItem(kind: .text, isRich: false, plainText: "plain", contentHash: "r3")
        let result = await CardAssetLoader.shared.richText(for: item, store: blobs)
        XCTAssertNil(result, "纯文本不走富文本渲染")
    }
}
