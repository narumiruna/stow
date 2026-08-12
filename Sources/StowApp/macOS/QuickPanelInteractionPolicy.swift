import Foundation

struct QuickPanelInputModifiers: OptionSet, Sendable {
    let rawValue: Int

    static let command = Self(rawValue: 1 << 0)
    static let control = Self(rawValue: 1 << 1)
    static let option = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
}

enum QuickPanelInputDecision: Equatable {
    case beginSearch(initialText: String)
    case ignored
}

enum QuickPanelInputPolicy {
    static func decision(
        characters: String,
        modifiers: QuickPanelInputModifiers
    ) -> QuickPanelInputDecision {
        guard modifiers.intersection([.command, .control, .option]).isEmpty,
              characters.count == 1,
              characters != " ",
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return .ignored
        }
        return .beginSearch(initialText: characters)
    }
}

struct QuickPanelSelectionState: Equatable {
    var selection: UUID?
    var selectedIDs: Set<UUID>
    var selectionAnchor: UUID?
}

enum QuickPanelSelectionPolicy {
    static func repair(
        _ state: QuickPanelSelectionState,
        visibleIDs: [UUID]
    ) -> QuickPanelSelectionState {
        guard !visibleIDs.isEmpty else {
            return QuickPanelSelectionState(selection: nil, selectedIDs: [], selectionAnchor: nil)
        }

        let visibleIDSet = Set(visibleIDs)
        var selectedIDs = state.selectedIDs.intersection(visibleIDSet)
        if let selection = state.selection, visibleIDSet.contains(selection) {
            selectedIDs.insert(selection)
            let selectionAnchor = state.selectionAnchor.flatMap { anchor in
                visibleIDSet.contains(anchor) ? anchor : nil
            } ?? selection
            return QuickPanelSelectionState(
                selection: selection,
                selectedIDs: selectedIDs,
                selectionAnchor: selectionAnchor
            )
        }

        let selection = visibleIDs[0]
        return QuickPanelSelectionState(
            selection: selection,
            selectedIDs: [selection],
            selectionAnchor: selection
        )
    }

    static func actionableSelection(
        in state: QuickPanelSelectionState,
        visibleIDs: [UUID]
    ) -> UUID? {
        guard let selection = state.selection, visibleIDs.contains(selection) else { return nil }
        return selection
    }
}
