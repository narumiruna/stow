import Foundation

/// Keeps close-only work separate from work needed when a close is canceled.
@MainActor
final class QuickPanelCloseQueue {
    struct PendingClose {
        let command: QuickPanelCloseCommand
        let returnFocus: Bool
        let afterClose: (() -> Void)?
        let onCancel: (() -> Void)?
    }

    private(set) var pending: PendingClose?

    /// Queues one close, or runs cancellation work if the close cannot be queued.
    func enqueue(
        _ request: QuickPanelCloseRequest,
        isVisible: Bool,
        returnFocus: Bool,
        afterClose: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) -> QuickPanelCloseCommand? {
        guard isVisible, pending == nil else {
            onCancel?()
            return nil
        }
        let command = QuickPanelCloseCommand(id: UUID(), request: request)
        pending = PendingClose(command: command, returnFocus: returnFocus, afterClose: afterClose, onCancel: onCancel)
        return command
    }

    /// Removes the matching close before its callbacks run.
    func take(commandID: UUID) -> PendingClose? {
        guard let pending, pending.command.id == commandID else { return nil }
        self.pending = nil
        return pending
    }

    func cancel(commandID: UUID) {
        take(commandID: commandID)?.onCancel?()
    }

    /// Cancels pending work when the panel is dismissed without approval.
    func cancel() {
        guard let pending else { return }
        cancel(commandID: pending.command.id)
    }
}
