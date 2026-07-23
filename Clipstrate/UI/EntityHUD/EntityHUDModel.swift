import Foundation
import Observation

struct EntityHUDPayload: Equatable, Sendable {
    let item: ClipItem
    let entities: [DetectedEntity]

    var text: String { item.plainText ?? "" }
}

@MainActor
@Observable
final class EntityHUDModel {
    private(set) var payload: EntityHUDPayload?

    @ObservationIgnored var onPresent: () -> Void = {}
    @ObservationIgnored var onDismiss: () -> Void = {}
    @ObservationIgnored var onExpand: (EntityHUDPayload) -> Void = { _ in }

    @ObservationIgnored private let dismissDelay: Duration
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var presentationID: UUID?

    init(dismissDelay: Duration = .milliseconds(2_500)) {
        self.dismissDelay = dismissDelay
    }

    deinit {
        dismissTask?.cancel()
    }

    func present(item: ClipItem, entities: [DetectedEntity]) {
        guard let text = item.plainText, !text.isEmpty, !entities.isEmpty else {
            dismiss()
            return
        }

        dismissTask?.cancel()
        let id = UUID()
        presentationID = id
        payload = EntityHUDPayload(item: item, entities: entities)
        onPresent()

        let delay = dismissDelay
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.expirePresentation(id: id)
        }
    }

    func dismiss() {
        let task = dismissTask
        dismissTask = nil
        presentationID = nil
        task?.cancel()
        clearPayload()
    }

    private func expirePresentation(id: UUID) {
        guard presentationID == id else { return }
        // This path is running inside dismissTask, so it must not cancel the
        // current task while that task is unwinding.
        dismissTask = nil
        presentationID = nil
        clearPayload()
    }

    private func clearPayload() {
        guard payload != nil else { return }
        payload = nil
        onDismiss()
    }

    @discardableResult
    func expandIfPresent() -> Bool {
        guard let payload else { return false }
        dismiss()
        onExpand(payload)
        return true
    }
}
