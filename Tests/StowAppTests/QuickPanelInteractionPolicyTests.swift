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

    func testShiftArrowExtendsFromAnchorAndShrinksWhenMovingBack() {
        let ids = (0..<5).map { _ in UUID() }
        var state = QuickPanelSelectionState(selection: ids[1], selectedIDs: [ids[1]], selectionAnchor: ids[1])
        state = QuickPanelSelectionPolicy.extend(state, to: ids[2], visibleIDs: ids)
        state = QuickPanelSelectionPolicy.extend(state, to: ids[3], visibleIDs: ids)
        XCTAssertEqual(state, QuickPanelSelectionState(selection: ids[3], selectedIDs: Set(ids[1...3]), selectionAnchor: ids[1]))
        state = QuickPanelSelectionPolicy.extend(state, to: ids[2], visibleIDs: ids)
        XCTAssertEqual(state.selectedIDs, Set(ids[1...2]))
        state = QuickPanelSelectionPolicy.extend(state, to: ids[1], visibleIDs: ids)
        XCTAssertEqual(state.selectedIDs, [ids[1]])
        state = QuickPanelSelectionPolicy.extend(state, to: ids[0], visibleIDs: ids)
        XCTAssertEqual(state, QuickPanelSelectionState(selection: ids[0], selectedIDs: Set(ids[0...1]), selectionAnchor: ids[1]))
    }

    func testPlainArrowResetSelectsOnlyTheFocusAndStartsANewRange() {
        let ids = (0..<5).map { _ in UUID() }
        var state = QuickPanelSelectionState(selection: ids[1], selectedIDs: [ids[1]], selectionAnchor: ids[1])
        state = QuickPanelSelectionPolicy.extend(state, to: ids[3], visibleIDs: ids)
        XCTAssertEqual(state.selectedIDs, Set(ids[1...3]))

        state = QuickPanelSelectionPolicy.reset(to: ids[4])
        XCTAssertEqual(state, QuickPanelSelectionState(selection: ids[4], selectedIDs: [ids[4]], selectionAnchor: ids[4]))

        state = QuickPanelSelectionPolicy.extend(state, to: ids[3], visibleIDs: ids)
        XCTAssertEqual(state, QuickPanelSelectionState(selection: ids[3], selectedIDs: Set(ids[3...4]), selectionAnchor: ids[4]))
    }

    func testExtendUsesTheFocusWhenTheAnchorIsMissingOrHidden() {
        let ids = (0..<4).map { _ in UUID() }
        let noAnchor = QuickPanelSelectionState(selection: ids[2], selectedIDs: [ids[2]], selectionAnchor: nil)
        XCTAssertEqual(
            QuickPanelSelectionPolicy.extend(noAnchor, to: ids[3], visibleIDs: ids),
            QuickPanelSelectionState(selection: ids[3], selectedIDs: Set(ids[2...3]), selectionAnchor: ids[2])
        )
        let hiddenAnchor = QuickPanelSelectionState(selection: ids[1], selectedIDs: [ids[1]], selectionAnchor: UUID())
        XCTAssertEqual(QuickPanelSelectionPolicy.extend(hiddenAnchor, to: ids[0], visibleIDs: ids).selectedIDs, Set(ids[0...1]))
        let unchanged = QuickPanelSelectionPolicy.extend(noAnchor, to: UUID(), visibleIDs: ids)
        XCTAssertEqual(unchanged, noAnchor)
    }

    func testMultipleSelectionKeepsTimelineOrderAndNeedsTwoVisibleItems() {
        struct Card: Identifiable, Equatable { let id = UUID() }
        let cards = (0..<4).map { _ in Card() }
        XCTAssertEqual(
            QuickPanelSelectionPolicy.multipleSelection(in: cards, selectedIDs: [cards[3].id, cards[0].id, cards[2].id]),
            [cards[0], cards[2], cards[3]]
        )
        XCTAssertNil(QuickPanelSelectionPolicy.multipleSelection(in: cards, selectedIDs: [cards[1].id]))
        XCTAssertNil(QuickPanelSelectionPolicy.multipleSelection(in: cards, selectedIDs: [cards[1].id, UUID()]))
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
