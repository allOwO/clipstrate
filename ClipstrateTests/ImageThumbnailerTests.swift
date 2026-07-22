import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Clipstrate

final class ImageThumbnailerTests: XCTestCase {
    func testDownsamplesWithoutExceedingMaxPixelAndPreservesOriginalMeta() throws {
        let original = try makePNG(width: 1_024, height: 512)
        let artifact = try XCTUnwrap(ImageThumbnailer.makeJPEG(from: original, maxPixel: 512))
        XCTAssertEqual(artifact.pixelWidth, 1_024)
        XCTAssertEqual(artifact.pixelHeight, 512)
        XCTAssertEqual(artifact.format, "PNG")

        let source = try XCTUnwrap(CGImageSourceCreateWithData(artifact.jpegData as CFData, nil))
        let thumb = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(max(thumb.width, thumb.height), 512)

        let name = artifact.fileName(contentHash: "abc", originalByteSize: original.count)
        let descriptor = try XCTUnwrap(ImageThumbnailDescriptor(fileName: name))
        XCTAssertEqual(descriptor.pixelWidth, 1_024)
        XCTAssertEqual(descriptor.pixelHeight, 512)
        XCTAssertEqual(descriptor.originalByteSize, original.count)
    }

    func testInvalidImageReturnsNil() {
        XCTAssertNil(ImageThumbnailer.makeJPEG(from: Data("not image".utf8)))
    }

    func testTransparentImageCompositedOverOpaqueBackground() throws {
        let transparent = try makeTransparentPNG(width: 128, height: 128)
        let artifact = try XCTUnwrap(ImageThumbnailer.makeJPEG(from: transparent, maxPixel: 128))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(artifact.jpegData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        let (r, g, b) = try averageRGB(image)
        // 全透明区域应合成为白底，而非 JPEG 默认的黑。
        XCTAssertGreaterThan(r, 200)
        XCTAssertGreaterThan(g, 200)
        XCTAssertGreaterThan(b, 200)
    }

    private func makeTransparentPNG(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.clear(CGRect(x: 0, y: 0, width: width, height: height)) // 全透明
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func averageRGB(_ image: CGImage) throws -> (Int, Int, Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1)) // 缩到 1×1 采样均值
        }
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
