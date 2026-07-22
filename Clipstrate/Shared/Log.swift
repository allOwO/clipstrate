import os

/// 日志与 signpost 统一门面。subsystem 固定 `io.github.allowo.clipstrate`，
/// 分模块 category（02 §9）。业务代码用 `Log.<模块>.info(...)`。
///
/// Release 下 debug 级由系统按 category 配置过滤；关键路径的 signpost
/// 全量打点在 T3.1 接线，此处先暴露 `signposter` 句柄供 T1.2 起使用。
enum Log {
    static let subsystem = "io.github.allowo.clipstrate"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let panel = Logger(subsystem: subsystem, category: "panel")
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")
    static let system = Logger(subsystem: subsystem, category: "system")
    static let chop = Logger(subsystem: subsystem, category: "chop")

    /// signpost 点位（02 §9）：summon.show / search.keystroke / chop.tokenize
    /// / capture.tick / db.page。用 "PointsOfInterest" category 以进
    /// Instruments 的 Points of Interest 仪表。
    static let signposter = OSSignposter(subsystem: subsystem, category: "PointsOfInterest")
}
