import SwiftUI

@MainActor
struct ChopOverlayView: View {
    private static let coordinateSpace = "chop-token-flow"

    @State private var model: ChopOverlayModel
    @State private var tokenFrames: [Int: CGRect] = [:]
    @State private var dragActive = false
    @State private var shakeTrigger = 0
    @FocusState private var hasKeyboardFocus: Bool

    private let actions: ChopOverlayActions
    private let onClose: () -> Void

    init(
        text: String,
        actions: ChopOverlayActions,
        onClose: @escaping () -> Void
    ) {
        _model = State(initialValue: ChopOverlayModel(text: text))
        self.actions = actions
        self.onClose = onClose
    }

    init(
        model: ChopOverlayModel,
        actions: ChopOverlayActions = .preview,
        onClose: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        self.actions = actions
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            entitySection
            if !model.entities.isEmpty { Divider().overlay(DS.Colors.divider) }
            tokenSection
            Divider().overlay(DS.Colors.divider)
            statusBar
        }
        .padding(18)
        .frame(maxWidth: DS.Metrics.chopOverlayMaxWidth, alignment: .leading)
        .glassSurface(cornerRadius: DS.Metrics.cardCornerRadius)
        .modifier(ShakeEffect(animatableData: CGFloat(shakeTrigger)))
        .animation(
            MotionPolicy.animation(.linear(duration: 0.28), reducedDuration: 0.08),
            value: shakeTrigger
        )
        .transition(MotionPolicy.overlayTransition)
        .focusable()
        .focused($hasKeyboardFocus)
        .onAppear { hasKeyboardFocus = true }
        .onKeyPress(phases: .down, action: handleKeyPress)
        .task { await model.load() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("分词")
    }

    @ViewBuilder
    private var entitySection: some View {
        if !model.entities.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("智能识别 · 按数字键直接复制")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Colors.secondaryText)

                TokenFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(model.entities.enumerated()), id: \.element.id) { index, entity in
                        Button {
                            apply(model.perform(.entity(number: index + 1)))
                        } label: {
                            EntityChip(entity: entity, number: index + 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(index + 1)，\(entity.typeLabel)，\(entity.value)")
                    }
                }
            }
        }
    }

    private var tokenSection: some View {
        Group {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                TokenFlowLayout {
                    ForEach(Array(model.tokens.enumerated()), id: \.element.id) { index, token in
                        TokenChip(token: token, isSelected: model.isSelected(token))
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: TokenFramePreferenceKey.self,
                                        value: [index: proxy.frame(in: .named(Self.coordinateSpace))]
                                    )
                                }
                            }
                            .accessibilityAction {
                                model.toggleToken(at: index)
                            }
                    }
                }
                .coordinateSpace(name: Self.coordinateSpace)
                .contentShape(Rectangle())
                .onPreferenceChange(TokenFramePreferenceKey.self) { tokenFrames = $0 }
                .gesture(selectionGesture)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                guard let index = tokenIndex(at: value.location) else { return }
                if dragActive {
                    model.updateDrag(to: index)
                } else {
                    dragActive = true
                    model.beginDrag(at: index)
                }
            }
            .onEnded { _ in
                model.endDrag()
                dragActive = false
            }
    }

    private var statusBar: some View {
        HStack(spacing: 0) {
            Text("已选 \(model.selectedCount) 词 · 点按选词 · 按住划选一段 · ⏎ 复制所选 · ⇧⏎ 复制并粘贴 · esc 返回")
                .font(.caption2)
                .foregroundStyle(DS.Colors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            Button("返回") { onClose() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(DS.Colors.secondaryText)
        }
    }

    private func tokenIndex(at point: CGPoint) -> Int? {
        tokenFrames
            .filter { $0.value.insetBy(dx: -2, dy: -2).contains(point) }
            .map(\.key)
            .min()
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let command: ChopOverlayCommand?

        if keyPress.key == .escape {
            command = .close
        } else if keyPress.key == .return {
            command = keyPress.modifiers.contains(.shift) ? .pasteSelection : .copySelection
        } else if keyPress.key == "a", keyPress.modifiers.contains(.command) {
            command = .selectAll
        } else if keyPress.modifiers.intersection([.command, .control, .option]).isEmpty,
                  let number = Int(keyPress.characters),
                  (1...9).contains(number) {
            command = .entity(number: number)
        } else {
            command = nil
        }

        guard let command else { return .ignored }
        apply(model.perform(command))
        return .handled
    }

    private func apply(_ effect: ChopOverlayEffect) {
        switch effect {
        case .none:
            break
        case .shake:
            shakeTrigger += 1
        case let .copy(text, toast):
            actions.copyText(text)
            if let toast { actions.showToast(toast) }
            onClose()
        case let .paste(text):
            // PasteService must run after the panel has yielded focus back to
            // the originating app (01 §3.5).
            onClose()
            actions.pasteText(text)
        case .close:
            onClose()
        }
    }
}

@MainActor
private struct ShakeEffect: GeometryEffect {
    nonisolated var animatableData: CGFloat

    nonisolated func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = 5 * sin(animatableData * .pi * 6)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

@MainActor
private struct EntityChip: View {
    let entity: DetectedEntity
    let number: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(DS.Typography.badge)
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(DS.Colors.accent, in: Circle())
            Image(systemName: entity.icon)
                .font(.caption)
                .foregroundStyle(DS.Colors.accent)
            Text(entity.value)
                .font(DS.Typography.entityValue)
                .lineLimit(1)
            Text(entity.typeLabel)
                .font(.caption2)
                .foregroundStyle(DS.Colors.secondaryText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .glassSurface(cornerRadius: DS.Metrics.chipCornerRadius, interactive: true)
    }
}

@MainActor
private struct TokenChip: View {
    let token: ChopToken
    let isSelected: Bool

    var body: some View {
        Text(token.text)
            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DS.Metrics.chipCornerRadius, style: .continuous)
                        .fill(DS.Colors.accent)
                }
            }
            .glassSurface(
                cornerRadius: DS.Metrics.chipCornerRadius,
                tint: isSelected ? DS.Colors.accent.opacity(0.28) : nil,
                interactive: true
            )
            .opacity(token.isPunctuation && !isSelected ? 0.38 : 1)
            .contentShape(RoundedRectangle(cornerRadius: DS.Metrics.chipCornerRadius))
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TokenFramePreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
