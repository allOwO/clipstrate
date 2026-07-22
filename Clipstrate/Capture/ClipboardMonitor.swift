import AppKit

/// 剪贴板轮询采集（01 §1.1、02 §7）。actor 串行化每次 tick；`DispatchSourceTimer`
/// 每 300ms（leeway 100ms）比对 `changeCount`，仅变化时读内容。读→解析在 tick 内完成，
/// 落盘/入库为 async。任何一次采集出错都吞掉记录、绝不中断轮询（02 §10）。
actor ClipboardMonitor {
    private let store: HistoryStore
    private let blobs: BlobStore
    private let reader: PasteboardReader
    private let queue = DispatchQueue(label: "io.github.allowo.clipstrate.capture", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int

    init(store: HistoryStore, blobs: BlobStore, reader: PasteboardReader = PasteboardReader()) {
        self.store = store
        self.blobs = blobs
        self.reader = reader
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
        let outcome: CaptureOutcome? = autoreleasepool {
            let pb = NSPasteboard.general
            let changeCount = pb.changeCount
            guard changeCount != lastChangeCount else { return nil }
            lastChangeCount = changeCount
            let frontmost = SourceApp(running: NSWorkspace.shared.frontmostApplication)
            return reader.read(from: pb, frontmost: frontmost, now: HistoryStore.nowMillis())
        }
        guard let outcome else { return }

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
        do {
            if let data = clip.blobData, let name = clip.item.blobPath {
                try blobs.writeBlob(data, name: name)
            }
            let saved = try await store.upsert(clip.item)
            Log.capture.debug("captured id=\(saved.id ?? -1, privacy: .public) kind=\(saved.kind.rawValue, privacy: .public)")
        } catch {
            Log.capture.error("persist failed: \(String(describing: error), privacy: .public)")
        }
    }
}
