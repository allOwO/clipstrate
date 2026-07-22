import AppKit
import SwiftUI

/// 唤出面板内容（01 §3.2 变体 C）：无外层容器、独立玻璃卡片、底边对齐。
/// 卡片视觉、两层焦点与三类内容渲染集中在此；搜索态由 T1.9 继续扩展。
struct SummonPanelView: View {
    @ObservedObject var model: SummonPanelModel

    var body: some View {
        ZStack {
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

    private var cardLayer: some View {
        VStack(spacing: DS.Metrics.hintPillGap) {
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
                                .id(cardID(item))
                            }
                        }
                        .frame(minWidth: 0, minHeight: DS.Metrics.cardSelected.height, alignment: .bottomLeading)
                        .padding(.horizontal, SummonPanelLayout.shadowPadding)
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.selectedIndex) { _, index in
                    guard model.items.indices.contains(index) else { return }
                    withAnimation(MotionPolicy.animation(DS.Anim.cardGrow)) {
                        proxy.scrollTo(cardID(model.items[index]), anchor: .center)
                    }
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
        .glassSurface(
            cornerRadius: DS.Metrics.cardCornerRadius,
            tint: isSelected ? DS.Colors.selectedCardTint : nil,
            interactive: true
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: DS.Metrics.cardCornerRadius, style: .continuous)
                    .stroke(DS.Colors.selectionRing, lineWidth: DS.Metrics.selectionRingWidth)
                    .opacity(isActionLayer ? DS.Metrics.actionLayerRingOpacity : 1)
            }
        }
        .shadow(
            color: .black.opacity(isSelected ? 0.30 : 0.18),
            radius: isSelected ? 28 : 18,
            y: isSelected ? 18 : 10
        )
        .animation(MotionPolicy.animation(DS.Anim.cardGrow), value: isSelected)
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
        let full = Animation.spring(response: 0.45, dampingFraction: 0.80)
            .delay(Double(index) * DS.Anim.entranceStagger)
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
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.Colors.placeholderFill)
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: presentation.symbolName)
                        .font(.system(size: isSelected ? 38 : 30, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
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
            hint("↓", "动作")
            hint("⏎", "/ 点击选中卡 粘贴")
            hint("⌥⏎", "纯文本粘贴")
            hint("Tab", "分词")
            hint("esc", "关闭")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .fixedSize()
        .glassSurface(cornerRadius: 999)
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
