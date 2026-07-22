import AppKit
import SwiftUI

/// 唤出面板内容（01 §3.2 变体 C）：无外层容器、独立玻璃卡片、底边对齐。
/// 键盘/鼠标焦点行为由 T1.4 接入；图片缩略图、文件图标与富文本渲染由 T1.6 替换占位内容。
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
                                presentationEpoch: model.presentationEpoch,
                                isPanelPresented: model.isPanelPresented,
                                onChop: { model.presentChopOverlay(for: item) }
                            )
                            .id("\(item.contentHash)-\(model.presentationEpoch)")
                        }
                    }
                    .frame(minWidth: 0, minHeight: DS.Metrics.cardSelected.height, alignment: .bottomLeading)
                    .padding(.horizontal, SummonPanelLayout.shadowPadding)
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: DS.Metrics.cardSelected.height + SummonPanelLayout.shadowPadding * 2)

            SummonHintPill()
        }
        .padding(.vertical, SummonPanelLayout.verticalPadding)
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
    let presentationEpoch: Int
    let isPanelPresented: Bool
    let onChop: () -> Void

    @State private var isEntered = false

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
        .scaleEffect(entranceScale, anchor: .bottom)
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
            Text(presentation.body)
                .font(isSelected ? DS.Typography.cardBody : DS.Typography.cardBodyCompact)
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(isSelected ? 6 : 4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .image, .file:
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.Colors.placeholderFill)
                    Image(systemName: presentation.symbolName)
                        .font(.system(size: isSelected ? 38 : 30, weight: .light))
                        .foregroundStyle(.secondary)
                }
                Text(presentation.body)
                    .font(DS.Typography.cardMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            ActionCapsule(title: "纯文本") {}
            ActionCapsule(title: "✂︎ 分词", action: onChop)
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

private struct SourceAppBadge: View {
    let bundleID: String?
    let name: String

    var body: some View {
        HStack(spacing: 3) {
            if let image = SourceAppIconCache.shared.icon(bundleID: bundleID) {
                Image(nsImage: image)
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
    }
}

private struct ActionCapsule: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: 999, interactive: true)
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

    func icon(bundleID: String?) -> NSImage? {
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
