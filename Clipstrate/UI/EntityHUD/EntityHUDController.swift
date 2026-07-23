import AppKit
import SwiftUI

@MainActor
final class EntityHUDController {
    private let model: EntityHUDModel
    private lazy var panel = makePanel()

    init(
        dismissDelay: Duration = .milliseconds(2_500),
        onExpand: @escaping (EntityHUDPayload) -> Void
    ) {
        model = EntityHUDModel(dismissDelay: dismissDelay)
        model.onPresent = { [weak self] in self?.presentPanel() }
        model.onDismiss = { [weak self] in self?.panel.orderOut(nil) }
        model.onExpand = onExpand
    }

    func show(item: ClipItem, entities: [DetectedEntity]) {
        model.present(item: item, entities: entities)
    }

    func dismiss() {
        model.dismiss()
    }

    /// Bind `HotkeyCenter.setChopHandler` to this method. A true result means
    /// the visible HUD consumed ⌥X and requested the overlay.
    @discardableResult
    func expandIfVisible() -> Bool {
        model.expandIfPresent()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let hostingView = NSHostingView(rootView: EntityHUDView(model: model))
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView
        return panel
    }

    private func presentPanel() {
        let hostingView = panel.contentView
        hostingView?.layoutSubtreeIfNeeded()
        let size = hostingView?.fittingSize ?? CGSize(width: 220, height: 44)
        panel.setContentSize(size)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let origin = CGPoint(
            x: visibleFrame.maxX - size.width - 18,
            y: visibleFrame.maxY - size.height - 18
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }
}
