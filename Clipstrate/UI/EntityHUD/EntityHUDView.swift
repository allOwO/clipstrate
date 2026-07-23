import SwiftUI

@MainActor
struct EntityHUDView: View {
    @Bindable var model: EntityHUDModel

    var body: some View {
        if let payload = model.payload {
            Button {
                model.expandIfPresent()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: payload.entities.first?.icon ?? "scissors")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                        .frame(width: 22, height: 22)

                    Text("\(payload.entities.count) 个实体 · ⌥X 拆词")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(DS.Colors.secondaryText)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassSurface(cornerRadius: 22, interactive: true)
            .fixedSize()
            .accessibilityLabel("发现 \(payload.entities.count) 个实体，拆词")
        }
    }
}
