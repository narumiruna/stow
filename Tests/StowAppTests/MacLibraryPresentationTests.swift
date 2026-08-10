import XCTest
import StowCore
@testable import StowApp

final class MacLibraryPresentationTests: XCTestCase {
    func testMacLibraryDestinationsExcludeDuplicateSettingsAndClarifyRecent() {
        XCTAssertEqual(MacLibraryPolicy.sections, [.inbox, .recent, .pinned, .archive, .trash])
        XCTAssertEqual(MacLibraryPolicy.title(for: .recent), "Recently Used")
    }

    func testFilterSummaryCountsAndNamesEveryActiveCriterion() {
        let summary = MacLibraryFilterSummary(
            type: .code,
            source: "An Extremely Long Source Application Name",
            date: .week
        )

        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.compactLabel, "3 Filters")
        XCTAssertEqual(summary.tokens.map(\.title), ["Code", "An Extremely Long Source Application Name", "Past week"])
    }

    func testFilteredEmptyStateOffersClearFiltersInsteadOfCapture() {
        XCTAssertEqual(
            MacLibraryPolicy.emptyState(section: .inbox, hasSearchText: false, hasFilters: true),
            .noResults
        )
        XCTAssertEqual(
            MacLibraryPolicy.emptyState(section: .inbox, hasSearchText: false, hasFilters: false),
            .emptyInbox
        )
    }

    func testMixedPinSelectionUsesDeterministicPinAllSemantics() {
        let pinned = makeItem(title: "Pinned", isPinned: true)
        let unpinned = makeItem(title: "Unpinned", isPinned: false)

        XCTAssertEqual(MacLibraryPolicy.pinAction(for: [pinned, unpinned]), .pinAll)
        XCTAssertEqual(MacLibraryPolicy.pinAction(for: [pinned]), .unpinAll)
    }

    func testLifecycleActionOnlyAppearsForUniformApplicableSelections() {
        let inbox = makeItem(title: "Inbox", status: .inbox)
        let archived = makeItem(title: "Archived", status: .archived)
        let trashed = makeItem(title: "Trashed", status: .trashed)

        XCTAssertEqual(MacLibraryPolicy.lifecycleAction(for: [inbox]), .archive)
        XCTAssertEqual(MacLibraryPolicy.lifecycleAction(for: [archived]), .restoreToInbox)
        XCTAssertNil(MacLibraryPolicy.lifecycleAction(for: [inbox, archived]))
        XCTAssertNil(MacLibraryPolicy.lifecycleAction(for: [trashed]))
    }

    func testEditDraftTracksDirtyStateWithoutMutatingSavedItem() {
        let item = makeItem(title: "Saved", text: "Original")
        var draft = MacLibraryEditDraft(item: item)

        XCTAssertFalse(draft.isDirty(comparedWith: item))
        draft.title = "Draft"
        draft.text = "Unsaved"

        XCTAssertTrue(draft.isDirty(comparedWith: item))
        XCTAssertEqual(item.title, "Saved")
        XCTAssertEqual(item.textContent, "Original")
    }

    private func makeItem(
        title: String,
        text: String? = nil,
        status: ItemStatus = .inbox,
        isPinned: Bool = false
    ) -> StowItem {
        StowItem(type: .text, title: title, textContent: text, status: status, isPinned: isPinned)
    }
}
