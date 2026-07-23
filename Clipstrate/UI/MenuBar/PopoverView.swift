import SwiftUI

/// Popover 主界面（01 §5）：头部 App 名 + 常驻搜索框；中部横向卡片流（懒加载分页）；
/// 底部统计 + 设置/关于。玻璃自绘、无箭头（02 §6）。点击条目 = 复制到剪贴板顶部。
struct PopoverView: View {
    @ObservedObject var model: PopoverModel
    let blobStore: BlobStore?
    var onSettings: () -> Void = {}
    var onAbout: () -> Void = {}

    static let width: CGFloat = 620
    static let height: CGFloat = 300

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            cardFlow
            Divider()
            footer
        }
        .frame(width: Self.width, height: Self.height)
        .glassSurface(cornerRadius: 18)
        .task {
            await model.reload()
            searchFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Clipstrate").font(.headline)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("搜索", text: $model.query)
                    .textFieldStyle(.plain)
                    .frame(width: 220)
                    .focused($searchFocused)
                    .onChange(of: model.query) { _, _ in model.queryDidChange() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.06), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var cardFlow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: DS.Metrics.cardSpacing) {
                ForEach(Array(model.items.enumerated()), id: \.element.contentHash) { index, item in
                    PopoverCard(item: item, blobStore: blobStore)
                        .onTapGesture { model.copy(item) }
                        .onAppear {
                            if index >= model.items.count - 3 {
                                Task { await model.loadNextPage() }
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if model.items.isEmpty {
                Text(model.query.isEmpty ? "暂无历史" : "无匹配")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("共 \(model.totalCount) 条 · \(byteText)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            FooterButton(title: "设置", systemImage: "gearshape", action: onSettings)
            FooterButton(title: "关于", systemImage: "info.circle", action: onAbout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var byteText: String {
        ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file)
    }
}

/// 底部工具按钮：图标与文字贴近成一体，整块（含内边距）可点击；
/// 悬停时给淡灰圆角高亮，贴近 macOS 原生条目观感。
private struct FooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.10 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct PopoverCard: View {
    let item: ClipItem
    let blobStore: BlobStore?

    @State private var thumbnail: CGImage?

    private var presentation: ClipCardPresentation { ClipCardPresentation(item: item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.typeLabel)
                .font(DS.Typography.cardTypeLabel)
                .foregroundStyle(.secondary)
            content
            Spacer(minLength: 0)
            if let source = presentation.sourceName {
                Text(source)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(width: 150, height: 150, alignment: .topLeading)
        .glassSurface(cornerRadius: DS.Metrics.cardCornerRadius)
        .contentShape(Rectangle())
        .task(id: item.thumbPath) {
            guard item.kind == .image, let name = item.thumbPath, let blobStore else { return }
            thumbnail = await CardAssetLoader.shared.thumbnail(named: name, store: blobStore)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            Text(presentation.body)
                .font(DS.Typography.cardBody)
                .lineLimit(4)
        case .image:
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 88)
            } else {
                Image(systemName: presentation.symbolName)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
            }
        case .file:
            Text(presentation.body)
                .font(DS.Typography.cardBody)
                .lineLimit(3)
        }
    }
}
