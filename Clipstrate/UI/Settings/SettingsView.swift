import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
struct SettingsView: View {
    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin = true
    @AppStorage(SettingsKey.digitModifier) private var digitModifierRaw = DigitModifier.cmd.rawValue
    @AppStorage(SettingsKey.pressAction) private var pressActionRaw = ClickAction.paste.rawValue
    @AppStorage(SettingsKey.returnAction) private var returnActionRaw = ClickAction.paste.rawValue
    @AppStorage(SettingsKey.plainTextDefault) private var plainTextDefault = false
    @AppStorage(SettingsKey.panelStyle) private var panelStyleRaw = PanelStyle.glass.rawValue
    @AppStorage(SettingsKey.panelItemCount) private var panelItemCount = 50
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
    /// 权限状态（实时轮询）：系统对运行中进程的授权状态有缓存，
    /// 但在设置里持续刷新可让用户在系统设置改动后尽快看到变化。
    @State private var pasteboardAllowed = PrivacyGate.isPasteboardAllowed
    @State private var axTrusted = AXPermission.isTrusted
    @State private var observedBackupState = SettingsBackupState.unavailable
    private let permissionPoll = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()
    /// 窗口激活态：失焦时把选中高亮转为系统式灰色（原生窗口非激活观感）。
    @Environment(\.controlActiveState) private var controlActiveState

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
        .onReceive(permissionPoll) { _ in refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginItemStatus()
            refreshBackupState()
        }
        .onAppear {
            refreshLoginItemStatus()
            refreshBackupState()
            onSectionChange(currentSection)
        }
        .onChange(of: currentSection) { _, section in onSectionChange(section) }
        .onChange(of: digitModifierRaw) { _, _ in changed(SettingsKey.digitModifier) }
        .onChange(of: pressActionRaw) { _, _ in changed(SettingsKey.pressAction) }
        .onChange(of: returnActionRaw) { _, _ in changed(SettingsKey.returnAction) }
        .onChange(of: plainTextDefault) { _, _ in changed(SettingsKey.plainTextDefault) }
        .onChange(of: panelStyleRaw) { _, _ in changed(SettingsKey.panelStyle) }
        .onChange(of: panelItemCount) { _, _ in changed(SettingsKey.panelItemCount) }
        .onChange(of: diskCapMB) { _, _ in changed(SettingsKey.diskCapMB) }
        .onChange(of: retentionRaw) { _, _ in changed(SettingsKey.retention) }
        .onChange(of: backupAutoICloud) { _, _ in
            changed(SettingsKey.backupAutoICloud)
            refreshBackupState()
        }
        .onChange(of: backupIncludeSettings) { _, _ in changed(SettingsKey.backupIncludeSettings) }
        .onChange(of: backupIncludeIgnoreList) { _, _ in changed(SettingsKey.backupIncludeIgnoreList) }
        .onChange(of: backupIncludeHistory) { _, _ in changed(SettingsKey.backupIncludeHistory) }
        .onChange(of: backupLastUploadAt) { _, _ in refreshBackupState() }
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
                            SettingsSidebarIcon(
                                section: section,
                                selected: currentSection == section,
                                active: windowActive
                            )
                            Text(section.title)
                                .font(.system(size: 13))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .foregroundStyle(sidebarForeground(selected: currentSection == section))
                        // 交叉淡入淡出（飞书式）：旧选中淡出、新选中淡入，
                        // 用透明度而非条件底色，避免硬切/闪烁。失焦时高亮转灰。
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(sidebarHighlightFill)
                                .opacity(currentSection == section ? 1 : 0)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(currentSection == section ? .isSelected : [])
                    .animation(MotionPolicy.animation(.easeInOut(duration: 0.18)), value: currentSection)
                    .animation(MotionPolicy.animation(.easeInOut(duration: 0.18)), value: controlActiveState)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .frame(width: 188)
    }

    private var windowActive: Bool { controlActiveState != .inactive }

    /// 选中高亮底色：窗口激活用强调色，失焦转系统式灰（原生非激活观感）。
    private var sidebarHighlightFill: Color {
        windowActive ? DS.Colors.accent : Color.secondary.opacity(0.28)
    }

    /// 选中项文字：激活时白字压强调色；失焦（灰底）回落主文字色。
    /// 非选中项文字随窗口失焦一起转灰，贴合 macOS 原生非激活观感。
    private func sidebarForeground(selected: Bool) -> Color {
        guard selected else { return windowActive ? .primary : DS.Colors.secondaryText }
        return windowActive ? .white : .primary
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
                    permissionsSection.id(SettingsSection.permissions)
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
                // 直接跳到分区，无滚动动画（点栏目瞬间定位，不要滑动/闪烁）。
                withAnimation(nil) {
                    proxy.scrollTo(target, anchor: .top)
                }
                scrollTarget = nil
            }
        }
    }

    private var permissionsSection: some View {
        section(.permissions) {
            SettingsGroup {
                permissionRow(
                    title: "剪贴板访问",
                    detail: "读取剪贴板以保存复制历史。",
                    granted: pasteboardAllowed,
                    statusOn: "已允许",
                    statusOff: "未允许",
                    primaryTitle: "请求访问",
                    primaryAction: { PrivacyGate.triggerPasteboardPrompt() },
                    secondaryTitle: "打开系统设置",
                    secondaryAction: { PrivacyGate.openPrivacySettings() }
                )
                SettingsDivider()
                permissionRow(
                    title: "辅助功能",
                    detail: "自动 ⌘V 粘贴、把面板定位到光标、划词拆词。",
                    granted: axTrusted,
                    statusOn: "已授权",
                    statusOff: "未授权",
                    primaryTitle: "请求授权",
                    primaryAction: { AXPermission.promptIfNeeded() },
                    secondaryTitle: "打开系统设置",
                    secondaryAction: { AXPermission.openAccessibilitySettings() }
                )
            }
            SettingsNote(text: "在系统设置里勾选后，若这里仍未变绿：系统对运行中进程的授权状态有缓存，重启一次 Clipstrate 即可生效。")
        }
    }

    /// 单条权限行：左侧标题 + 说明 + 实时状态灯；未授权时右侧给出操作按钮。
    @ViewBuilder
    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        statusOn: String,
        statusOff: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(granted ? Color.green : Color.orange)
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(granted ? statusOn : statusOff)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(granted ? Color.green : Color.orange)
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if !granted {
                HStack(spacing: 6) {
                    if let secondaryTitle, let secondaryAction {
                        Button(secondaryTitle, action: secondaryAction)
                            .buttonStyle(.bordered)
                    }
                    Button(primaryTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 48)
    }

    private var generalSection: some View {
        section(.general) {
            SettingsGroup {
                SettingsToggleRow("登录时启动", isOn: launchAtLoginBinding)
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
                SettingsToggleRow("粘贴为纯文本（全局默认）", isOn: $plainTextDefault)
            }
            IgnoreListSettingsView(
                store: ignoreListStore,
                onChange: actions.ignoreListChanged
            )
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
                SettingsRow("唤出面板显示条数") {
                    Picker("", selection: $panelItemCount) {
                        ForEach(SummonPanelLayout.itemCountOptions, id: \.self) { count in
                            Text("\(count) 条").tag(count)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                SettingsDivider()
                SettingsRow("外观") {
                    Text("跟随系统（浅色 / 深色）")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.secondaryText)
                }
            }
            SettingsNote(text: "面板只显示最近 N 条；搜索始终扫描全部历史,不受此限。兼容模式适配旧版 macOS。")
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
                SettingsToggleRow("自动备份", isOn: $backupAutoICloud)
                    .disabled(!isBackupAvailable)
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
                SettingsToggleRow("配置信息", isOn: $backupIncludeSettings)
                SettingsDivider()
                SettingsToggleRow("忽略名单", isOn: $backupIncludeIgnoreList)
                SettingsDivider()
                SettingsToggleRow("剪贴板历史数据库", isOn: $backupIncludeHistory)
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
                    HStack(spacing: 4) {
                        Text("作者").foregroundStyle(DS.Colors.secondaryText)
                        Text("allOwO").fontWeight(.medium)
                    }
                    .font(.system(size: 12))
                    if let repo = URL(string: "https://github.com/allOwO/clipstrate") {
                        Link(destination: repo) {
                            Label("github.com/allOwO/clipstrate", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 12))
                        }
                    }
                    Text("数据默认仅本地存储 · iCloud 备份可选 · © 2026 allOwO")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }

            SettingsGroupTitle(title: "许可协议")
            SettingsGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("免费供个人 / 非商业用途使用。")
                        .font(.system(size: 12, weight: .medium))
                    Text("禁止用于商业目的或转售 —— PolyForm Noncommercial License 1.0.0。")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let license = URL(string: "https://polyformproject.org/licenses/noncommercial/1.0.0/") {
                        Link("查看协议全文", destination: license)
                            .font(.system(size: 11))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
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
        if case .available = observedBackupState { return true }
        return false
    }

    private var backupStatusText: String {
        switch observedBackupState {
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

    private func refreshBackupState() {
        observedBackupState = actions.backupState()
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

    private func refreshPermissions() {
        let allowed = PrivacyGate.isPasteboardAllowed
        let trusted = AXPermission.isTrusted
        if allowed != pasteboardAllowed { pasteboardAllowed = allowed }
        if trusted != axTrusted { axTrusted = trusted }
    }

    private func refreshLoginItemStatus() {
        let state = loginItemManager.state
        launchAtLogin = state.isSelected
        loginItemNotice = state.notice
    }
}
