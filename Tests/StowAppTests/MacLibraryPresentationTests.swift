import XCTest
import StowCore
@testable import StowApp

final class MacLibraryPresentationTests: XCTestCase {
    func testMacLibraryDestinationsExcludeDuplicateSettingsAndClarifyRecent() {
        XCTAssertEqual(MacLibraryPolicy.sections, [.inbox, .recent, .pinned, .archive, .trash])
        XCTAssertEqual(MacLibraryPolicy.title(for: .recent), "Recently Used")
    }

    func testSidebarCountsIncludeOverlappingCollectionsButExcludeTrashFromRecentAndPinned() {
        let inbox = makeItem(title: "Inbox", isPinned: true)
        let archived = makeItem(title: "Archived", status: .archived, isPinned: true)
        archived.lastUsedAt = .now
        let trashed = makeItem(title: "Trashed", status: .trashed, isPinned: true)
        trashed.lastUsedAt = .now

        let counts = MacLibraryPolicy.counts(for: [inbox, archived, trashed])

        XCTAssertEqual(counts, [.inbox: 1, .recent: 1, .pinned: 2, .archive: 1, .trash: 1])
        XCTAssertFalse(MacLibraryPolicy.includes(trashed, in: .recent))
        XCTAssertFalse(MacLibraryPolicy.includes(trashed, in: .pinned))
        XCTAssertFalse(MacLibraryPolicy.includes(inbox, in: .settings))
    }

    func testSharedSectionPolicyDefinesMembershipForEveryDestination() {
        let inbox = makeItem(title: "Inbox", status: .inbox, isPinned: true)
        inbox.lastUsedAt = Date(timeIntervalSince1970: 300)
        let archived = makeItem(title: "Archived", status: .archived, isPinned: true)
        archived.lastUsedAt = Date(timeIntervalSince1970: 200)
        let trashed = makeItem(title: "Trashed", status: .trashed, isPinned: true)
        trashed.lastUsedAt = Date(timeIntervalSince1970: 100)
        let plainInbox = makeItem(title: "Plain", status: .inbox)
        let items = [inbox, archived, trashed, plainInbox]

        let membership = Dictionary(uniqueKeysWithValues: StowSection.allCases.map { section in
            (section, items.filter(section.includes).map(\.title))
        })

        XCTAssertEqual(membership[.inbox], ["Inbox", "Plain"])
        XCTAssertEqual(membership[.recent], ["Inbox", "Archived"])
        XCTAssertEqual(membership[.pinned], ["Inbox", "Archived"])
        XCTAssertEqual(membership[.archive], ["Archived"])
        XCTAssertEqual(membership[.trash], ["Trashed"])
        XCTAssertEqual(membership[.settings], [])
        XCTAssertEqual(MacLibraryPolicy.includes(inbox, in: .inbox), StowSection.inbox.includes(inbox))
    }

    func testSharedSectionPolicyPreservesDefaultAndRecentOrderingIncludingTies() {
        let old = makeItem(
            title: "Old",
            createdAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: Date(timeIntervalSince1970: 300)
        )
        let new = makeItem(
            title: "New",
            createdAt: Date(timeIntervalSince1970: 200),
            lastUsedAt: Date(timeIntervalSince1970: 200)
        )
        for section in StowSection.allCases where section != .recent {
            XCTAssertEqual(section.sortedItems([old, new]).map(\.title), ["New", "Old"])
        }
        XCTAssertEqual(StowSection.recent.sortedItems([old, new]).map(\.title), ["Old", "New"])

        let firstTie = makeItem(
            title: "First",
            createdAt: Date(timeIntervalSince1970: 400),
            lastUsedAt: Date(timeIntervalSince1970: 500)
        )
        let secondTie = makeItem(
            title: "Second",
            createdAt: Date(timeIntervalSince1970: 400),
            lastUsedAt: Date(timeIntervalSince1970: 500)
        )
        XCTAssertEqual(StowSection.inbox.sortedItems([firstTie, secondTie]).map(\.title), ["First", "Second"])
        XCTAssertEqual(StowSection.recent.sortedItems([firstTie, secondTie]).map(\.title), ["First", "Second"])
    }

    func testSidebarCountsKeepEmptyCollectionsAndFollowLifecycleChanges() {
        XCTAssertEqual(MacLibraryPolicy.counts(for: []), [.inbox: 0, .recent: 0, .pinned: 0, .archive: 0, .trash: 0])
        let item = makeItem(title: "Saved")
        XCTAssertEqual(MacLibraryPolicy.counts(for: [item])[.inbox], 1)

        item.status = .archived
        item.isPinned = true
        item.lastUsedAt = .now

        XCTAssertEqual(MacLibraryPolicy.counts(for: [item]), [.inbox: 0, .recent: 1, .pinned: 1, .archive: 1, .trash: 0])
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
        isPinned: Bool = false,
        createdAt: Date = Date(timeIntervalSince1970: 100),
        lastUsedAt: Date? = nil
    ) -> StowItem {
        StowItem(
            type: .text,
            title: title,
            textContent: text,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            status: status,
            isPinned: isPinned
        )
    }
}
