import AppKit
import SwiftUI

/// 侧栏分区图标：极简单色线性符号 + 一枚 Liquid Glass 薄片，
/// 取代旧的彩色渐变方块。随选中 / 窗口激活态调整前景与底片。
@MainActor
struct SettingsSidebarIcon: View {
    let section: SettingsSection
    var selected = false
    var active = true

    var body: some View {
        Image(systemName: section.symbol)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(symbolColor)
            .frame(width: 22, height: 22)
            .background(chip)
    }

    private var symbolColor: Color {
        if selected { return active ? .white : .primary }
        return active ? DS.Colors.secondaryText : DS.Colors.secondaryText.opacity(0.45)
    }

    @ViewBuilder
    private var chip: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if selected {
            // 选中行底色已是强调 / 灰，图标叠一层半透明白霜片贴合底色。
            shape.fill(.white.opacity(active ? 0.20 : 0.10))
        } else {
            // 未选中：极简玻璃薄片 + 发丝描边，弱存在感。
            shape
                .fill(Color.primary.opacity(0.05))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .glassSurface(cornerRadius: 6)
                .opacity(active ? 1 : 0.6)
        }
    }
}

@MainActor
struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .glassSurface(cornerRadius: 12)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@MainActor
struct SettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer(minLength: 20)
            control
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 38)
    }
}

/// 开关行：整行标签区域都可点击切换（不再要求精准命中右侧小开关）。
/// 用原生 `Toggle` + `.switch` 样式，标签铺满行宽，点标签即切换（macOS 惯例）。
@MainActor
struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 20)
            // 开关只作视觉呈现，命中交给整行手势，避免「开关切一次 + 手势又切一次」双重触发。
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 38)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

@MainActor
struct SettingsDivider: View {
    var body: some View {
        Divider().overlay(DS.Colors.divider).padding(.leading, 14)
    }
}

@MainActor
struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 10)
            .padding(.bottom, 8)
    }
}

@MainActor
struct SettingsGroupTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DS.Colors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }
}

@MainActor
struct SettingsNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }
}

private struct SettingsSectionOffsetPreferenceKey: PreferenceKey {
    nonisolated static let defaultValue: [SettingsSection: CGFloat] = [:]

    nonisolated static func reduce(
        value: inout [SettingsSection: CGFloat],
        nextValue: () -> [SettingsSection: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func settingsSectionOffset(_ section: SettingsSection) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SettingsSectionOffsetPreferenceKey.self,
                    value: [section: proxy.frame(in: .named("settings-scroll")).minY]
                )
            }
        }
    }

    func onSettingsSectionOffsets(
        perform action: @escaping ([SettingsSection: CGFloat]) -> Void
    ) -> some View {
        onPreferenceChange(SettingsSectionOffsetPreferenceKey.self, perform: action)
    }
}
