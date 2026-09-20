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

final class EditorTransitionModelTests: XCTestCase {
    func testFailedSaveKeepsDraftDirtyAndRequiresDiscardBeforeExit() {
        var model = EditorTransitionModel()
        model.updateDirty(true)
        model.beginSave(then: .finishEditing)

        XCTAssertNil(model.finishSave(errorMessage: "Save failed"))
        XCTAssertEqual(model.phase, .saveFailed("Save failed"))
        XCTAssertEqual(model.errorMessage, "Save failed")
        XCTAssertTrue(model.hasUnsavedChanges)

        XCTAssertNil(model.request(.finishEditing))
        XCTAssertEqual(model.phase, .discardConfirmation)
    }

    func testSuccessfulSaveCompletesRequestedTransition() {
        var model = EditorTransitionModel()
        model.updateDirty(true)
        model.beginSave(then: .finishEditing)

        XCTAssertEqual(model.finishSave(errorMessage: nil), .finishEditing)
        XCTAssertEqual(model.phase, .clean)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testEditToRenameRequiresConfirmationAndConfirmedDiscardChangesMode() {
        let itemID = UUID()
        var model = EditorTransitionModel()
        model.updateDirty(true)

        XCTAssertNil(model.request(.popover(itemID: itemID, mode: .rename)))
        XCTAssertEqual(model.phase, .discardConfirmation)
        XCTAssertEqual(
            model.confirmDiscard(),
            .popover(itemID: itemID, mode: .rename)
        )
        XCTAssertEqual(model.phase, .clean)
    }

    func testRenameToPreviewCanKeepEditing() {
        let itemID = UUID()
        var model = EditorTransitionModel()
        model.updateDirty(true)

        XCTAssertNil(model.request(.popover(itemID: itemID, mode: .preview)))
        model.keepEditing()

        XCTAssertEqual(model.phase, .dirty)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertNil(model.confirmDiscard())
    }

    func testSelectionChangeRequiresConfirmationWhenDirty() {
        let itemID = UUID()
        var model = EditorTransitionModel()
        model.updateDirty(true)

        XCTAssertNil(model.request(.selection(itemID: itemID)))
        XCTAssertEqual(model.confirmDiscard(), .selection(itemID: itemID))
    }

    func testEscapeDismissesCleanEditorButConfirmsDirtyEditor() {
        var clean = EditorTransitionModel()
        XCTAssertEqual(clean.request(.dismissEditor), .dismissEditor)

        var dirty = EditorTransitionModel()
        dirty.updateDirty(true)
        XCTAssertNil(dirty.request(.dismissEditor))
        XCTAssertEqual(dirty.phase, .discardConfirmation)
    }

    func testDestinationCloseRequiresConfirmationWhenDirty() {
        var model = EditorTransitionModel()
        model.updateDirty(true)

        XCTAssertNil(model.request(.panelExit))
        XCTAssertEqual(model.phase, .discardConfirmation)
        XCTAssertEqual(model.confirmDiscard(), .panelExit)
    }
}
