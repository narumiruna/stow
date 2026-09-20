import Foundation

enum EditorMode: Equatable {
    case preview
    case edit
    case rename
}

enum EditorTransitionDestination: Equatable {
    case finishEditing
    case dismissEditor
    case popover(itemID: UUID, mode: EditorMode)
    case selection(itemID: UUID)
    case panelExit
}

struct EditorTransitionModel: Equatable {
    enum Phase: Equatable {
        case clean
        case dirty
        case saving
        case saveFailed(String)
        case discardConfirmation
    }

    private(set) var phase: Phase = .clean
    private var phaseBeforeConfirmation: Phase?
    private var pendingDestination: EditorTransitionDestination?

    var hasUnsavedChanges: Bool {
        switch phase {
        case .dirty, .saveFailed, .discardConfirmation:
            true
        case .clean, .saving:
            false
        }
    }

    var errorMessage: String? {
        guard case .saveFailed(let message) = phase else { return nil }
        return message
    }

    mutating func updateDirty(_ isDirty: Bool) {
        switch phase {
        case .saving, .discardConfirmation:
            return
        case .saveFailed where isDirty:
            return
        case .clean, .dirty, .saveFailed:
            phase = isDirty ? .dirty : .clean
        }
    }

    mutating func beginSave(then destination: EditorTransitionDestination) {
        guard phase != .saving, phase != .discardConfirmation else { return }
        pendingDestination = destination
        phaseBeforeConfirmation = nil
        phase = .saving
    }

    mutating func finishSave(errorMessage: String?) -> EditorTransitionDestination? {
        guard phase == .saving else { return nil }
        if let errorMessage {
            phase = .saveFailed(errorMessage)
            pendingDestination = nil
            return nil
        }
        let destination = pendingDestination
        reset()
        return destination
    }

    mutating func request(_ destination: EditorTransitionDestination) -> EditorTransitionDestination? {
        switch phase {
        case .clean:
            return destination
        case .dirty, .saveFailed:
            phaseBeforeConfirmation = phase
            pendingDestination = destination
            phase = .discardConfirmation
            return nil
        case .saving, .discardConfirmation:
            return nil
        }
    }

    mutating func confirmDiscard() -> EditorTransitionDestination? {
        guard phase == .discardConfirmation else { return nil }
        let destination = pendingDestination
        reset()
        return destination
    }

    mutating func keepEditing() {
        guard phase == .discardConfirmation else { return }
        phase = phaseBeforeConfirmation ?? .dirty
        phaseBeforeConfirmation = nil
        pendingDestination = nil
    }

    mutating func dismissFailure() {
        if case .saveFailed = phase { phase = .dirty }
    }

    mutating func reset() {
        phase = .clean
        phaseBeforeConfirmation = nil
        pendingDestination = nil
    }
}
