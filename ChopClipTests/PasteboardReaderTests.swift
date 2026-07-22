import XCTest
import AppKit
@testable import ChopClip

@MainActor
final class PasteboardReaderTests: XCTestCase {
    private var pb: NSPasteboard!
    private let reader = PasteboardReader()

    override func setUp() {
        super.setUp()
        pb = NSPasteboard.withUniqueName()
        pb.clearContents()
    }

    override func tearDown() {
        pb.releaseGlobally()
        pb = nil
        super.tearDown()
    }

    private func capture(now: Int64 = 1_000, frontmost: SourceApp = SourceApp()) -> CapturedClip? {
        if case let .captured(clip) = reader.read(from: pb, frontmost: frontmost, now: now) {
            return clip
        }
        return nil
    }

    private func skip() -> SkipReason? {
        if case let .skipped(reason) = reader.read(from: pb, frontmost: SourceApp(), now: 1) {
            return reason
        }
        return nil
    }

    // MARK: - 类型解析

    func testPlainText() throws {
        pb.setString("hello 世界", forType: .string)
        let clip = try XCTUnwrap(capture())
        XCTAssertEqual(clip.item.kind, .text)
        XCTAssertFalse(clip.item.isRich)
        XCTAssertEqual(clip.item.plainText, "hello 世界")
        XCTAssertEqual(clip.item.contentHash, ContentHash.text("hello 世界"))
        XCTAssertEqual(clip.item.byteSize, "hello 世界".utf8.count)
        XCTAssertNil(clip.blobData)
    }

    func testRichRTF() throws {
        let rtf = Data("{\\rtf1 hi}".utf8)
        pb.setString("hi", forType: .string)
        pb.setData(rtf, forType: .rtf)
        let clip = try XCTUnwrap(capture())
        XCTAssertEqual(clip.item.kind, .text)
        XCTAssertTrue(clip.item.isRich)
        XCTAssertEqual(clip.item.richType, "rtf")
        XCTAssertEqual(clip.item.blobPath, "\(ContentHash.text("hi")).rtf")
        XCTAssertEqual(clip.blobData, rtf)
        XCTAssertEqual(clip.item.byteSize, rtf.count)
    }

    func testRichHTMLWhenNoRTF() throws {
        let html = Data("<b>hi</b>".utf8)
        pb.setString("hi", forType: .string)
        pb.setData(html, forType: .html)
        let clip = try XCTUnwrap(capture())
        XCTAssertTrue(clip.item.isRich)
        XCTAssertEqual(clip.item.richType, "html")
        XCTAssertEqual(clip.blobData, html)
    }

    func testImagePNG() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        pb.setData(png, forType: .png)
        let clip = try XCTUnwrap(capture())
        XCTAssertEqual(clip.item.kind, .image)
        XCTAssertEqual(clip.item.blobPath, "\(ContentHash.image(png)).png")
        XCTAssertEqual(clip.item.byteSize, png.count)
        XCTAssertEqual(clip.blobData, png)
        XCTAssertNotNil(clip.item.label)
    }

    func testImageTIFFWhenNoPNG() throws {
        let tiff = Data([0x4D, 0x4D, 0x00, 0x2A])
        pb.setData(tiff, forType: .tiff)
        let clip = try XCTUnwrap(capture())
        XCTAssertEqual(clip.item.kind, .image)
        XCTAssertEqual(clip.item.blobPath, "\(ContentHash.image(tiff)).tiff")
    }

    func testFileURLs() throws {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.pdf")]
        pb.writeObjects(urls.map { $0 as NSURL })
        let clip = try XCTUnwrap(capture())
        XCTAssertEqual(clip.item.kind, .file)
        XCTAssertEqual(clip.item.fileURLs, ["/tmp/a.txt", "/tmp/b.pdf"])
        XCTAssertEqual(clip.item.label, "a.txt, b.pdf")
        XCTAssertEqual(clip.item.contentHash, ContentHash.file(["/tmp/a.txt", "/tmp/b.pdf"]))
    }

    // MARK: - 跳过规则

    func testConcealedSkipped() {
        // 模拟 1Password 等密码管理器
        pb.declareTypes([.string, .nsConcealed], owner: nil)
        pb.setString("s3cr3t", forType: .string)
        XCTAssertEqual(skip(), .concealed)
    }

    func testTransientSkipped() {
        pb.declareTypes([.string, .nsTransient], owner: nil)
        pb.setString("temp", forType: .string)
        XCTAssertEqual(skip(), .transient)
    }

    func testSelfWriteSkipped() {
        pb.declareTypes([.string, .chopClipSelfWrite], owner: nil)
        pb.setString("我们自己粘贴的", forType: .string)
        XCTAssertEqual(skip(), .selfWrite)
    }

    func testEmptyWhitespaceSkipped() {
        pb.setString("   \n\t ", forType: .string)
        XCTAssertEqual(skip(), .empty)
    }

    func testImageTooLargeSkipped() {
        let reader = PasteboardReader(maxTextBytes: 2 * 1024 * 1024, maxImageBytes: 8)
        pb.setData(Data(count: 16), forType: .png)
        if case let .skipped(reason) = reader.read(from: pb, frontmost: SourceApp(), now: 1) {
            XCTAssertEqual(reason, .imageTooLarge)
        } else {
            XCTFail("超限图片应被跳过")
        }
    }

    func testNothingWhenNoUsableType() {
        // clearContents 后未写任何内容
        if case .nothing = reader.read(from: pb, frontmost: SourceApp(), now: 1) {} else {
            XCTFail("空剪贴板应为 .nothing")
        }
    }

    // MARK: - 截断

    func testLongTextTruncatedAndMarked() throws {
        let reader = PasteboardReader(maxTextBytes: 10, maxImageBytes: 1024)
        pb.setString(String(repeating: "x", count: 100), forType: .string)
        if case let .captured(clip) = reader.read(from: pb, frontmost: SourceApp(), now: 1) {
            XCTAssertTrue(clip.item.truncated)
            XCTAssertEqual(clip.item.plainText?.utf8.count, 10)
        } else {
            XCTFail("应捕获截断文本")
        }
    }

    // MARK: - 来源 App（两级）

    func testSourceFromPasteboardSourceType() throws {
        pb.declareTypes([.string, .nsSource], owner: nil)
        pb.setString("body", forType: .string)
        pb.setString("com.acme.editor", forType: .nsSource)
        let clip = try XCTUnwrap(capture())
        XCTAssertEqual(clip.item.appBundleID, "com.acme.editor")
    }

    func testSourceFallsBackToFrontmost() throws {
        pb.setString("body", forType: .string)
        let clip = try XCTUnwrap(capture(frontmost: SourceApp(bundleID: "com.a", name: "AppA")))
        XCTAssertEqual(clip.item.appBundleID, "com.a")
        XCTAssertEqual(clip.item.appName, "AppA")
    }

    func testSourceNilWhenBothMissing() throws {
        pb.setString("body", forType: .string)
        let clip = try XCTUnwrap(capture())
        XCTAssertNil(clip.item.appBundleID)
        XCTAssertNil(clip.item.appName)
    }
}
