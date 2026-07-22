# Clipstrate

macOS 26 原生剪贴板管理器：Liquid Glass 观感 + Maccy 级轻量 + 「大爆炸」分词拆选。Swift 6 + SwiftUI/AppKit，arm64，macOS 26+。

## 文档（开工前必读）

- `docs/specs/README.md` → `02-架构与选型` → 领任务看 `03-开发准备与任务拆分` → 实现前读 `01-功能规格` 对应章节。
- **specs 是唯一事实来源**；UI 以 `prototype/index.html`（浏览器直接打开）为像素参考。`prototype/` 是抛弃型原型，只读参考，勿引用其代码、勿发布。
- 设计决策历史：`prototype/NOTES.md`。已定决策不要重开讨论（见 03 §5）。

## 构建

```bash
xcodegen generate        # 改 project.yml 后重跑
xcodebuild -scheme Clipstrate build
xcodebuild -scheme Clipstrate test
```

调试权限（辅助功能/剪贴板）用 Xcode ⌘R 跑真 App；重签会重置 TCC 授权属正常。

## 硬约束（违反 = bug）

- **性能预算**（规划 §5.1）：唤出 <100ms P95；击键搜索 <30ms；1000 字分词 <30ms；1 万条滚动 120Hz；常驻 <30MB；峰值 <100MB 且回落；冷启 <300ms；包体 <10MB。
- **依赖白名单**：GRDB.swift、KeyboardShortcuts。新增依赖必须先问用户。
- **`#available` 只允许出现在三个接缝**：`DesignSystem/GlassSurface`、`Capture/PrivacyGate`、`DesignSystem/MotionPolicy`。
- **主线程只做 UI**：DB/正则/分词/图片解码一律后台（02 §7 并发模型）。
- 隐私：尊重 `org.nspasteboard.ConcealedType`；来源 App 取不到就不显示；除 iCloud 备份外不联网。

## 零泄露清单（写涉及生命周期的代码时逐条对照）

- NSPanel：`isReleasedWhenClosed = false`，单一持有者（Controller），复用不重建。
- `NSEvent` 全局/本地 monitor、NotificationCenter observer、`DispatchSource`：成对移除/cancel（deinit 或显式 teardown）。
- timer/异步回调/通知闭包捕获 self 一律显式 `[weak self]`。
- 轮询循环体包 `autoreleasepool`。
- 图片只经 ImageIO 降采样进内存，禁止 NSImage 全图解码；缓存用限额 NSCache。

## 代码约定

- Swift 6 strict concurrency；UI 类型标 `@MainActor`；跨 actor 传 `Sendable` 值类型。
- UserDefaults 只经 `Shared/Settings.swift` 访问；日志用 `os.Logger(subsystem: "io.github.allowo.clipstrate", category: 模块)`；关键路径打 `os_signpost`（点位见 02 §9）。
- 模块依赖方向 `UI → Store/Chop/System → Shared`，禁止反向（02 §2）。
- 一个任务（03 的 T 编号）一个 commit，message 带任务号；完成即跑该任务【验收】。
- specs 未覆盖的行为：按"最像 macOS 内置 App 的做法"实现，并在 commit/PR 里注明。
