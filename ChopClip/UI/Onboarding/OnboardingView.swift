import SwiftUI

/// 首启两步引导（01 §8）。标准窗口内容，无玻璃观感（DesignSystem 属 M1）。
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    /// 关闭窗口（→ 写 onboarding.done 由 controller 在 windowWillClose 处理）。
    let onFinish: () -> Void

    @State private var step = 0

    private let poll = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            Group {
                if step == 0 { clipboardStep } else { accessibilityStep }
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
                Text("欢迎使用 ChopClip").font(.title2).bold()
                Text("第 \(step + 1) / 2 步").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 第 1 步：剪贴板

    private var clipboardStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("允许访问剪贴板").font(.headline)
            Text("ChopClip 需要读取剪贴板来保存你的复制历史。点击下面的按钮会弹出系统提示——请选择「始终允许」。所有数据仅保存在本机。")
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
                      pending: "尚未授权（在系统设置里勾选 ChopClip 后打勾）",
                      doneText: "辅助功能已授权")

            HStack(spacing: 12) {
                Button("开启辅助功能") {
                    AXPermission.promptIfNeeded()
                    AXPermission.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - 底部导航

    private var footer: some View {
        HStack {
            if step == 1 {
                Button("上一步") { step = 0 }
            }
            Spacer()
            if step == 0 {
                Button("下一步") { step = 1 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("跳过") { onFinish() }
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
