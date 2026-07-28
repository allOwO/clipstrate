import SwiftUI

/// 首启三步引导（01 §8）：剪贴板权限 / 辅助功能 / 完整特效。
/// 标准窗口内容，无玻璃观感（DesignSystem 属 M1）。
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    /// 关闭窗口（→ 写 onboarding.done 由 controller 在 windowWillClose 处理）。
    let onFinish: () -> Void

    @State private var step = 0
    /// 「完整特效」选择直写设置（与 SettingsView 同一存储，注册默认值为开）。
    @AppStorage(SettingsKey.fullEffects) private var fullEffects = true

    private let poll = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            Group {
                switch step {
                case 0: clipboardStep
                case 1: accessibilityStep
                default: effectsStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            footer
        }
        .padding(28)
        .frame(width: 520, height: 420)
        .onReceive(poll) { _ in model.refresh() }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("欢迎使用 Clipstrate").font(.title2).bold()
                Text("第 \(step + 1) / 3 步").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 第 1 步：剪贴板

    private var clipboardStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("允许访问剪贴板").font(.headline)
            Text("Clipstrate 需要读取剪贴板来保存你的复制历史。点击下面的按钮会弹出系统提示——请选择「始终允许」。所有数据仅保存在本机。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            statusRow(done: model.pasteboardAllowed,
                      pending: "尚未允许（选择「始终允许」后这里会打勾）",
                      doneText: "已允许访问剪贴板")

            HStack(spacing: 12) {
                Button("请求剪贴板访问") { PrivacyGate.triggerPasteboardPrompt() }
                    .buttonStyle(.borderedProminent)
                Button("打开系统设置") { PrivacyGate.openPrivacySettings() }
                    .buttonStyle(.link)
            }
        }
    }

    // MARK: - 第 2 步：辅助功能

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("开启辅助功能（可选）").font(.headline)
            Text("用于自动按 ⌘V 粘贴、把面板定位到文本光标处、以及划词拆词。跳过也能用——只是改为「复制到剪贴板、由你手动粘贴」，面板出现在鼠标位置。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            statusRow(done: model.axTrusted,
                      pending: "尚未授权（在系统设置里勾选 Clipstrate 后打勾）",
                      doneText: "辅助功能已授权")

            HStack(spacing: 12) {
                // 只弹系统提示（保持在最前、点完即消失）；打开设置拆为独立按钮，
                // 不再同时把设置窗口叠到提示前面导致提示卡在后面不消失。
                Button("请求授权") { AXPermission.promptIfNeeded() }
                    .buttonStyle(.borderedProminent)
                Button("打开系统设置") { AXPermission.openAccessibilitySettings() }
                    .buttonStyle(.link)
            }
        }
    }

    // MARK: - 第 3 步：完整特效（波浪放大）

    private var effectsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("完整特效").font(.headline)
            Text("开启后，在唤出面板里滚动时，光标附近的卡片会像 Dock 放大镜一样轻轻隆起。随时可在 设置 · 显示 里更改。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                EffectsDemoCard(title: "波浪", wavy: true, selected: fullEffects) {
                    fullEffects = true
                }
                EffectsDemoCard(title: "普通", wavy: false, selected: !fullEffects) {
                    fullEffects = false
                }
            }

            HStack(spacing: 10) {
                Text("完整特效").font(.system(size: 13))
                Spacer()
                Toggle("", isOn: $fullEffects)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(.green)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("系统开启「减弱动态效果」时，此特效会自动停用。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 底部导航

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("上一步") { step -= 1 }
            }
            Spacer()
            if step < 2 {
                Button("下一步") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("完成") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func statusRow(done: Bool, pending: String, doneText: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(done ? doneText : pending)
                .foregroundStyle(done ? .primary : .secondary)
                .font(.callout)
        }
    }
}

/// 「完整特效」对比演示卡：迷你卡片条 + 来回扫过的光点。波浪版按与正式实现相同的
/// 余弦衰减隆起（幅度按迷你比例放大以便看清，属示意）；普通版光点同样扫过但卡片不动。
/// 点击整卡即选择对应模式；「减弱动态效果」下演示静止（选择仍可用）。
private struct EffectsDemoCard: View {
    let title: String
    let wavy: Bool
    let selected: Bool
    let onChoose: () -> Void

    /// 迷你条的示意参数：卡宽 26、间距 6、光点影响半径约两张卡。
    private static let cardCount = 6
    private static let cardSize = CGSize(width: 26, height: 40)
    private static let spacing: CGFloat = 6
    /// 迷你卡上按真实幅度只有几 pt，读不出来；示意幅度放大到 1.5×。
    private static let demoMaxScale: CGFloat = 1.5
    /// 按真实凸形的覆盖比例（光标左右各约两张卡）折算到迷你卡距（32pt/张）。
    private static let demoRadius: CGFloat = 80

    var body: some View {
        VStack(spacing: 8) {
            demo
                .frame(height: 78)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 5) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: selected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: onChoose)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)模式\(selected ? "，已选中" : "")")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var demo: some View {
        if MotionPolicy.prefersReducedMotion {
            demoFrame(sweep: 0.5, animated: false)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 40)) { context in
                // 3.2s 一个来回的正弦扫动，两张演示卡相位一致便于对比。
                let t = context.date.timeIntervalSinceReferenceDate
                demoFrame(sweep: 0.5 + 0.5 * sin(t * (2 * .pi / 3.2)), animated: true)
            }
        }
    }

    /// sweep ∈ [0,1]：光点在条内的相对位置。
    private func demoFrame(sweep: Double, animated: Bool) -> some View {
        let stripWidth = CGFloat(Self.cardCount) * Self.cardSize.width
            + CGFloat(Self.cardCount - 1) * Self.spacing
        let pointerX = stripWidth * CGFloat(sweep)
        return VStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: Self.spacing) {
                ForEach(0..<Self.cardCount, id: \.self) { index in
                    let midX = (Self.cardSize.width + Self.spacing) * CGFloat(index)
                        + Self.cardSize.width / 2
                    let falloff = wavy
                        ? WaveMagnify.falloff(distance: midX - pointerX, radius: Self.demoRadius)
                        : 0
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.14 + 0.10 * falloff))
                        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                        .scaleEffect(1 + (Self.demoMaxScale - 1) * falloff, anchor: .bottom)
                }
            }
            .frame(height: Self.cardSize.height * Self.demoMaxScale, alignment: .bottom)
            Circle()
                .fill(Color.secondary)
                .frame(width: 5, height: 5)
                .offset(x: pointerX - stripWidth / 2)
                .opacity(animated ? 1 : 0.5)
        }
        .frame(width: stripWidth + Self.cardSize.width, alignment: .center)
    }
}
