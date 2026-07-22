import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageThumbnailArtifact: Sendable, Equatable {
    let jpegData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let format: String

    func fileName(contentHash: String, originalByteSize: Int) -> String {
        "\(contentHash)_\(pixelWidth)x\(pixelHeight)_\(format)_\(originalByteSize).jpg"
    }
}

/// ImageIO 降采样管线（01 §2）：直接从原始数据生成 ≤512px JPEG，不先解码整张 NSImage。
enum ImageThumbnailer {
    static func makeJPEG(
        from data: Data,
        maxPixel: Int = 512,
        quality: Double = 0.82
    ) -> ImageThumbnailArtifact? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        // JPEG 无 alpha 通道：透明 PNG/TIFF 直接编码会把透明区域压成黑色。
        // 先把带透明的缩略图合成到不透明白底，再编码。
        let opaqueImage = flattenedOverOpaqueBackground(thumbnail)

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            opaqueImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }

        let typeIdentifier = CGImageSourceGetType(source) as String?
        let rawFormat = typeIdentifier
            .flatMap { UTType($0)?.preferredFilenameExtension }
            .map { $0.uppercased() }
            ?? "IMAGE"
        let format = rawFormat.filter { $0.isLetter || $0.isNumber }
        return ImageThumbnailArtifact(
            jpegData: output as Data,
            pixelWidth: width,
            pixelHeight: height,
            format: format.isEmpty ? "IMAGE" : format
        )
    }

    /// 带透明通道的图合成到不透明白底；无 alpha 时原样返回。
    private static func flattenedOverOpaqueBackground(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return image
        default:
            break
        }
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }
}

struct ImageThumbnailDescriptor: Equatable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
    let format: String
    let originalByteSize: Int

    init?(fileName: String) {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: "_").map(String.init)
        guard parts.count >= 4,
              let dimensionPart = parts.dropLast(2).last,
              let separator = dimensionPart.firstIndex(of: "x"),
              let width = Int(dimensionPart[..<separator]),
              let height = Int(dimensionPart[dimensionPart.index(after: separator)...]),
              let byteSize = Int(parts.last ?? ""),
              width > 0, height > 0, byteSize >= 0,
              width <= 100_000, height <= 100_000 else { return nil }
        pixelWidth = width
        pixelHeight = height
        format = parts[parts.count - 2]
        originalByteSize = byteSize
    }
}
