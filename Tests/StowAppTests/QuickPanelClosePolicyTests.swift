import XCTest
@testable import StowApp

final class QuickPanelClosePolicyTests: XCTestCase {
    func testEscapeClosesPresentedLayerBeforeSearchAndPanel() {
        XCTAssertEqual(
            decision(.escape, search: true, criteria: true, layer: .preview),
            .closePresentedLayer
        )
        XCTAssertEqual(
            decision(.escape, search: true, criteria: true, layer: .menu),
            .closePresentedLayer
        )
        XCTAssertEqual(
            decision(.escape, search: true, criteria: true),
            .clearSearch
        )
        XCTAssertEqual(
            decision(.escape, search: true, criteria: false),
            .collapseSearch
        )
        XCTAssertEqual(
            decision(.escape, search: false, criteria: false),
            .closePanel
        )
    }

    func testExplicitAndShortcutCloseSkipDisposableSearchState() {
        for request in [QuickPanelCloseRequest.explicit, .shortcutToggle, .completedUse] {
            XCTAssertEqual(
                decision(request, search: true, criteria: true),
                .closePanel
            )
        }
    }

    func testDirtyEditorRequiresConfirmationForEveryExitKind() {
        XCTAssertEqual(
            decision(.escape, layer: .editor(isDirty: true)),
            .confirmDiscard(.layerOnly)
        )
        XCTAssertEqual(
            decision(.outsideClick, layer: .editor(isDirty: true)),
            .confirmDiscard(.panel(.outsideClick))
        )
        XCTAssertEqual(
            decision(.explicit, layer: .editor(isDirty: true)),
            .confirmDiscard(.panel(.explicit))
        )
        XCTAssertEqual(
            decision(.destination(.settings), layer: .editor(isDirty: true)),
            .confirmDiscard(.panel(.destination(.settings)))
        )
    }

    func testCleanEditorIsLayeredForEscapeButNotExplicitClose() {
        XCTAssertEqual(
            decision(.escape, layer: .editor(isDirty: false)),
            .closePresentedLayer
        )
        XCTAssertEqual(
            decision(.outsideClick, layer: .editor(isDirty: false)),
            .closePresentedLayer
        )
        XCTAssertEqual(
            decision(.explicit, layer: .editor(isDirty: false)),
            .closePanel
        )
    }

    func testOutsideClickDismissesOneTransientLayerAtATime() {
        XCTAssertEqual(
            decision(.outsideClick, layer: .preview),
            .closePresentedLayer
        )
        XCTAssertEqual(
            decision(.outsideClick, layer: .menu),
            .closePresentedLayer
        )
        XCTAssertEqual(
            decision(.outsideClick),
            .closePanel
        )
    }

    func testAppResignationOnlyRequestsCloseDuringPointerInteraction() {
        XCTAssertFalse(QuickPanelOutsideEventPolicy.shouldRequestCloseOnApplicationResign(pointerButtonsArePressed: false))
        XCTAssertTrue(QuickPanelOutsideEventPolicy.shouldRequestCloseOnApplicationResign(pointerButtonsArePressed: true))
    }

    private func decision(
        _ request: QuickPanelCloseRequest,
        search: Bool = false,
        criteria: Bool = false,
        layer: QuickPanelPresentedLayer = .none
    ) -> QuickPanelCloseDecision {
        QuickPanelClosePolicy.decision(
            for: request,
            state: QuickPanelCloseState(
                searchIsActive: search,
                hasSearchCriteria: criteria,
                presentedLayer: layer
            )
        )
    }
}
