import Foundation

enum QuickPanelDestination: Equatable {
    case quickAdd
    case library
    case settings
}

enum QuickPanelCloseRequest: Equatable {
    case escape
    case explicit
    case shortcutToggle
    case outsideClick
    case completedUse
    case destination(QuickPanelDestination)
}

struct QuickPanelCloseCommand: Identifiable, Equatable {
    let id: UUID
    let request: QuickPanelCloseRequest
}

enum QuickPanelPresentedLayer: Equatable {
    case none
    case menu
    case preview
    case editor(isDirty: Bool)
}

struct QuickPanelCloseState: Equatable {
    var searchIsActive: Bool
    var hasSearchCriteria: Bool
    var presentedLayer: QuickPanelPresentedLayer
}

enum QuickPanelDiscardScope: Equatable {
    case layerOnly
    case panel(QuickPanelCloseRequest)
}

enum QuickPanelCloseDecision: Equatable {
    case closePanel
    case closePresentedLayer
    case clearSearch
    case collapseSearch
    case confirmDiscard(QuickPanelDiscardScope)
}

enum QuickPanelClosePolicy {
    static func decision(for request: QuickPanelCloseRequest, state: QuickPanelCloseState) -> QuickPanelCloseDecision {
        switch request {
        case .escape:
            switch state.presentedLayer {
            case .none:
                break
            case .menu, .preview:
                return .closePresentedLayer
            case .editor(let isDirty):
                return isDirty ? .confirmDiscard(.layerOnly) : .closePresentedLayer
            }

            if state.hasSearchCriteria { return .clearSearch }
            if state.searchIsActive { return .collapseSearch }
            return .closePanel

        case .outsideClick:
            switch state.presentedLayer {
            case .none:
                return .closePanel
            case .menu, .preview:
                return .closePresentedLayer
            case .editor(let isDirty):
                return isDirty ? .confirmDiscard(.panel(request)) : .closePresentedLayer
            }

        case .explicit, .shortcutToggle, .completedUse, .destination:
            if case .editor(isDirty: true) = state.presentedLayer {
                return .confirmDiscard(.panel(request))
            }
            return .closePanel
        }
    }
}
