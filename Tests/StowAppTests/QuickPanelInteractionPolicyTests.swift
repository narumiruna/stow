import XCTest
@testable import StowApp

final class QuickPanelInteractionPolicyTests: XCTestCase {
    func testPrintableCharacterBeginsSearchWithoutLosingFirstCharacter() {
        XCTAssertEqual(
            QuickPanelInputPolicy.decision(characters: "P", modifiers: []),
            .beginSearch(initialText: "P")
        )
        XCTAssertEqual(
            QuickPanelInputPolicy.decision(characters: "É", modifiers: [.shift]),
            .beginSearch(initialText: "É")
        )
    }

    func testCommandControlAndOptionModifiedCharactersDoNotBeginSearch() {
        for modifiers: QuickPanelInputModifiers in [.command, .control, .option, [.command, .shift]] {
            XCTAssertEqual(
                QuickPanelInputPolicy.decision(characters: "f", modifiers: modifiers),
                .ignored
            )
        }
    }

    func testSpaceAndReturnRemainPanelCommands() {
        XCTAssertEqual(QuickPanelInputPolicy.decision(characters: " ", modifiers: []), .ignored)
        XCTAssertEqual(QuickPanelInputPolicy.decision(characters: "\r", modifiers: []), .ignored)
    }

    func testArrowAndFunctionKeysDoNotBeginSearch() {
        // NSUpArrowFunctionKey...NSRightArrowFunctionKey, NSF1FunctionKey, NSHomeFunctionKey
        for scalar: UInt32 in [0xF700, 0xF701, 0xF702, 0xF703, 0xF704, 0xF729] {
            let characters = String(Character(Unicode.Scalar(scalar)!))
            XCTAssertEqual(QuickPanelInputPolicy.decision(characters: characters, modifiers: []), .ignored)
            XCTAssertEqual(QuickPanelInputPolicy.decision(characters: characters, modifiers: [.shift]), .ignored)
        }
    }

    func testRepairSelectsFirstVisibleItemWhenPreviousSelectionIsStale() {
        let stale = UUID()
        let first = UUID()
        let second = UUID()
        let state = QuickPanelSelectionState(
            selection: stale,
            selectedIDs: [stale],
            selectionAnchor: stale
        )

        let repaired = QuickPanelSelectionPolicy.repair(state, visibleIDs: [first, second])

        XCTAssertEqual(repaired.selection, first)
        XCTAssertEqual(repaired.selectedIDs, [first])
        XCTAssertEqual(repaired.selectionAnchor, first)
    }

    func testRepairRetainsASelectionThatSurvivesTheCurrentResults() {
        let first = UUID()
        let selected = UUID()
        let removed = UUID()
        let state = QuickPanelSelectionState(
            selection: selected,
            selectedIDs: [selected, removed],
            selectionAnchor: selected
        )

        let repaired = QuickPanelSelectionPolicy.repair(state, visibleIDs: [first, selected])

        XCTAssertEqual(repaired.selection, selected)
        XCTAssertEqual(repaired.selectedIDs, [selected])
        XCTAssertEqual(repaired.selectionAnchor, selected)
    }

    func testZeroResultsClearEverySelection() {
        let stale = UUID()
        let state = QuickPanelSelectionState(
            selection: stale,
            selectedIDs: [stale],
            selectionAnchor: stale
        )

        let repaired = QuickPanelSelectionPolicy.repair(state, visibleIDs: [])

        XCTAssertNil(repaired.selection)
        XCTAssertTrue(repaired.selectedIDs.isEmpty)
        XCTAssertNil(repaired.selectionAnchor)
    }
}
