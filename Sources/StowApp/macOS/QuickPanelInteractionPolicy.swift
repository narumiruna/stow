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
              characters.unicodeScalars.allSatisfy({ isTypedTextScalar($0) }) else {
            return .ignored
        }
        return .beginSearch(initialText: characters)
    }

    /// AppKit reports arrow, function, and navigation keys as scalars in
    /// U+F700–U+F8FF (for example, NSLeftArrowFunctionKey is U+F702).
    private static let functionKeyScalars: ClosedRange<UInt32> = 0xF700...0xF8FF

    private static func isTypedTextScalar(_ scalar: Unicode.Scalar) -> Bool {
        !CharacterSet.controlCharacters.contains(scalar)
            && !functionKeyScalars.contains(scalar.value)
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
}
