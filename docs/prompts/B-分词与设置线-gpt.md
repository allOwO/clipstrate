# Prompt B · 分词与设置线（建议 GPT 5.6 sol）

> 复制以下全文作为新会话的首条消息。进场前提：会话 A 已完成并提交 M0（T0.1–T0.5）。

---

你负责 macOS App **ChopClip v0.1** 的「分词与设置」线开发。仓库在 `.`，Swift 6 + SwiftUI，macOS 26+/arm64。设计与规格已全部定稿且需求冻结，你只做实现，不重开任何已定决策；拿不准一律以 specs 原文为准。

## 开工前（必须实际打开并读完，不要凭印象）

1. 仓库根 `AGENTS.md` —— 本仓库的硬约束（性能预算、零泄露清单、依赖白名单、`#available` 三接缝），全文照办；
2. `docs/specs/README.md` → `docs/specs/01-功能规格.md` 的 §4（分词层）、§6（设置）、§8（Onboarding 仅了解）→ `docs/specs/02-架构与选型.md`（模块划分/并发模型/Schema/UserDefaults key 表）→ `docs/specs/03-开发准备与任务拆分.md` §3–§5；
3. 浏览器打开 `prototype/index.html`：按 `3` 看设置页（通铺+scroll-spy+玻璃晶片图标），在面板上按 `Tab` 看分词层——你的 UI 以它为像素参考。

## 你的任务（按序，验收标准见 specs 03 §3 表格）

1. **T2.1** NLSegmenter（实现 `Segmenter` 协议，NLTokenizer 分词 + 标点标记；1000 字 <30ms 性能单测）；
2. **T2.2** EntityDetector + P0 规则表（specs 01 §4.4 的正则与优先级；每条规则 ≥3 正例 + ≥2 反例单测）；
3. **T2.3/T2.4** ChopOverlay 视图与交互（实体行/词块流/划选锚点语义/键盘，全按 specs 01 §4.2–4.3；挂载到会话 A 在 SummonPanel 预留的 overlay 槽位）；
4. **T2.5** EntityHUD + `⌥X` 展开；**T2.6**〔P1〕SelectionGrabber 划词直拆；
5. **T3.4** 设置窗口：通铺 + scroll-spy + 玻璃晶片边栏图标，specs 01 §6 全表接线到 `Shared/Settings.swift`（key 表 specs 02 §5），每项即时生效；
6. **T3.6**〔P1〕置顶/删除、忽略名单、堆栈模式。

## 边界与协作（严格遵守）

- 你**只拥有**：`Chop/`、`UI/ChopOverlay/`、`UI/EntityHUD/`、`UI/Settings/` 目录及其测试。
- 你**不改**：`App/ Capture/ Store/ System/ Shared/ UI/SummonPanel/ UI/MenuBar/ DesignSystem/` 与 `project.yml`（属会话 A）。需要新增源文件时按 XcodeGen 约定放进你的目录即可（project.yml 用通配，无需改工程文件）；若确需 A 侧改动（如挂载点签名），在 commit message 里写明诉求，由 A 处理。
- 复用 A 提供的 `DesignSystem/GlassSurface` 与颜色/字体 token，**不得自建玻璃实现**。
- 在分支 `feat/chop-settings` 上工作（建议 `git worktree` 隔离）；每完成一个任务 rebase 一次 `main`；一个任务一个 commit，message 以任务号开头（如 `T2.2: EntityDetector P0 规则`）。

## 硬约束（违反=返工）

- 不新增任何依赖（白名单 GRDB + KeyboardShortcuts 已固定）；不引入网络请求。
- Swift 6 strict concurrency：分词/正则在后台执行，UI 类型标 `@MainActor`；`#available` 不允许出现在你的目录（三接缝都在 A 侧）。
- timer/observer/闭包捕获遵守 AGENTS.md 零泄露清单；每任务完成跑 `xcodebuild test` + 对应【验收】。
- specs 未覆盖的行为：按"最像 macOS 内置 App 的做法"实现，并在 commit message 注明。

从 T2.1 开始；T2.1/T2.2 是纯逻辑+单测，不依赖任何 UI，可立即动手。
