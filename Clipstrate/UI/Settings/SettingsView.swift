import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
struct SettingsView: View {
    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin = true
    @AppStorage(SettingsKey.digitModifier) private var digitModifierRaw = DigitModifier.cmd.rawValue
    @AppStorage(SettingsKey.pressAction) private var pressActionRaw = ClickAction.paste.rawValue
    @AppStorage(SettingsKey.returnAction) private var returnActionRaw = ClickAction.paste.rawValue
    @AppStorage(SettingsKey.autoClose) private var autoClose = true
    @AppStorage(SettingsKey.plainTextDefault) private var plainTextDefault = false
    @AppStorage(SettingsKey.panelStyle) private var panelStyleRaw = PanelStyle.glass.rawValue
    @AppStorage(SettingsKey.diskCapMB) private var diskCapMB = 512
    @AppStorage(SettingsKey.retention) private var retentionRaw = Retention.month.rawValue
    @AppStorage(SettingsKey.backupAutoICloud) private var backupAutoICloud = false
    @AppStorage(SettingsKey.backupIncludeSettings) private var backupIncludeSettings = true
    @AppStorage(SettingsKey.backupIncludeIgnoreList) private var backupIncludeIgnoreList = true
    @AppStorage(SettingsKey.backupIncludeHistory) private var backupIncludeHistory = true
    @AppStorage(SettingsKey.backupLastUploadAt) private var backupLastUploadAt = 0.0

    @State private var currentSection = SettingsSection.general
    @State private var scrollTarget: SettingsSection?
    @State private var sectionOffsets: [SettingsSection: CGFloat] = [:]
    @State private var isAtBottom = false
    @State private var loginItemError: String?
    @State private var loginItemNotice: String?
    /// 点侧栏后，在目标分区的几何位置真正稳定前冻结 scroll-spy。
    /// 不能依赖无动画事务的 completion：它可能早于 offset preference 更新完成。
    @State private var programmaticScrollTarget: SettingsSection?

    private let actions: SettingsActions
    private let loginItemManager: any LoginItemManaging
    private let ignoreListStore: IgnoreListStore
    private let onSectionChange: (SettingsSection) -> Void

    init(
        actions: SettingsActions = SettingsActions(),
        loginItemManager: any LoginItemManaging = SystemLoginItemManager(),
        ignoreListStore: IgnoreListStore = IgnoreListStore.makeDefault(),
        onSectionChange: @escaping (SettingsSection) -> Void = { _ in }
    ) {
        self.actions = actions
        self.loginItemManager = loginItemManager
        self.ignoreListStore = ignoreListStore
        self.onSectionChange = onSectionChange
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(DS.Colors.divider)
            settingsPage
        }
        .frame(minWidth: 680, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginItemStatus()
        }
        .onAppear {
            refreshLoginItemStatus()
            onSectionChange(currentSection)
        }
        .onChange(of: currentSection) { _, section in onSectionChange(section) }
        .onChange(of: digitModifierRaw) { _, _ in changed(SettingsKey.digitModifier) }
        .onChange(of: pressActionRaw) { _, _ in changed(SettingsKey.pressAction) }
        .onChange(of: returnActionRaw) { _, _ in changed(SettingsKey.returnAction) }
        .onChange(of: autoClose) { _, _ in changed(SettingsKey.autoClose) }
        .onChange(of: plainTextDefault) { _, _ in changed(SettingsKey.plainTextDefault) }
        .onChange(of: panelStyleRaw) { _, _ in changed(SettingsKey.panelStyle) }
        .onChange(of: diskCapMB) { _, _ in changed(SettingsKey.diskCapMB) }
        .onChange(of: retentionRaw) { _, _ in changed(SettingsKey.retention) }
        .onChange(of: backupAutoICloud) { _, _ in changed(SettingsKey.backupAutoICloud) }
        .onChange(of: backupIncludeSettings) { _, _ in changed(SettingsKey.backupIncludeSettings) }
        .onChange(of: backupIncludeIgnoreList) { _, _ in changed(SettingsKey.backupIncludeIgnoreList) }
        .onChange(of: backupIncludeHistory) { _, _ in changed(SettingsKey.backupIncludeHistory) }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        programmaticScrollTarget = section
                        currentSection = section
                        scrollTarget = section
                    } label: {
                        HStack(spacing: 8) {
                            SettingsSidebarIcon(section: section)
                            Text(section.title)
                                .font(.system(size: 13))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .foregroundStyle(currentSection == section ? Color.white : Color.primary)
                        .background(
                            currentSection == section ? DS.Colors.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(currentSection == section ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .frame(width: 188)
    }

    private var settingsPage: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    generalSection.id(SettingsSection.general)
                    shortcutsSection.id(SettingsSection.shortcuts)
                    interactionSection.id(SettingsSection.interaction)
                    displaySection.id(SettingsSection.display)
                    storageSection.id(SettingsSection.storage)
                    backupSection.id(SettingsSection.backup)
                    aboutSection.id(SettingsSection.about)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .coordinateSpace(name: "settings-scroll")
            .onSettingsSectionOffsets { offsets in
                sectionOffsets = offsets
                updateScrollSpy()
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height
                    >= geometry.contentSize.height - 4
            } action: { _, atBottom in
                isAtBottom = atBottom
                updateScrollSpy()
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(MotionPolicy.animation(.easeInOut(duration: 0.24))) {
                    proxy.scrollTo(target, anchor: .top)
                }
                scrollTarget = nil
            }
        }
    }

    private var generalSection: some View {
        section(.general) {
            SettingsGroup {
                SettingsRow("登录时启动") {
                    Toggle("", isOn: launchAtLoginBinding).labelsHidden()
                }
            }
            if let loginItemError {
                SettingsNote(text: "登录项更新失败：\(loginItemError)")
                    .foregroundStyle(.red)
            }
            if let loginItemNotice {
                SettingsNote(text: loginItemNotice)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var shortcutsSection: some View {
        section(.shortcuts) {
            SettingsGroupTitle(title: "唤出 / 关闭剪贴板面板")
            SettingsGroup {
                SettingsRow("双击修饰键唤出") {
                    Picker("", selection: .constant(0)) { Text("暂无").tag(0) }
                        .labelsHidden().frame(width: 140).disabled(true)
                }
                SettingsDivider()
                SettingsRow("Fn 单击唤出") {
                    Picker("", selection: .constant(0)) { Text("暂无").tag(0) }
                        .labelsHidden().frame(width: 140).disabled(true)
                }
                SettingsDivider()
                SettingsRow("唤出 / 关闭面板") {
                    KeyboardShortcuts.Recorder(for: .summon)
                }
                SettingsDivider()
                SettingsRow("划词拆词") {
                    KeyboardShortcuts.Recorder(for: .chop)
                }
            }
            SettingsNote(text: "双击修饰键与 Fn 入口为 P1；02 §5 暂无持久化 key，当前保持“暂无”。")

            SettingsGroupTitle(title: "剪贴板堆栈")
            SettingsGroup {
                SettingsRow("开启 / 关闭") {
                    KeyboardShortcuts.Recorder(for: .stackToggle)
                }
                SettingsDivider()
                SettingsRow("单条粘贴") {
                    KeyboardShortcuts.Recorder(for: .stackPaste)
                }
            }

            SettingsGroupTitle(title: "数字快捷键")
            SettingsGroup {
                SettingsRow("修饰键 + 1~9") {
                    Picker("", selection: digitModifierBinding) {
                        ForEach(DigitModifier.allCases, id: \.self) { value in
                            Text(value.settingsLabel).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }
        }
    }

    private var interactionSection: some View {
        section(.interaction) {
            SettingsGroup {
                SettingsRow("按下后（数字键）") {
                    actionPicker(selection: pressActionBinding)
                }
                SettingsDivider()
                SettingsRow("双击 / 回车") {
                    actionPicker(selection: returnActionBinding)
                }
                SettingsDivider()
                SettingsRow("操作完成后自动关闭窗口") {
                    Toggle("", isOn: $autoClose).labelsHidden()
                }
                SettingsDivider()
                SettingsRow("粘贴为纯文本（全局默认）") {
                    Toggle("", isOn: $plainTextDefault).labelsHidden()
                }
            }
            IgnoreListSettingsView(store: ignoreListStore)
        }
    }

    private var displaySection: some View {
        section(.display) {
            SettingsGroup {
                SettingsRow("面板样式") {
                    HStack(spacing: 5) {
                        Button("玻璃面板") { panelStyleRaw = PanelStyle.glass.rawValue }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button("兼容模式") {}
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(true)
                        Text("下期支持")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                SettingsDivider()
                SettingsRow("外观") {
                    Text("跟随系统（浅色 / 深色）")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.secondaryText)
                }
            }
            SettingsNote(text: "兼容模式适配旧版 macOS。")
        }
    }

    private var storageSection: some View {
        section(.storage) {
            SettingsGroup {
                SettingsRow("磁盘空间上限") {
                    Picker("", selection: $diskCapMB) {
                        ForEach(SettingsCatalog.diskCapsMB, id: \.self) { value in
                            Text(diskCapLabel(value)).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                SettingsDivider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("存储时间限制").font(.system(size: 13))
                    Slider(value: retentionIndexBinding, in: 0...6, step: 1)
                    HStack(spacing: 0) {
                        ForEach(SettingsCatalog.retentions, id: \.self) { value in
                            Button(value.settingsLabel) { retentionRaw = value.rawValue }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: retention == value ? .semibold : .regular))
                                .foregroundStyle(retention == value ? DS.Colors.accent : DS.Colors.secondaryText)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            SettingsNote(text: "超限时自动清理最旧的未置顶条目。")
        }
    }

    private var backupSection: some View {
        section(.backup) {
            SettingsGroupTitle(title: "iCloud 云备份")
            SettingsGroup {
                SettingsRow("备份状态") {
                    Text(backupStatusText)
                        .font(.system(size: 13))
                        .foregroundStyle(isBackupAvailable ? Color.green : DS.Colors.secondaryText)
                }
                SettingsDivider()
                SettingsRow("上次备份") {
                    Text(lastBackupText)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.secondaryText)
                }
                SettingsDivider()
                SettingsRow("自动备份") {
                    Toggle("", isOn: $backupAutoICloud).labelsHidden()
                        .disabled(!isBackupAvailable)
                }
                SettingsDivider()
                HStack(spacing: 8) {
                    Button("立即备份", action: actions.backupNow)
                        .buttonStyle(.borderedProminent)
                    Button("从 iCloud 恢复", action: actions.restoreFromCloud)
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
                .disabled(!isBackupAvailable)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsGroupTitle(title: "导入 / 导出")
            SettingsGroup {
                SettingsRow("配置信息") {
                    Toggle("", isOn: $backupIncludeSettings).labelsHidden()
                }
                SettingsDivider()
                SettingsRow("忽略名单") {
                    Toggle("", isOn: $backupIncludeIgnoreList).labelsHidden()
                }
                SettingsDivider()
                SettingsRow("剪贴板历史数据库") {
                    Toggle("", isOn: $backupIncludeHistory).labelsHidden()
                }
                SettingsDivider()
                HStack(spacing: 8) {
                    Button("导入…", action: actions.importBackup)
                    Button("导出…", action: actions.exportBackup)
                }
                .controlSize(.small)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            SettingsNote(text: "导出为单个 .clipstrate 文件，包含所选数据；历史数据库可能较大。")
        }
    }

    private var aboutSection: some View {
        section(.about) {
            SettingsGroup {
                VStack(spacing: 6) {
                    Image(systemName: "scissors")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                    Text("Clipstrate").font(.system(size: 16, weight: .bold))
                    Text("版本 \(Bundle.main.shortVersion)（\(Bundle.main.buildNumber)）")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.secondaryText)
                    Text("数据全本地存储 · 不联网 · © 2026")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            }
        }
    }

    private func section<Content: View>(
        _ section: SettingsSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            SettingsSectionHeader(title: section.title)
            content()
        }
        .settingsSectionOffset(section)
    }

    private func actionPicker(selection: Binding<ClickAction>) -> some View {
        Picker("", selection: selection) {
            ForEach(ClickAction.allCases, id: \.self) { action in
                Text(action.settingsLabel).tag(action)
            }
        }
        .labelsHidden()
        .frame(width: 150)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                do {
                    try loginItemManager.setEnabled(enabled)
                    loginItemError = nil
                    refreshLoginItemStatus()
                    changed(SettingsKey.launchAtLogin)
                } catch {
                    loginItemError = error.localizedDescription
                    refreshLoginItemStatus()
                }
            }
        )
    }

    private var digitModifierBinding: Binding<DigitModifier> {
        rawBinding($digitModifierRaw, default: .none)
    }

    private var pressActionBinding: Binding<ClickAction> {
        rawBinding($pressActionRaw, default: .paste)
    }

    private var returnActionBinding: Binding<ClickAction> {
        rawBinding($returnActionRaw, default: .paste)
    }

    private func rawBinding<Value: RawRepresentable>(
        _ rawValue: Binding<String>,
        default defaultValue: Value
    ) -> Binding<Value> where Value.RawValue == String {
        Binding(
            get: { Value(rawValue: rawValue.wrappedValue) ?? defaultValue },
            set: { rawValue.wrappedValue = $0.rawValue }
        )
    }

    private var retention: Retention {
        Retention(rawValue: retentionRaw) ?? .month
    }

    private var retentionIndexBinding: Binding<Double> {
        Binding(
            get: { Double(SettingsCatalog.retentions.firstIndex(of: retention) ?? 2) },
            set: { index in
                let clamped = min(max(Int(index.rounded()), 0), SettingsCatalog.retentions.count - 1)
                retentionRaw = SettingsCatalog.retentions[clamped].rawValue
            }
        )
    }

    private var isBackupAvailable: Bool {
        if case .available = actions.backupState { return true }
        return false
    }

    private var backupStatusText: String {
        switch actions.backupState {
        case .unavailable: "请在系统设置开启 iCloud 云盘"
        case let .available(status): status
        }
    }

    private var lastBackupText: String {
        guard backupLastUploadAt > 0 else { return "尚未备份" }
        return Date(timeIntervalSince1970: backupLastUploadAt).formatted(
            date: .numeric,
            time: .shortened
        )
    }

    private func diskCapLabel(_ value: Int) -> String {
        value >= 1_024 ? "\(value / 1_024)GB" : "\(value)MB"
    }

    private func changed(_ key: String) {
        actions.settingChanged(key)
    }

    private func updateScrollSpy() {
        let observed = SettingsScrollSpy.section(offsets: sectionOffsets, isAtBottom: isAtBottom)
        let synchronized = SettingsScrollSpy.synchronize(
            programmaticTarget: programmaticScrollTarget,
            observed: observed
        )
        programmaticScrollTarget = synchronized.pendingTarget
        if synchronized.section != currentSection {
            currentSection = synchronized.section
        }
    }

    private func refreshLoginItemStatus() {
        let state = loginItemManager.state
        launchAtLogin = state.isSelected
        loginItemNotice = state.notice
    }
}
