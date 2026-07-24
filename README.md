<div align="center">

# Clipstrate

**macOS 26 原生剪贴板管理器 · 液态玻璃观感 · Maccy 级轻量 · 「大爆炸」分词拆选**

*Native macOS 26 clipboard manager — Liquid Glass look, Maccy‑light footprint, "big‑bang" token chopping*

[中文](#中文) · [English](#english)

</div>

---

<a name="中文"></a>

## 中文

Clipstrate 是一个常驻菜单栏的 macOS 剪贴板管理器。它记录你复制过的文本 / 富文本 / 图片 / 文件，用一个液态玻璃面板快速唤出、搜索、粘贴；并提供把一段文本「炸开」成词块逐个挑选的分词能力。全程本地优先，除可选的 iCloud 备份外不联网。

> 系统要求：**macOS 26.0+**、Apple Silicon（arm64）。无 Dock 图标，仅驻留菜单栏。

### 功能

- **剪贴历史**：文本、富文本（RTF/HTML，双份存储）、图片（ImageIO 降采样缩略图）、文件路径；内容寻址去重，命中已有内容只提升时间不新建。
- **即时搜索**：中文子串用 FTS5 trigram，短查询回退 `LIKE`；面板内直接打字即搜（中英文/输入法均可）。
- **「大爆炸」分词**：把一段文本拆成词块，拖选/点选任意组合复制或粘贴；自动识别实体（如验证码、链接等）一键取值。
- **堆栈模式**：连续入栈、按序弹栈粘贴，适合搬运多段内容。
- **置顶与清理**：条目可置顶（永不清理）；按时限（日/周/月…）与磁盘容量自动回收。
- **备份**：本地导入 / 导出 `.clipstrate` 备份；可选 **iCloud Drive 自动备份**（默认开启，见下）。
- **隐私**：尊重 `org.nspasteboard.ConcealedType`（密码类不记录）；取不到来源 App 就不显示；除 iCloud 备份外不联网。
- **内存**：列表只加载预览文本、完整全文按需回源，图片缓存有硬上限并随系统内存压力回落——这些把**大剪贴内容 / 大历史**下的增长压住。稳态常驻主要由 SwiftUI/AppKit 与液态玻璃渲染决定，实测 `phys_footprint` 约 70MB。

### 安装

1. 从 [Releases](https://github.com/allOwO/clipstrate/releases) 下载最新的 `.dmg` 或 `.zip`。
2. 拖入「应用程序」并打开。

> ⚠️ 当前发布产物为 **ad‑hoc 签名、未公证**。首次打开会被 Gatekeeper 拦下，请**右键点击 App → 打开**，或在「系统设置 → 隐私与安全性」里点「仍要打开」。（后续接入 Developer ID 公证后此步骤会消失。）

### 接入 / 首次设置

Clipstrate 首次启动会弹出**引导窗口**，带你完成下面两项授权并实时打勾——这也是获得完整体验前需要做的全部事情：

1. **辅助功能（Accessibility）** — *必需*：用于把选中的历史条目合成 `⌘V` 自动粘贴回你原来的输入框，以及定位光标弹出面板。
   路径：系统设置 → 隐私与安全性 → 辅助功能 → 打开 Clipstrate。
   > 未授权时仍可用：会「只复制到剪贴板」，你手动 `⌘V` 即可。
2. **剪贴板访问** — macOS 26 的剪贴板隐私授权，用于读取复制内容。

授权后无需重启，菜单栏图标上的黄点会消失，即表示就绪。

### 默认快捷键

| 操作 | 快捷键 |
| --- | --- |
| 唤出面板 | `⌥V` |
| 展开分词（大爆炸） | `⌥X` |
| 堆栈开关 | `⌃⇧C` |
| 弹栈并粘贴 | `⌃⇧V` |
| 快速粘贴第 N 条 | `⌘1`–`⌘9` |

面板内：`←/→` 选择 · `⏎` 或单击 粘贴 · `⌥⏎` 纯文本粘贴 · `Tab` 分词 · 直接打字 搜索 · `esc` 关闭。快捷键均可在设置窗口自定义。

### 从源码构建

依赖 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。第三方依赖仅 GRDB.swift 与 KeyboardShortcuts（SPM 自动拉取）。

```bash
xcodegen generate                       # 改了 project.yml 后重跑
xcodebuild -scheme Clipstrate build
xcodebuild -scheme Clipstrate test
```

调试涉及权限（辅助功能 / 剪贴板）时，用 Xcode `⌘R` 跑真 App；重签会重置系统授权属正常。

### 关于自动备份（默认开启）

`0.2.0` 起 **iCloud Drive 自动备份默认开启**：应用会把设置、忽略名单与剪贴历史备份到你自己的 iCloud Drive（不经任何第三方）。可在「设置 → 备份」中关闭，或调整备份内容。剪贴历史可能含敏感信息，如不希望上云请在首次使用时关闭。

### 许可

见 [LICENSE.md](LICENSE.md)（非商业许可）。

---

<a name="english"></a>

## English

Clipstrate is a menu‑bar clipboard manager for macOS. It records the text / rich text / images / files you copy, and lets you summon a Liquid‑Glass panel to search and paste them fast. It also lets you "blow up" a piece of text into tokens and cherry‑pick any combination. Local‑first: no network access beyond optional iCloud backup.

> Requirements: **macOS 26.0+**, Apple Silicon (arm64). No Dock icon — lives in the menu bar.

### Features

- **Clipboard history** — text, rich text (RTF/HTML, stored alongside a plain copy), images (ImageIO‑downsampled thumbnails), file paths. Content‑addressed de‑duplication: re‑copying existing content just bumps recency.
- **Instant search** — FTS5 trigram for CJK substring matching, `LIKE` fallback for short queries; type directly in the panel (works with IME too).
- **"Big‑bang" chopping** — split text into tokens, drag/click‑select any subset to copy or paste; detected entities (codes, links, …) are one‑tap copyable.
- **Stack mode** — enqueue items and paste them back in order.
- **Pin & retention** — pin items (never reclaimed); auto‑reclaim by age (day/week/month/…) and disk cap.
- **Backup** — import/export `.clipstrate` archives locally; optional **iCloud Drive auto‑backup** (on by default, see below).
- **Privacy** — honors `org.nspasteboard.ConcealedType` (passwords aren't recorded); no source app shown if unavailable; no network except iCloud backup.
- **Memory** — lists load preview text only and fetch full text on demand; image caches are hard‑capped and released under memory pressure, bounding growth with **large clips / large history**. Steady‑state residency is dominated by SwiftUI/AppKit and Liquid‑Glass rendering; measured `phys_footprint` ≈ 70 MB.

### Install

1. Download the latest `.dmg` or `.zip` from [Releases](https://github.com/allOwO/clipstrate/releases).
2. Move it to Applications and open.

> ⚠️ Release artifacts are currently **ad‑hoc signed and not notarized**. On first launch Gatekeeper will block it — **right‑click the app → Open**, or click "Open Anyway" under System Settings → Privacy & Security. (This step goes away once Developer ID notarization is wired into the pipeline.)

### Getting Started / Setup

On first launch Clipstrate shows an **onboarding window** that walks you through the two permissions below, ticking them off live — this is everything you need to do to get the full experience:

1. **Accessibility** — *required*: used to synthesize `⌘V` so a chosen history item pastes back into your original field, and to position the panel at your caret.
   Path: System Settings → Privacy & Security → Accessibility → enable Clipstrate.
   > Still usable without it: the app falls back to "copy only" — just press `⌘V` yourself.
2. **Clipboard access** — the macOS 26 pasteboard‑privacy grant, used to read copied content.

No restart needed; the attention dot on the menu‑bar icon clears once you're set.

### Default shortcuts

| Action | Shortcut |
| --- | --- |
| Summon panel | `⌥V` |
| Expand chopping (big‑bang) | `⌥X` |
| Toggle stack | `⌃⇧C` |
| Pop stack & paste | `⌃⇧V` |
| Quick‑paste Nth item | `⌘1`–`⌘9` |

In panel: `←/→` select · `⏎` or click to paste · `⌥⏎` paste as plain text · `Tab` chop · just type to search · `esc` close. All shortcuts are customizable in Settings.

### Build from source

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen). The only third‑party dependencies are GRDB.swift and KeyboardShortcuts (fetched via SPM).

```bash
xcodegen generate                       # re-run after editing project.yml
xcodebuild -scheme Clipstrate build
xcodebuild -scheme Clipstrate test
```

When debugging permission‑related flows (Accessibility / clipboard), run the real app via Xcode `⌘R`; re‑signing resets system grants, which is expected.

### About auto‑backup (on by default)

Since `0.2.0`, **iCloud Drive auto‑backup is on by default**: the app backs up settings, the ignore list, and clipboard history to *your own* iCloud Drive (never any third party). Turn it off or adjust its scope under Settings → Backup. Clipboard history may contain sensitive data — disable this on first use if you'd rather not sync to the cloud.

### License

See [LICENSE.md](LICENSE.md) (non‑commercial).
