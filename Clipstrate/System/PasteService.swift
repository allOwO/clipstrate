import AppKit
import CoreGraphics

enum PasteResult: Equatable, Sendable {
    case pasted
    case copied
    case copiedNeedsManualPaste
    case unavailable

    var didWritePasteboard: Bool { self != .unavailable }
}

/// 把历史条目写回剪贴板，并按需向原前台 App 合成 ⌘V（01 §3.5）。
/// blob 读取在 detached task；NSPasteboard 与 CGEvent 只在主 actor 操作。
@MainActor
final class PasteService {
    typealias TrustCheck = @MainActor () -> Bool
    typealias PasteKeystroke = @MainActor () -> Void

    private let pasteboard: NSPasteboard
    private let blobStore: BlobStore?
    private let isAXTrusted: TrustCheck
    private let postPasteKeystroke: PasteKeystroke

    init(
        pasteboard: NSPasteboard = .general,
        blobStore: BlobStore?,
        isAXTrusted: @escaping TrustCheck = { AXPermission.isTrusted },
        postPasteKeystroke: @escaping PasteKeystroke = { PasteService.postCommandV() }
    ) {
        self.pasteboard = pasteboard
        self.blobStore = blobStore
        self.isAXTrusted = isAXTrusted
        self.postPasteKeystroke = postPasteKeystroke
    }

    func perform(item: ClipItem, plainText: Bool, action: ClickAction) async -> PasteResult {
        let wrote = await write(item: item, plainText: plainText)
        guard wrote else {
            Log.system.error("剪贴板条目不可用：kind=\(item.kind.rawValue, privacy: .public)")
            return .unavailable
        }

        guard action == .paste else { return .copied }
        guard isAXTrusted() else {
            Log.system.info("辅助功能未授权：已复制，跳过自动 ⌘V")
            return .copiedNeedsManualPaste
        }
        postPasteKeystroke()
        return .pasted
    }

    private func write(item: ClipItem, plainText: Bool) async -> Bool {
        switch item.kind {
        case .text:
            return await writeText(item, plainText: plainText)
        case .image:
            return await writeImage(item)
        case .file:
            return writeFiles(item)
        }
    }

    private func writeText(_ item: ClipItem, plainText: Bool) async -> Bool {
        guard let plain = item.plainText else { return false }
        var rich: (NSPasteboard.PasteboardType, Data)?
        if !plainText, item.isRich,
           let blobPath = item.blobPath,
           let type = Self.richPasteboardType(item.richType) {
            do {
                rich = (type, try await readBlob(blobPath))
            } catch {
                // 富文本 blob 丢失时仍保留纯文本降级，不让历史条目彻底失效。
                Log.system.error("读取富文本 blob 失败，降级纯文本：\(String(describing: error), privacy: .public)")
            }
        }

        var types: [NSPasteboard.PasteboardType] = [.string, .clipstrateSelfWrite]
        if let rich { types.insert(rich.0, at: 0) }
        pasteboard.declareTypes(types, owner: nil)
        guard pasteboard.setString(plain, forType: .string) else { return false }
        if let rich, !pasteboard.setData(rich.1, forType: rich.0) { return false }
        return pasteboard.setData(Data(), forType: .clipstrateSelfWrite)
    }

    private func writeImage(_ item: ClipItem) async -> Bool {
        guard let blobPath = item.blobPath,
              let type = Self.imagePasteboardType(path: blobPath),
              let data = try? await readBlob(blobPath) else { return false }
        pasteboard.declareTypes([type, .clipstrateSelfWrite], owner: nil)
        guard pasteboard.setData(data, forType: type) else { return false }
        return pasteboard.setData(Data(), forType: .clipstrateSelfWrite)
    }

    private func writeFiles(_ item: ClipItem) -> Bool {
        let urls = item.fileURLs?.map { URL(fileURLWithPath: $0) } ?? []
        guard !urls.isEmpty else { return false }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(urls as [NSURL]) else { return false }
        return pasteboard.setData(Data(), forType: .clipstrateSelfWrite)
    }

    private func readBlob(_ name: String) async throws -> Data {
        guard let blobStore else { throw CocoaError(.fileNoSuchFile) }
        return try await Task.detached(priority: .userInitiated) {
            try blobStore.readBlob(name)
        }.value
    }

    private static func richPasteboardType(_ richType: String?) -> NSPasteboard.PasteboardType? {
        switch richType {
        case "rtf": return .rtf
        case "html": return .html
        default: return nil
        }
    }

    private static func imagePasteboardType(path: String) -> NSPasteboard.PasteboardType? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png": return .png
        case "tif", "tiff": return .tiff
        default: return nil
        }
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            Log.system.error("无法创建 ⌘V CGEvent")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
