import AppKit
import SwiftUI

/// 唤出面板内容（01 §3.2 变体 C）：无外层容器、独立玻璃卡片、底边对齐。
/// 卡片视觉、两层焦点与三类内容渲染集中在此；搜索态由 T1.9 继续扩展。
struct SummonPanelView: View {
    @ObservedObject var model: SummonPanelModel

    var body: some View {
        ZStack {
            searchInput

            cardLayer
                .opacity(model.overlayView == nil ? 1 : DS.Metrics.overlayDimOpacity)
                .allowsHitTesting(model.overlayView == nil)
                .animation(.easeInOut(duration: DS.Anim.ringFadeDuration), value: model.overlayView != nil)

            if let overlayView = model.overlayView {
                overlayView
                    .frame(maxWidth: DS.Metrics.chopOverlayMaxWidth)
                    .transition(MotionPolicy.overlayTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 常驻但不可见的唯一文本输入客户端。面板唤出后立即聚焦，因此输入法可直接开始组合；
    /// 查询为空时搜索胶囊仍保持隐藏，不改变无框卡片条的视觉。
    private var searchInput: some View {
        SummonSearchInput(
            text: Binding(
                get: { model.searchQuery },
                set: { model.setSearchQuery($0) }
            ),
            isActive: model.imeInputActive
        )
        .frame(width: 1, height: 1)
        .opacity(0.001)
    }

    private var cardLayer: some View {
        VStack(spacing: DS.Metrics.hintPillGap) {
            if model.isSearching { searchCapsule }
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    if model.items.isEmpty {
                        emptyState
                    } else {
                        LazyHStack(alignment: .bottom, spacing: DS.Metrics.cardSpacing) {
                            ForEach(Array(model.items.enumerated()), id: \.element.contentHash) { index, item in
                                SummonCardView(
                                    item: item,
                                    index: index,
                                    isSelected: index == model.selectedIndex,
                                    isActionLayer: index == model.selectedIndex && model.focus != .card,
                                    focusedActionIndex: index == model.selectedIndex ? model.focus.actionIndex : nil,
                                    blobStore: model.blobStore,
                                    presentationEpoch: model.presentationEpoch,
                                    isPanelPresented: model.isPanelPresented,
                                    onActivate: { model.activateCard(at: index) },
                                    onPlainText: { model.activateAction(0) },
                                    onChop: { model.activateAction(1) }
                                )
                                // 固定高度底对齐槽位：卡片长大只在槽内向上发生，
                                // 不改变行高、不引起纵向重排或向下过冲。
                                .frame(height: DS.Metrics.cardSelected.height, alignment: .bottom)
                                .id(cardID(item))
                            }
                        }
                        .frame(minWidth: 0, minHeight: DS.Metrics.cardSelected.height, alignment: .bottomLeading)
                        // 四周等量留白：卡片玻璃阴影在留白内羽化完，ScrollView 的裁剪
                        // 边界落在透明区——既不裁成硬线，也不向下铺出（下探）。
                        .padding(SummonPanelLayout.shadowPadding)
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.selectedIndex) { _, index in
                    guard model.items.indices.contains(index) else { return }
                    // 瞬时定位，不做滚动动画（与「无生长动画」一致）。
                    proxy.scrollTo(cardID(model.items[index]), anchor: .center)
                }
            }
            .frame(height: DS.Metrics.cardSelected.height + SummonPanelLayout.shadowPadding * 2)

            SummonHintPill()
        }
        .padding(.vertical, SummonPanelLayout.verticalPadding)
    }

    private func cardID(_ item: ClipItem) -> String {
        "\(item.contentHash)-\(model.presentationEpoch)"
    }

    private var emptyState: some View {
        Text("尚无剪贴板历史")
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .glassSurface(cornerRadius: 999)
            .frame(maxWidth: .infinity, minHeight: DS.Metrics.cardSelected.height)
    }

    /// 搜索胶囊（01 §3.6）：🔍 + 查询词 + 匹配数。输入由常驻隐藏 TextField 接收，
    /// 胶囊仅负责显示，因此中英文都能从第一个字符直接搜索。
    private var searchCapsule: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(model.searchQuery)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .frame(minWidth: 60)
            .fixedSize()
            Text(model.items.isEmpty ? "无匹配" : "\(model.matchCount)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassSurface(cornerRadius: 999)
        .contentShape(Capsule())
        .onTapGesture { model.beginIMEInput() }
    }
}

/// SwiftUI 的透明 TextField 不保证会成为 first responder；显式使用 AppKit 文本输入客户端，
/// 才能让拼音等输入法在第一个按键时收到 marked-text 组合事件。
private struct SummonSearchInput: NSViewRepresentable {
    @Binding var text: String
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> SummonSearchTextField {
        let field = SummonSearchTextField()
        field.delegate = context.coordinator
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: SummonSearchTextField, context: Context) {
        context.coordinator.text = $text

        let isComposing = (field.currentEditor() as? NSTextInputClient)?.hasMarkedText() ?? false
        if field.stringValue != text, !isComposing {
            field.stringValue = text
            if let editor = field.currentEditor() {
                editor.string = text
                editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            }
        }
        field.inputActive = isActive
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

@MainActor
private final class SummonSearchTextField: NSTextField {
    var inputActive = false {
        didSet { updateFirstResponder() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateFirstResponder()
    }

    private func updateFirstResponder() {
        guard let window else { return }
        if inputActive {
            if currentEditor() == nil {
                window.makeFirstResponder(self)
            }
        } else if let editor = currentEditor(), window.firstResponder === editor {
            window.makeFirstResponder(nil)
        }
    }
}

private struct SummonCardView: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let isActionLayer: Bool
    let focusedActionIndex: Int?
    let blobStore: BlobStore?
    let presentationEpoch: Int
    let isPanelPresented: Bool
    let onActivate: () -> Void
    let onPlainText: () -> Void
    let onChop: () -> Void

    @State private var isEntered = false
    @State private var isHovered = false

    private var size: CGSize {
        isSelected ? DS.Metrics.cardSelected : DS.Metrics.cardUnselected
    }

    private var presentation: ClipCardPresentation {
        ClipCardPresentation(item: item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
            if isSelected, item.kind == .text {
                actions
            }
        }
        .padding(10)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        // 内容一律裁到卡片轮廓内（在 glass/描边/阴影之前），任何内容都不外溢。
        .clipShape(RoundedRectangle(cornerRadius: DS.Metrics.cardCornerRadius, style: .continuous))
        // 不给选中卡加灰 tint：选中已由「放大 + 强调色描边」表达；
        // 若再改背景明暗，切换时会明暗跳变、显得刺眼（闪）。
        .glassSurface(
            cornerRadius: DS.Metrics.cardCornerRadius,
            interactive: true
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: DS.Metrics.cardCornerRadius, style: .continuous)
                    .stroke(DS.Colors.selectionRing, lineWidth: DS.Metrics.selectionRingWidth)
                    .opacity(isActionLayer ? DS.Metrics.actionLayerRingOpacity : 1)
            }
        }
        // 不再叠显式 shadow：glassEffect 自带四周均匀的 Liquid Glass 投影。
        // 选中不做生长动画：尺寸瞬时切换（回到最初方案），彻底消除生长过程中的下探。
        .opacity(isEntered ? 1 : 0)
        .offset(y: entranceOffset)
        .offset(y: isHovered ? -4 : 0)
        .scaleEffect(entranceScale, anchor: .bottom)
        .contentShape(RoundedRectangle(cornerRadius: DS.Metrics.cardCornerRadius, style: .continuous))
        .onTapGesture(perform: onActivate)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) { isHovered = hovering }
        }
        .onAppear { updateEntrance(animate: presentationEpoch > 0 && isPanelPresented) }
        .onChange(of: isPanelPresented) { _, presented in
            if !presented { animateExit() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(index + 1) 条，\(presentation.typeLabel)，\(presentation.body)")
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(presentation.typeLabel)
                .font(DS.Typography.cardTypeLabel)
                .tracking(0.4)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 2)

            if let sourceName = presentation.sourceName {
                SourceAppBadge(bundleID: item.appBundleID, name: sourceName)
            }
        }
        .padding(.trailing, 20)
        .overlay(alignment: .topTrailing) {
            Text("\(index + 1)")
                .font(DS.Typography.badge)
                .foregroundStyle(.secondary)
                .frame(minWidth: 16, minHeight: 16)
                .padding(.horizontal, 2)
                .background(.primary.opacity(0.08), in: Capsule())
                .offset(x: 20)
        }
        .frame(height: 16)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            TextCardContent(
                item: item,
                presentation: presentation,
                isSelected: isSelected,
                blobStore: blobStore
            )
        case .image:
            ImageCardContent(
                item: item,
                presentation: presentation,
                isSelected: isSelected,
                blobStore: blobStore
            )
        case .file:
            FileCardContent(item: item, presentation: presentation, isSelected: isSelected)
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            ActionCapsule(title: "纯文本", isFocused: focusedActionIndex == 0, action: onPlainText)
            ActionCapsule(title: "✂︎ 分词", isFocused: focusedActionIndex == 1, action: onChop)
        }
        .padding(.top, 8)
    }

    private var entranceOffset: CGFloat {
        guard !isEntered, !MotionPolicy.prefersReducedMotion else { return 0 }
        return DS.Anim.entranceRise
    }

    private var entranceScale: CGFloat {
        guard !isEntered, !MotionPolicy.prefersReducedMotion else { return 1 }
        return DS.Anim.entranceScale
    }

    private func updateEntrance(animate: Bool) {
        isEntered = false
        guard animate else {
            isEntered = true
            return
        }
        // 错开延时封顶，卡片多时末卡也不至于迟迟才动。
        let full = Animation.spring(response: 0.30, dampingFraction: 0.82)
            .delay(Double(min(index, 6)) * DS.Anim.entranceStagger)
        withAnimation(MotionPolicy.animation(full)) {
            isEntered = true
        }
    }

    private func animateExit() {
        withAnimation(MotionPolicy.animation(.easeIn(duration: DS.Anim.closeDuration))) {
            isEntered = false
        }
    }
}

private struct TextCardContent: View {
    let item: ClipItem
    let presentation: ClipCardPresentation
    let isSelected: Bool
    let blobStore: BlobStore?

    @State private var richText: AttributedString?

    var body: some View {
        Group {
            if let richText {
                Text(richText)
            } else {
                Text(presentation.body)
            }
        }
        .font(isSelected ? DS.Typography.cardBody : DS.Typography.cardBodyCompact)
        .foregroundStyle(.primary)
        .lineSpacing(2)
        .lineLimit(isSelected ? 6 : 4)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: item.blobPath) {
            guard item.isRich, let blobStore else { return }
            richText = await CardAssetLoader.shared.richText(for: item, store: blobStore)
        }
    }
}

private struct ImageCardContent: View {
    let item: ClipItem
    let presentation: ClipCardPresentation
    let isSelected: Bool
    let blobStore: BlobStore?

    @State private var thumbnail: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Color.clear 定尺（受卡片约束），图片作 overlay：overlay 恒等于底视图尺寸，
            // 因此超宽图（如 1400×128）scaledToFill 只会在内部溢出、被 clipShape 裁掉，
            // 绝不会撑大布局顶出卡片。ZStack 会取最大子视图尺寸，故不能用。
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: presentation.symbolName)
                            .font(.system(size: isSelected ? 38 : 30, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                }
                .background(DS.Colors.placeholderFill)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if isSelected {
                Text(presentation.body)
                    .font(DS.Typography.cardMeta)
                    .lineLimit(1)
            }
            if let meta = presentation.meta {
                Text(meta)
                    .font(DS.Typography.cardMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: item.thumbPath) {
            guard let name = item.thumbPath, let blobStore else { return }
            thumbnail = await CardAssetLoader.shared.thumbnail(named: name, store: blobStore)
        }
    }
}

private struct FileCardContent: View {
    let item: ClipItem
    let presentation: ClipCardPresentation
    let isSelected: Bool

    @State private var meta: String?
    @State private var icon: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.Colors.placeholderFill)
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(isSelected ? 18 : 12)
                } else {
                    Image(systemName: presentation.symbolName)
                        .font(.system(size: isSelected ? 38 : 30, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            Text(presentation.body)
                .font(DS.Typography.cardMeta)
                .lineLimit(1)
            if let meta {
                Text(meta)
                    .font(DS.Typography.cardMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 图标与元信息异步加载，不阻塞首次唤出的同步渲染（<100ms 预算）。
        .task(id: item.fileURLs) {
            let paths = item.fileURLs ?? []
            icon = await FileIconCache.shared.icon(path: paths.first)
            meta = await CardAssetLoader.shared.fileMeta(paths: paths)
        }
    }
}

@MainActor
private final class FileIconCache {
    static let shared = FileIconCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 64
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    /// async：命中缓存即返回；未命中才问 Launch Services。由卡片的 `.task` 在首次渲染后调用，
    /// 因此 `NSWorkspace.icon` 不落在唤出的同步渲染路径上。
    func icon(path: String?) async -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: path as NSString, cost: 128 * 128 * 4)
        return icon
    }
}

private struct SourceAppBadge: View {
    let bundleID: String?
    let name: String

    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 12, height: 12)
            }
            Text(name)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel("来自 \(name)")
        // 来源角标出现在每张卡上：图标异步取，避免同步渲染时批量问 Launch Services。
        .task(id: bundleID) {
            icon = await SourceAppIconCache.shared.icon(bundleID: bundleID)
        }
    }
}

private struct ActionCapsule: View {
    let title: String
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(isFocused ? DS.Colors.accent.opacity(0.16) : .clear, in: Capsule())
        .glassSurface(cornerRadius: 999, interactive: true)
        .overlay {
            if isFocused {
                Capsule().stroke(DS.Colors.selectionRing, lineWidth: 2)
            }
        }
        .animation(.easeInOut(duration: DS.Anim.ringFadeDuration), value: isFocused)
    }
}

private extension SummonPanelFocus {
    var actionIndex: Int? {
        if case let .action(index) = self { return index }
        return nil
    }
}

private struct SummonHintPill: View {
    var body: some View {
        HStack(spacing: 14) {
            hint("←→", "选择")
            if let digitKey = Self.digitHintKey { hint(digitKey, "快速粘贴") }
            hint("⏎", "/ 点击 粘贴")
            hint("⌥⏎", "纯文本粘贴")
            hint("Tab", "分词")
            hint("打字", "搜索")
            hint("esc", "关闭")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .fixedSize()
        .glassSurface(cornerRadius: 999)
    }

    /// 快速粘贴的按键提示，随「数字修饰键」设置变化（默认 ⌘1~9）。
    private static var digitHintKey: String? {
        switch Settings.digitModifier {
        case .none: "1~9"
        case .cmd: "⌘1~9"
        case .opt: "⌥1~9"
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            Text(label)
        }
    }
}

@MainActor
private final class SourceAppIconCache {
    static let shared = SourceAppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private var misses = Set<String>()

    func icon(bundleID: String?) async -> NSImage? {
        guard let bundleID, !bundleID.isEmpty, !misses.contains(bundleID) else { return nil }
        if let cached = cache.object(forKey: bundleID as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            misses.insert(bundleID)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: bundleID as NSString)
        return image
    }
}
