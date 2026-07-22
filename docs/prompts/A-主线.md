# Prompt A · 主工程线

> 复制以下全文作为新会话的首条消息。

---

你负责 macOS App **Clipstrate v0.1** 的主工程线开发。当前目录是仓库根目录，设计与规格已全部定稿，你只做实现，不重开任何已定决策。

## 开工前（按顺序读）

1. 仓库根 `AGENTS.md`（硬约束：性能预算、零泄露清单、依赖白名单、`#available` 三接缝）；
2. `docs/specs/README.md`（总览与阅读法）→ `docs/specs/02-架构与选型.md`（全读）→ `docs/specs/03-开发准备与任务拆分.md` §1–§2（环境与脚手架）；
3. 领到 UI 任务时读 `docs/specs/01-功能规格.md` 对应章节，并用浏览器打开 `prototype/index.html` 逐项对照（底部浮条切界面，这是像素级参考）。

## 你的任务（严格按 T 编号顺序，清单与【验收】见 specs 03 §3）

- **M0 全部**：T0.1 脚手架（XcodeGen，specs 03 §2 有 project.yml 骨架）→ T0.2 GRDB/FTS → T0.3 采集 → T0.4 PrivacyGate+Onboarding → T0.5 配额清理。
- **M1 全部**：T1.1 热键 → T1.2 面板控制器 → T1.3 卡片条 UI（变体 C）→ T1.4 两层键盘焦点 → T1.5 PasteService → T1.6 三类卡片 → T1.7 数字直贴 → T1.8 Popover → T1.9 面板 type-to-search。
- 之后（另一条线并入后）：T3.1–T3.3、T3.5 性能/泄露/边界/动效，M4 发布线。

**完成 M0（T0.5 验收过、已 commit）时明确宣告一次**——另一个会话（分词与设置线）以此为进场信号。

## 边界（与并行会话 B 的分工）

- 你**拥有**：`App/ Capture/ Store/ System/ Shared/ UI/SummonPanel/ UI/MenuBar/ UI/Onboarding/ DesignSystem/` 及工程文件（project.yml）。
- 你**不碰**：`Chop/`、`UI/ChopOverlay/`、`UI/EntityHUD/`、`UI/Settings/`（会话 B 负责）。T1.3 里给 ChopOverlay 预留挂载点（面板上层 overlay 槽位 + 打开/关闭回调）即可，不实现内容。
- DesignSystem（GlassSurface、颜色/字体 token、动效降级开关）由你在 T1.3 前建好——B 会直接复用，接口保持稳定。
- 直接在 `main` 串行提交；一个任务一个 commit，message 以任务号开头（如 `T1.3: 卡片条 UI`）。

## 硬约束（违反=返工）

- 依赖白名单只有 GRDB.swift + KeyboardShortcuts；新增依赖必须先问用户。
- Swift 6 strict concurrency；主线程只做 UI，DB/分词/图片解码全后台；`#available` 只允许出现在三接缝（GlassSurface / PrivacyGate / 动效降级）。
- 每个任务完成即跑 `xcodebuild test` + 该任务【验收】；涉及 NSPanel/监听器/timer 的代码逐条对照 AGENTS.md 零泄露清单。
- specs 未覆盖的行为：按"最像 macOS 内置 App 的做法"实现，并在 commit message 里注明该决策。

现在从 T0.1 开始。
