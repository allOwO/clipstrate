import XCTest
@testable import ChopClip

final class ContentHashTests: XCTestCase {
    func testDeterministicAndDistinct() {
        XCTAssertEqual(ContentHash.text("abc"), ContentHash.text("abc"))
        XCTAssertNotEqual(ContentHash.text("abc"), ContentHash.text("abd"))
        // SHA-256 十六进制 = 64 字符
        XCTAssertEqual(ContentHash.text("abc").count, 64)
    }

    func testKindPrefixSeparatesSameBytes() {
        let bytes = "same"
        XCTAssertNotEqual(ContentHash.text(bytes), ContentHash.image(Data(bytes.utf8)))
    }

    func testFileHashIsOrderIndependent() {
        XCTAssertEqual(ContentHash.file(["/b", "/a"]), ContentHash.file(["/a", "/b"]))
    }
}
