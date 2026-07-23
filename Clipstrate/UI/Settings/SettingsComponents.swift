import AppKit
import SwiftUI

@MainActor
struct SettingsSidebarIcon: View {
    let section: SettingsSection
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let rgb = section.tintRGB
        let nsTint = NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        let bright = nsTint.blended(withFraction: 0.45, of: .white) ?? nsTint
        let dark = nsTint.blended(withFraction: 0.18, of: .black) ?? nsTint

        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(nsColor: bright), Color(nsColor: nsTint), Color(nsColor: dark)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Image(systemName: section.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
        }
        .frame(width: 22, height: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.22 : 0.45), lineWidth: 0.5)
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.34), lineWidth: 1)
                .mask(Rectangle().frame(height: 11).frame(maxHeight: .infinity, alignment: .top))
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.22), radius: 2.5, y: 1)
        .glassSurface(cornerRadius: 7)
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
