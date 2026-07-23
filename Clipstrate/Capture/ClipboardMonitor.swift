import AppKit

/// 剪贴板轮询采集（01 §1.1、02 §7）。actor 串行化每次 tick；`DispatchSourceTimer`
/// 每 300ms（leeway 100ms）比对 `changeCount`，仅变化时读内容。读→解析在 tick 内完成，
/// 落盘/入库为 async。任何一次采集出错都吞掉记录、绝不中断轮询（02 §10）。
actor ClipboardMonitor {
    private let store: HistoryStore
    private let blobs: BlobStore
    private let reader: PasteboardReader
    private let queue = DispatchQueue(
        label: "io.github.allowo.clipstrate.capture",
        qos: .utility
    )
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    /// 入库后回调（App 层据此做实体检测 + EntityHUD）。Capture 不依赖 Chop（模块方向）。
    private let onCapture: (@Sendable (ClipItem) -> Void)?
    /// 忽略名单判定（注入，避免 Capture→Chop 依赖）：返回 true 则该来源 App 不入库（01 §7.3）。
    private let isIgnored: (@Sendable (String?) async -> Bool)?

    init(
        store: HistoryStore,
        blobs: BlobStore,
        reader: PasteboardReader = PasteboardReader(),
        onCapture: (@Sendable (ClipItem) -> Void)? = nil,
        isIgnored: (@Sendable (String?) async -> Bool)? = nil
    ) {
        self.store = store
        self.blobs = blobs
        self.reader = reader
        self.onCapture = onCapture
        self.isIgnored = isIgnored
        // 启动时不采集既有剪贴板内容，只从下一次变化开始（隐私友好）。
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    deinit {
        timer?.cancel()
    }

    func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + .milliseconds(300),
                        repeating: .milliseconds(300),
                        leeway: .milliseconds(100))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.tick() }
        }
        timer = source
        source.resume()
        Log.capture.info("ClipboardMonitor started")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        Log.capture.info("ClipboardMonitor stopped")
    }

    private func tick() async {
        // changeCount 比对很廉价，不打 signpost；仅在真有变化时计量读取+入库这一拍。
        let changeCount = NSPasteboard.general.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let interval = Log.signposter.beginInterval("capture.tick")
        defer { Log.signposter.endInterval("capture.tick", interval) }

        let outcome: CaptureOutcome = autoreleasepool {
            let pb = NSPasteboard.general
            let frontmost = SourceApp(running: NSWorkspace.shared.frontmostApplication)
            return reader.read(from: pb, frontmost: frontmost, now: HistoryStore.nowMillis())
        }

        switch outcome {
        case .captured(let clip):
            await persist(clip)
        case .skipped(let reason):
            Log.capture.debug("capture skipped: \(reason.rawValue, privacy: .public)")
        case .nothing:
            break
        }
    }

    private func persist(_ clip: CapturedClip) async {
        // 忽略名单：前台来源 App 在名单内则整条跳过（01 §7.3）。
        if let isIgnored, await isIgnored(clip.item.appBundleID) {
            Log.capture.debug("capture skipped: ignored source app")
            return
        }
        do {
            var item = clip.item
            if let data = clip.blobData, let name = clip.item.blobPath {
                try blobs.writeBlob(data, name: name)
            }
            if item.kind == .image, let data = clip.blobData {
                let artifact = await Task.detached(priority: .utility) {
                    ImageThumbnailer.makeJPEG(from: data)
                }.value
                if let artifact {
                    let name = artifact.fileName(
                        contentHash: item.contentHash,
                        originalByteSize: item.byteSize
                    )
                    do {
                        item.thumbPath = try blobs.writeThumb(artifact.jpegData, name: name)
                    } catch {
                        Log.capture.error("thumbnail persist failed: \(String(describing: error), privacy: .public)")
                    }
                }
            }
            let saved = try await store.upsert(item)
            Log.capture.debug("captured id=\(saved.id ?? -1, privacy: .public) kind=\(saved.kind.rawValue, privacy: .public)")
            onCapture?(saved)
        } catch {
            Log.capture.error("persist failed: \(String(describing: error), privacy: .public)")
        }
    }
}
