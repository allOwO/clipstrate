import AppKit

/// 集中的 NSPasteboard 类型常量。采集（Capture）与写回（System/PasteService）
/// 都要用，放 Shared 避免两个同级模块互相依赖。
extension NSPasteboard.PasteboardType {
    /// 密码管理器等标记「隐藏」内容（nspasteboard.org 约定），命中即跳过。
    static let nsConcealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    /// 「瞬时」内容，不应入历史。
    static let nsTransient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    /// 来源 App 的 bundle id（最可信的来源信息）。
    static let nsSource = NSPasteboard.PasteboardType("org.nspasteboard.source")
    /// 本 App 粘贴时自写入的标记；再被采集到即跳过，避免自我回环。
    static let clipstrateSelfWrite = NSPasteboard.PasteboardType("io.github.allowo.clipstrate.self")
}
