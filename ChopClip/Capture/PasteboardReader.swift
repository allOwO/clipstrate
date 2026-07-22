import AppKit

/// 来源 App（值类型，可跨 actor 传）。两级获取见 01 §1.4。
struct SourceApp: Sendable, Equatable {
    var bundleID: String?
    var name: String?

    init(bundleID: String? = nil, name: String? = nil) {
        self.bundleID = bundleID
        self.name = name
    }

    init(running app: NSRunningApplication?) {
        self.bundleID = app?.bundleIdentifier
        self.name = app?.localizedName
    }
}

/// 一次采集的产物：入库草稿 + 待落盘的 blob（富文本原数据 / 图片原图）。
struct CapturedClip: Sendable {
    var item: ClipItem
    var blobData: Data?
}

enum SkipReason: String, Sendable {
    case concealed, transient, selfWrite, empty, imageTooLarge
}

enum CaptureOutcome: Sendable {
    case captured(CapturedClip)
    case skipped(SkipReason)
    case nothing
}

/// 把 `NSPasteboard` 当拍内容解析成 `ClipItem` 草稿（01 §1）。纯函数式、可单测
/// （传入自建 NSPasteboard 即可，无需真实系统剪贴板）。
struct PasteboardReader: Sendable {
    /// 文本 plain 超此字节数则截断存储并标记 truncated（01 §1.1）。
    var maxTextBytes: Int = 2 * 1024 * 1024
    /// 图片原始数据超此字节数则丢弃（01 §1.1）。
    var maxImageBytes: Int = 50 * 1024 * 1024

    func read(from pb: NSPasteboard, frontmost: SourceApp, now: Int64) -> CaptureOutcome {
        let types = pb.types ?? []

        // 跳过规则（在读取内容之前判断）。
        if types.contains(.nsConcealed) { return .skipped(.concealed) }
        if types.contains(.nsTransient) { return .skipped(.transient) }
        if types.contains(.chopClipSelfWrite) { return .skipped(.selfWrite) }

        let source = resolveSource(pb, frontmost: frontmost)

        // 读取顺序：fileURL → image(png/tiff) → rich(rtf/html)+string → string。
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return .captured(makeFile(urls, source: source, now: now))
        }

        if let (data, ext) = imageData(pb) {
            if data.count > maxImageBytes { return .skipped(.imageTooLarge) }
            return .captured(makeImage(data, ext: ext, source: source, now: now))
        }

        if let string = pb.string(forType: .string) {
            if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .skipped(.empty)
            }
            return .captured(makeText(pb, plain: string, source: source, now: now))
        }

        return .nothing
    }

    // MARK: - 来源

    private func resolveSource(_ pb: NSPasteboard, frontmost: SourceApp) -> SourceApp {
        if let bundleID = pb.string(forType: .nsSource), !bundleID.isEmpty {
            let name = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .first?.localizedName
            return SourceApp(bundleID: bundleID, name: name)
        }
        return frontmost
    }

    // MARK: - 构造各类型草稿

    private func makeFile(_ urls: [URL], source: SourceApp, now: Int64) -> CapturedClip {
        let paths = urls.map(\.path)
        let label = urls.map(\.lastPathComponent).joined(separator: ", ")
        let item = ClipItem(
            kind: .file,
            label: label,
            fileURLs: paths,
            contentHash: ContentHash.file(paths),
            appBundleID: source.bundleID,
            appName: source.name,
            byteSize: 0,               // 只存路径，不占本 App 磁盘
            createdAt: now
        )
        return CapturedClip(item: item, blobData: nil)
    }

    private func imageData(_ pb: NSPasteboard) -> (Data, String)? {
        if let png = pb.data(forType: .png) { return (png, "png") }
        if let tiff = pb.data(forType: .tiff) { return (tiff, "tiff") }
        return nil
    }

    private func makeImage(_ data: Data, ext: String, source: SourceApp, now: Int64) -> CapturedClip {
        let hash = ContentHash.image(data)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date(timeIntervalSince1970: Double(now) / 1000))
        let item = ClipItem(
            kind: .image,
            label: "图片 \(dateString)",   // 可搜标签（T1.6 图片管线可细化为「截图 …」）
            blobPath: "\(hash).\(ext)",     // 扩展名保留格式，供粘贴时选类型
            contentHash: hash,
            appBundleID: source.bundleID,
            appName: source.name,
            byteSize: data.count,
            createdAt: now
        )
        return CapturedClip(item: item, blobData: data)
    }

    private func makeText(_ pb: NSPasteboard, plain rawPlain: String,
                          source: SourceApp, now: Int64) -> CapturedClip {
        let (plain, truncated) = truncatePlain(rawPlain)
        let hash = ContentHash.text(plain)

        // 富文本：双份存储（原数据落盘 + 纯文本副本入列，01 §1.2）。RTF 优先，其次 HTML。
        if let rtf = pb.data(forType: .rtf) {
            return richClip(plain: plain, truncated: truncated, hash: hash,
                            richData: rtf, richType: "rtf", source: source, now: now)
        }
        if let html = pb.data(forType: .html) {
            return richClip(plain: plain, truncated: truncated, hash: hash,
                            richData: html, richType: "html", source: source, now: now)
        }

        let item = ClipItem(
            kind: .text,
            isRich: false,
            plainText: plain,
            contentHash: hash,
            appBundleID: source.bundleID,
            appName: source.name,
            byteSize: plain.utf8.count,
            truncated: truncated,
            createdAt: now
        )
        return CapturedClip(item: item, blobData: nil)
    }

    private func richClip(plain: String, truncated: Bool, hash: String,
                          richData: Data, richType: String,
                          source: SourceApp, now: Int64) -> CapturedClip {
        let item = ClipItem(
            kind: .text,
            isRich: true,
            plainText: plain,
            richType: richType,
            blobPath: "\(hash).\(richType)",
            contentHash: hash,
            appBundleID: source.bundleID,
            appName: source.name,
            byteSize: richData.count,
            truncated: truncated,
            createdAt: now
        )
        return CapturedClip(item: item, blobData: richData)
    }

    private func truncatePlain(_ s: String) -> (String, Bool) {
        let data = Data(s.utf8)
        guard data.count > maxTextBytes else { return (s, false) }
        return (String(decoding: data.prefix(maxTextBytes), as: UTF8.self), true)
    }
}
