import Foundation

/// 01 §10 的进程内剪贴板堆栈。捕获链仍照常入历史；A 侧在 `HistoryStore.upsert`
/// 成功后把已存条目 enqueue。关闭模式会立即清空，读取固定 FIFO。
actor ClipboardStack {
    struct State: Equatable, Sendable {
        var isEnabled: Bool
        var count: Int
    }

    private var enabled = false
    private var items: [ClipItem] = []
    private var head = 0

    func state() -> State {
        State(isEnabled: enabled, count: items.count - head)
    }

    @discardableResult
    func toggle() -> State {
        setEnabled(!enabled)
    }

    @discardableResult
    func setEnabled(_ newValue: Bool) -> State {
        enabled = newValue
        if !newValue {
            items.removeAll(keepingCapacity: false)
            head = 0
        }
        return state()
    }

    /// 模式关闭时忽略入栈；开启时每次复制都保留，包括内容重复的复制。
    @discardableResult
    func enqueue(_ item: ClipItem) -> Bool {
        guard enabled else { return false }
        items.append(item)
        return true
    }

    /// 固定 FIFO：最早入栈的条目最先弹出。
    func dequeue() -> ClipItem? {
        guard enabled, head < items.count else { return nil }
        let item = items[head]
        head += 1
        compactIfNeeded()
        return item
    }

    private func compactIfNeeded() {
        guard head >= 64, head * 2 >= items.count else { return }
        items.removeFirst(head)
        head = 0
    }
}
