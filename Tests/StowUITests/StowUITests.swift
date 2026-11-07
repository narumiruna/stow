import Foundation
import notify
import XCTest

@MainActor
final class StowUITests: XCTestCase {
    // Reuse only this test's dedicated Simulator preferences domain on relaunch.
    private var preferencesID = UUID()
    private let galleryTitles = [
        "A quiet morning in Kyoto",
        "A simpler way to organize ideas",
        "Designing for a calmer digital life",
        "A weekend in the mountains",
        "Three ideas for a slower week",
        "Places to revisit"
    ]

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        XCUIApplication(bundleIdentifier: "com.apple.mobilesafari").terminate()
        try await super.tearDown()
    }

    func testInProcessLaunchReadinessIsReported() {
        let app = launchApp()
        revealSections(in: app)
        app.buttons["Settings"].tap()
        let readiness = app.descendants(matching: .any)["launch-readiness"]
        XCTAssertTrue(readiness.waitForExistence(timeout: 3))
        let value = readiness.value as? String ?? ""
        let rendered = value.isEmpty ? readiness.label : value
        let milliseconds = rendered.split(whereSeparator: { !$0.isNumber && $0 != "." }).lazy.compactMap { Double(String($0)) }.first
        let measuredMilliseconds = try? XCTUnwrap(milliseconds)
        XCTAssertGreaterThan(measuredMilliseconds ?? 0, 0)
        XCTAssertLessThan(measuredMilliseconds ?? .infinity, 10_000, "Launch metrics belong in the instrumented performance test, while this smoke check rejects missing or stalled reporting")
    }

    func testInstrumentedLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            let app = launchApp()
            XCTAssertTrue(app.buttons["add-item"].waitForExistence(timeout: 3))
            app.terminate()
        }
    }

    func testAccessibilityAuditHasNoCriticalFindings() throws {
        try audit(launchApp())
    }

    func testDarkModeAndReducedMotionAccessibility() throws {
        let arguments = ["-UIAccessibilityReduceMotionEnabled", "YES"]
        var app = launchApp(extraArguments: arguments)
        selectSection("Settings", in: app)
        choose("Dark", for: "appearance", in: app)
        selectSection("Inbox", in: app)
        try audit(app)
        app.terminate()
        app = launchApp(extraArguments: ["--ui-testing-seed-gallery"] + arguments)
        let firstCard = items(titled: galleryTitles[0], in: app).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 3))
        XCTAssertTrue(preview(for: firstCard, in: app).waitForExistence(timeout: 3))
        attachScreenshot("ios-gallery-3a-2-dark", from: app)
        try audit(app)
    }

    func testLargestDynamicTypeKeepsPrimaryActionReachable() {
        let app = launchApp(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let addItem = app.buttons["Add Item"]
        XCTAssertTrue(addItem.waitForExistence(timeout: 3))
        for _ in 0..<5 where !addItem.isHittable { app.swipeUp() }
        XCTAssertTrue(addItem.isHittable)
    }

    func testCompactGalleryShowsTwoColumnsAndMixedPreviews() throws {
        let app = launchApp(extraArguments: ["--ui-testing-seed-gallery", "-AppleInterfaceStyle", "Light"])
        try XCTSkipUnless(app.frame.width < 700, "This screenshot checks the compact two-column gallery")
        let navigationBar = app.navigationBars["Inbox"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 3))
        let cards = galleryTitles.prefix(4).map { items(titled: $0, in: app).firstMatch }
        for (title, card) in zip(galleryTitles.prefix(4), cards) {
            XCTAssertTrue(card.waitForExistence(timeout: 3), "Missing \(title)")
            XCTAssertTrue(card.isHittable, "The first four cards must be visible: \(title)")
        }

        let firstFrame = cards[0].frame
        let secondFrame = cards[1].frame
        XCTAssertEqual(firstFrame.minY, secondFrame.minY, accuracy: 1)
        XCTAssertLessThan(firstFrame.maxX, secondFrame.minX)
        XCTAssertEqual(firstFrame.width, secondFrame.width, accuracy: 1)
        XCTAssertLessThan(firstFrame.width, app.frame.width / 2)
        XCTAssertLessThanOrEqual(navigationBar.frame.height, 64, "The library title must remain inline")
        XCTAssertGreaterThanOrEqual(firstFrame.minY, navigationBar.frame.maxY - 1)
        XCTAssertLessThanOrEqual(firstFrame.minY - navigationBar.frame.maxY, 16, "Cards must start directly below the toolbar")
        for card in [cards[0], cards[2], cards[3]] {
            let image = preview(for: card, in: app)
            XCTAssertTrue(image.waitForExistence(timeout: 3))
            XCTAssertGreaterThan(image.frame.height, 0)
        }
        XCTAssertFalse(preview(for: cards[1], in: app).exists, "Text-only links must not have empty media placeholders")
        for identifier in ["show-sections", "show-filters", "collection-layout", "add-item"] {
            XCTAssertTrue(app.buttons[identifier].isHittable, "Missing toolbar control: \(identifier)")
        }
        for identifier in ["filter-type", "filter-source", "filter-date"] {
            XCTAssertFalse(app.buttons[identifier].exists, "Filters belong in the sheet, not above the gallery")
        }
        let search = app.searchFields["Search saved content"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertTrue(search.isHittable)
        XCTAssertGreaterThan(search.frame.midY, app.frame.minY + app.frame.height * 0.75, "Native search must remain at the bottom")
        XCTAssertFalse(app.staticTexts["gallery-page-status"].exists, "Small libraries must keep the selected 3A-2 layout")
        attachScreenshot("ios-gallery-3a-2", from: app)
        let sectionTitle = navigationBar.descendants(matching: .any)["library-section-title"].firstMatch
        XCTAssertTrue(sectionTitle.waitForExistence(timeout: 3), "The inline section title must be visible")
        XCTAssertEqual(sectionTitle.label, "Inbox")
        XCTAssertGreaterThan(sectionTitle.frame.width, 30)
        XCTAssertTrue(navigationBar.frame.contains(sectionTitle.frame))
        XCTAssertLessThan(sectionTitle.frame.midX, app.frame.midX, "The title belongs beside the section button, not in the center")
        try audit(app)

        for title in galleryTitles.suffix(2) {
            scrollTo(items(titled: title, in: app).firstMatch, in: app)
        }
        let firstCard = items(titled: galleryTitles[0], in: app).firstMatch
        scrollTo(firstCard, in: app)
        XCTAssertTrue(preview(for: firstCard, in: app).waitForExistence(timeout: 3), "Scrolling back must reload the local preview")
        openFixture(galleryTitles[0], in: app)
        app.navigationBars.buttons["Inbox"].tap()
        XCTAssertTrue(preview(for: items(titled: galleryTitles[0], in: app).firstMatch, in: app).waitForExistence(timeout: 3), "Returning from details must restore the preview")
    }

    func testOffscreenGalleryMediaKeepsItsHeightAfterLoading() {
        let app = launchApp(extraArguments: ["--ui-testing-seed-gallery", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let first = items(titled: galleryTitles[0], in: app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(preview(for: first, in: app).waitForExistence(timeout: 3))
        let card = items(titled: galleryTitles[3], in: app).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(card.frame.minY, app.frame.maxY + 200, "The fixture must start beyond the preview loading margin")
        XCTAssertFalse(preview(for: card, in: app).exists, "Offscreen image pixels must remain unloaded")
        let itemID = card.identifier.dropFirst("item-".count)
        let reserved = app.descendants(matching: .any)["item-preview-loading-\(itemID)"].firstMatch
        XCTAssertTrue(reserved.waitForExistence(timeout: 3), "Image space must exist before pixel decoding")
        let cardHeight = card.frame.height
        let mediaHeight = reserved.frame.height
        XCTAssertGreaterThan(mediaHeight, 100)
        scrollTo(card, in: app)
        let image = preview(for: card, in: app)
        XCTAssertTrue(image.waitForExistence(timeout: 3))
        XCTAssertEqual(card.frame.height, cardHeight, accuracy: 1)
        XCTAssertEqual(image.frame.height, mediaHeight, accuracy: 1)
        for _ in 0..<10 where !first.isHittable { app.swipeDown() }
        XCTAssertTrue(first.isHittable)
        XCTAssertTrue(reserved.waitForExistence(timeout: 3), "Leaving the viewport must release pixels, not reserved space")
        XCTAssertEqual(card.frame.height, cardHeight, accuracy: 1)
        XCTAssertEqual(reserved.frame.height, mediaHeight, accuracy: 1)
    }

    func testLargestDynamicTypeKeepsPopulatedGalleryAndControlsReachable() throws {
        let app = launchApp(extraArguments: ["--ui-testing-seed-gallery", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let firstCard = items(titled: galleryTitles[0], in: app).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 3))
        XCTAssertTrue(preview(for: firstCard, in: app).waitForExistence(timeout: 3))
        let firstFrame = firstCard.frame
        if app.frame.width < 700 {
            XCTAssertGreaterThan(firstFrame.width, app.frame.width * 0.75, "Accessibility text sizes must use one column")
        }
        XCTAssertTrue(app.buttons["library-actions"].isHittable)
        for (identifier, label) in [("show-filters", "Filters"), ("collection-layout", "View"), ("add-item", "Add")] {
            XCTAssertTrue(libraryControl(identifier, label: label, in: app).isHittable, "Unreachable library action: \(label)")
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.93)).tap()
        XCTAssertTrue(app.buttons["show-filters"].waitForNonExistence(timeout: 3), "Dismiss the actions menu before auditing the gallery")
        XCTAssertFalse(app.buttons["filter-type"].exists)
        attachScreenshot("ios-gallery-3a-2-largest", from: app)
        try audit(app)

        let secondCard = items(titled: galleryTitles[1], in: app).firstMatch
        scrollTo(secondCard, in: app)
        XCTAssertEqual(secondCard.frame.minX, firstFrame.minX, accuracy: 1)
        XCTAssertEqual(secondCard.frame.width, firstFrame.width, accuracy: 1)
        scrollTo(items(titled: galleryTitles[5], in: app).firstMatch, in: app)
        openFilters(in: app)
        for identifier in ["filter-type", "filter-source", "filter-date", "reset-filters"] {
            scrollTo(app.buttons[identifier], in: app)
        }
        dismissFilters(in: app)
        openQuickAdd(in: app)
        XCTAssertTrue(app.textViews["Content"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
    }

    func testFilterSheetCombinesTypeSourceAndDateAndResetsImmediately() {
        let app = launchApp(extraArguments: ["--ui-testing-seed-panel"])
        let titles = ["Panel Link", "Panel Text", "Panel Code", "Panel Image", "Panel File"]
        XCTAssertTrue(items(titled: "Panel File", in: app).firstMatch.waitForExistence(timeout: 3))
        openFilters(in: app)
        assertPicker("filter-type", hasValue: "All types", in: app)
        assertPicker("filter-source", hasValue: "All sources", in: app)
        assertPicker("filter-date", hasValue: "Any time", in: app)
        choose("Links", for: "filter-type", in: app)
        choose("Safari", for: "filter-source", in: app)
        choose("Past week", for: "filter-date", in: app)
        dismissFilters(in: app)
        XCTAssertTrue(items(titled: "Panel Link", in: app).firstMatch.waitForExistence(timeout: 3))
        for title in titles.dropFirst() {
            XCTAssertTrue(items(titled: title, in: app).firstMatch.waitForNonExistence(timeout: 3), "Unexpected result: \(title)")
        }

        openFilters(in: app)
        assertPicker("filter-type", hasValue: "Links", in: app)
        assertPicker("filter-source", hasValue: "Safari", in: app)
        assertPicker("filter-date", hasValue: "Past week", in: app)
        choose("Notes", for: "filter-source", in: app)
        dismissFilters(in: app)
        for title in titles {
            XCTAssertTrue(items(titled: title, in: app).firstMatch.waitForNonExistence(timeout: 3), "Type and source must intersect: \(title)")
        }

        openFilters(in: app)
        choose("Text", for: "filter-type", in: app)
        dismissFilters(in: app)
        XCTAssertTrue(items(titled: "Panel Text", in: app).firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(items(titled: "Panel Link", in: app).firstMatch.waitForNonExistence(timeout: 3))
        openFilters(in: app)
        app.buttons["reset-filters"].tap()
        assertPicker("filter-type", hasValue: "All types", in: app)
        assertPicker("filter-source", hasValue: "All sources", in: app)
        assertPicker("filter-date", hasValue: "Any time", in: app)
        dismissFilters(in: app)
        XCTAssertTrue(items(titled: "Panel File", in: app).firstMatch.waitForExistence(timeout: 3))
        for title in titles {
            scrollTo(items(titled: title, in: app).firstMatch, in: app)
        }
        XCTAssertTrue(app.navigationBars["Inbox"].exists)
    }

    func testCollectionLayoutMenuSwitchesBetweenListAndGallery() {
        let app = launchApp(extraArguments: ["--ui-testing-seed-panel"])
        let galleryItem = items(titled: "Panel Text", in: app).firstMatch
        scrollTo(galleryItem, in: app)
        let galleryWidth = galleryItem.frame.width
        assertPicker("collection-layout", hasValue: "Gallery", in: app)
        choose("List", for: "collection-layout", in: app)
        assertPicker("collection-layout", hasValue: "List", in: app)
        let listItem = items(titled: "Panel Text", in: app).firstMatch
        scrollTo(listItem, in: app)
        if app.frame.width < 700 {
            XCTAssertGreaterThan(listItem.frame.width, galleryWidth * 1.5)
        }
        XCTAssertTrue(app.navigationBars["Inbox"].exists)
        openFixture("Panel Text", in: app)
        app.navigationBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.navigationBars["Inbox"].waitForExistence(timeout: 3))
        choose("Gallery", for: "collection-layout", in: app)
        assertPicker("collection-layout", hasValue: "Gallery", in: app)
        let restoredGalleryItem = items(titled: "Panel Text", in: app).firstMatch
        scrollTo(restoredGalleryItem, in: app)
        XCTAssertEqual(restoredGalleryItem.frame.width, galleryWidth, accuracy: 1)
        XCTAssertTrue(app.buttons["show-filters"].isHittable)
        XCTAssertTrue(app.buttons["add-item"].isHittable)
        XCTAssertTrue(app.searchFields["Search saved content"].exists)
    }

    func testGalleryPagesBoundCardsAndClampAfterArchivingTheLastItem() throws {
        let app = launchApp(extraArguments: ["--ui-testing-seed-gallery-pages"])
        assertGalleryPage(1, of: 3, cardCount: 40, firstTitle: "Gallery item 001", in: app)
        XCTAssertFalse(items(titled: "Gallery item 041", in: app).firstMatch.exists)
        XCTAssertFalse(app.buttons["gallery-previous-page"].isEnabled)
        for identifier in ["gallery-previous-page", "gallery-next-page"] {
            let button = app.buttons[identifier]
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertLessThanOrEqual(button.frame.maxY, app.searchFields["Search saved content"].frame.minY)
        }
        attachScreenshot("ios-gallery-pagination", from: app)
        app.swipeUp()
        app.buttons["gallery-next-page"].tap()
        assertGalleryPage(2, of: 3, cardCount: 40, firstTitle: "Gallery item 041", in: app)
        XCTAssertFalse(items(titled: "Gallery item 001", in: app).firstMatch.exists)
        XCTAssertFalse(items(titled: "Gallery item 081", in: app).firstMatch.exists)
        app.buttons["gallery-previous-page"].tap()
        assertGalleryPage(1, of: 3, cardCount: 40, firstTitle: "Gallery item 001", in: app)
        app.buttons["gallery-next-page"].tap()
        app.buttons["gallery-next-page"].tap()
        assertGalleryPage(3, of: 3, cardCount: 1, firstTitle: "Gallery item 081", in: app)
        XCTAssertFalse(app.buttons["gallery-next-page"].isEnabled)
        try audit(app)

        openFixture("Gallery item 081", in: app)
        app.navigationBars.buttons["Inbox"].tap()
        assertGalleryPage(3, of: 3, cardCount: 1, firstTitle: "Gallery item 081", in: app)
        performContextAction("Archive", on: "Gallery item 081", in: app)
        assertGalleryPage(2, of: 2, cardCount: 40, firstTitle: "Gallery item 041", in: app)
        XCTAssertFalse(items(titled: "Gallery item 081", in: app).firstMatch.exists)
        selectSection("Archive", in: app)
        XCTAssertTrue(items(titled: "Gallery item 081", in: app).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["gallery-page-status"].exists)
    }

    func testGalleryPaginationResetsForSearchSectionsFiltersAndLayout() {
        let app = launchApp(extraArguments: ["--ui-testing-seed-gallery-pages"])
        assertGalleryPage(1, of: 3, cardCount: 40, firstTitle: "Gallery item 001", in: app)
        app.buttons["gallery-next-page"].tap()
        let search = app.searchFields["Search saved content"]
        search.tap()
        let query = "Gallery item 081"
        search.typeText(query)
        XCTAssertTrue(app.staticTexts["gallery-page-status"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(items(titled: query, in: app).firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(galleryCards(in: app).count, 1, "Search must include items outside the active page")
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: query.count))
        assertGalleryPage(1, of: 3, cardCount: 40, firstTitle: "Gallery item 001", in: app)
        let closeSearch = app.buttons.matching(NSPredicate(format: "label == 'close' OR label == 'Cancel'")).firstMatch
        XCTAssertTrue(closeSearch.waitForExistence(timeout: 3))
        closeSearch.tap()
        XCTAssertTrue(app.buttons["show-sections"].waitForExistence(timeout: 3))
        app.buttons["gallery-next-page"].tap()
        selectSection("Pinned", in: app)
        assertGalleryPage(1, of: 3, cardCount: 40, firstTitle: "Gallery item 001", in: app)
        selectSection("Inbox", in: app)

        app.buttons["gallery-next-page"].tap()
        openFilters(in: app)
        choose("Safari", for: "filter-source", in: app)
        dismissFilters(in: app)
        assertGalleryPage(1, of: 2, cardCount: 40, firstTitle: "Gallery item 001", in: app)
        app.buttons["gallery-next-page"].tap()
        assertGalleryPage(2, of: 2, cardCount: 1, firstTitle: "Gallery item 081", in: app)
        openFilters(in: app)
        choose("Code", for: "filter-type", in: app)
        dismissFilters(in: app)
        assertGalleryPage(1, of: 2, cardCount: 40, firstTitle: "Gallery item 001", in: app)
        app.buttons["gallery-next-page"].tap()
        openFilters(in: app)
        choose("Text", for: "filter-type", in: app)
        dismissFilters(in: app)
        XCTAssertTrue(app.staticTexts["No Results"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["gallery-page-status"].exists)
        openFilters(in: app)
        app.buttons["reset-filters"].tap()
        dismissFilters(in: app)
        assertGalleryPage(1, of: 3, cardCount: 40, firstTitle: "Gallery item 001", in: app)

        app.buttons["gallery-next-page"].tap()
        openFilters(in: app)
        choose("Past week", for: "filter-date", in: app)
        dismissFilters(in: app)
        assertGalleryPage(1, of: 3, cardCount: 40, firstTitle: "Gallery item 001", in: app)
        app.buttons["gallery-next-page"].tap()
        choose("List", for: "collection-layout", in: app)
        choose("Gallery", for: "collection-layout", in: app)
        assertGalleryPage(1, of: 3, cardCount: 40, firstTitle: "Gallery item 001", in: app)
    }

    func testLargestDynamicTypeKeepsGalleryPageControlsReachable() throws {
        let app = launchApp(extraArguments: ["--ui-testing-seed-gallery-pages", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        assertGalleryPage(1, of: 3, cardCount: 40, firstTitle: "Gallery item 001", in: app)
        let next = app.buttons["gallery-next-page"]
        let previous = app.buttons["gallery-previous-page"]
        let status = app.staticTexts["gallery-page-status"]
        let search = app.searchFields["Search saved content"]
        XCTAssertTrue(next.isHittable)
        XCTAssertGreaterThanOrEqual(next.frame.height, 44)
        XCTAssertGreaterThanOrEqual(previous.frame.height, 44)
        XCTAssertTrue(app.frame.contains(status.frame))
        XCTAssertLessThanOrEqual(next.frame.maxY, search.frame.minY)
        next.tap()
        assertGalleryPage(2, of: 3, cardCount: 40, firstTitle: "Gallery item 041", in: app)
        XCTAssertTrue(previous.isHittable)
        next.tap()
        assertGalleryPage(3, of: 3, cardCount: 1, firstTitle: "Gallery item 081", in: app)
        attachScreenshot("ios-gallery-pagination-largest", from: app)
        try audit(app)
    }

    func testSettingsGroupsDefaultsAndPreviewPersistence() {
        var app = launchApp()
        selectSection("Settings", in: app)
        for group in ["Security & Privacy", "Saving & Sharing", "Appearance & Browsing", "Sync & Data"] {
            scrollTo(app.staticTexts[group].firstMatch, in: app)
        }
        assertSwitch("app-lock-enabled", isOn: false, in: app)
        XCTAssertFalse(app.buttons["lock-delay"].exists)
        assertSwitch("automatic-link-previews", isOn: false, in: app)
        assertSwitch("save-shared-items-immediately", isOn: false, in: app)
        assertPicker("launch-page", hasValue: "Inbox", in: app)
        assertPicker("appearance", hasValue: "System", in: app)
        scrollTo(app.switches["Anonymous on-device product metrics"], in: app)
        for identifier in ["sync-account", "sync-status", "attachment-usage", "launch-readiness"] {
            let row = app.descendants(matching: .any)[identifier].firstMatch
            scrollTo(row, in: app)
            XCTAssertFalse([row.label, row.value as? String ?? ""].joined().isEmpty)
        }

        setSwitch("automatic-link-previews", isOn: true, in: app)
        app.terminate()
        app = launchApp()
        selectSection("Settings", in: app)
        assertSwitch("automatic-link-previews", isOn: true, in: app)
        setSwitch("automatic-link-previews", isOn: false, in: app)
        app.terminate()
        app = launchApp()
        selectSection("Settings", in: app)
        assertSwitch("automatic-link-previews", isOn: false, in: app)

        // A new dedicated domain must not inherit settings from a previous test.
        choose("Pinned", for: "launch-page", in: app)
        choose("Dark", for: "appearance", in: app)
        app.terminate()
        preferencesID = UUID()
        app = launchApp()
        XCTAssertTrue(app.navigationBars["Inbox"].waitForExistence(timeout: 3))
        selectSection("Settings", in: app)
        assertPicker("launch-page", hasValue: "Inbox", in: app)
        assertPicker("appearance", hasValue: "System", in: app)
        assertSwitch("app-lock-enabled", isOn: false, in: app)
    }

    func testEveryLaunchPagePersistsWithoutResettingForegroundNavigation() {
        var app = launchApp()
        let choices = [("Inbox", "Inbox"), ("Pinned", "Pinned"), ("Recently Used", "Recent"), ("Last Library Section", "Archive")]
        for (choice, expectedSection) in choices {
            selectSection("Settings", in: app)
            choose(choice, for: "launch-page", in: app)
            XCTAssertTrue(app.navigationBars["Settings"].exists, "Changing next launch must not change the active section")
            selectSection("Archive", in: app)
            backgroundAndReturn(app)
            XCTAssertTrue(app.navigationBars["Archive"].waitForExistence(timeout: 3), "Foregrounding must not apply \(choice)")
            app.terminate()
            app = launchApp()
            XCTAssertTrue(app.navigationBars[expectedSection].waitForExistence(timeout: 3), "Wrong initial section for \(choice)")
            selectSection("Settings", in: app)
            assertPicker("launch-page", hasValue: choice, in: app)
        }

        // Settings and Trash must not replace the last valid library section.
        app.terminate()
        app = launchApp()
        XCTAssertTrue(app.navigationBars["Archive"].waitForExistence(timeout: 3))
        selectSection("Trash", in: app)
        app.terminate()
        app = launchApp()
        XCTAssertTrue(app.navigationBars["Archive"].waitForExistence(timeout: 3))
    }

    func testEveryAppearancePersistsAcrossForegroundAndColdLaunch() {
        var app = launchApp()
        for appearance in ["Light", "Dark", "System"] {
            selectSection("Settings", in: app)
            choose(appearance, for: "appearance", in: app)
            backgroundAndReturn(app)
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
            assertPicker("appearance", hasValue: appearance, in: app)
            app.terminate()
            app = launchApp()
            XCTAssertTrue(app.navigationBars["Inbox"].waitForExistence(timeout: 3))
            attachScreenshot("\(appearance) library after cold launch", from: app)
            selectSection("Settings", in: app)
            assertPicker("appearance", hasValue: appearance, in: app)
            // Keep app-owned presentation evidence in the final .xcresult only.
            openQuickAdd(in: app)
            XCTAssertTrue(app.textViews["Content"].waitForExistence(timeout: 3))
            attachScreenshot("\(appearance) Quick Add", from: app)
            app.buttons["Cancel"].tap()
        }
    }

    func testAppLockSettingsRequireFreshAuthenticationAndRetainCancelledValues() {
        let app = launchApp()
        selectSection("Settings", in: app)
        tapSwitch("app-lock-enabled", in: app)
        cancelNativeAuthentication(in: app)
        assertSwitch("app-lock-enabled", isOn: false, in: app)
        XCTAssertFalse(app.buttons["lock-delay"].exists)

        enableAppLock(in: app)
        assertPicker("lock-delay", hasValue: "Immediately", in: app)
        choose("1 minute", for: "lock-delay", in: app)
        cancelNativeAuthentication(in: app)
        assertPicker("lock-delay", hasValue: "Immediately", in: app)
        choose("1 minute", for: "lock-delay", in: app)
        completeNativeAuthentication(in: app)
        assertPicker("lock-delay", hasValue: "1 minute", in: app)
        backgroundAndReturn(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["unlock-stow"].exists)

        choose("5 minutes", for: "lock-delay", in: app)
        completeNativeAuthentication(in: app)
        assertPicker("lock-delay", hasValue: "5 minutes", in: app)
        backgroundAndReturn(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["unlock-stow"].exists)
        // Timeout boundaries use the injected clock in unit tests, not UI sleeps.
        choose("Immediately", for: "lock-delay", in: app)
        assertPicker("lock-delay", hasValue: "Immediately", in: app)
        tapSwitch("app-lock-enabled", in: app)
        cancelNativeAuthentication(in: app)
        assertSwitch("app-lock-enabled", isOn: true, in: app)
        tapSwitch("app-lock-enabled", in: app)
        completeNativeAuthentication(in: app)
        assertSwitch("app-lock-enabled", isOn: false, in: app)
        XCTAssertFalse(app.buttons["lock-delay"].exists)
    }

    func testImmediateRelockCancellationAndNonmatchKeepLibraryProtected() {
        let app = launchApp(extraArguments: ["--ui-testing-seed-panel"])
        enableAppLock(in: app)
        selectSection("Inbox", in: app)
        backgroundAndReturn(app)
        assertLocked(app, hiding: [app.staticTexts["Panel Text"], app.buttons["add-item"]])
        app.buttons["unlock-stow"].tap()
        cancelNativeAuthentication(in: app)
        assertLocked(app, hiding: [app.staticTexts["Panel Text"], app.buttons["add-item"]])

        app.buttons["unlock-stow"].tap()
        waitForNativeAuthentication(in: app)
        XCTAssertEqual(notify_post("com.apple.BiometricKit_Sim.fingerTouch.nomatch"), UInt32(NOTIFY_STATUS_OK))
        // Face ID can keep its prompt open for passcode fallback after a nonmatch.
        let rejected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let nativeFailure = [springboard, app].contains { owner in
                owner.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'not recognized'")).firstMatch.exists ||
                owner.buttons["Try Face ID Again"].exists || self.authenticationCancelButton(in: app).exists
            }
            return nativeFailure || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Authentication did not complete.'")).firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rejected], timeout: 5), .completed, "Simulator must report the native nonmatch before retrying")
        if authenticationCancelButton(in: app).exists { cancelNativeAuthentication(in: app) }
        assertLocked(app, hiding: [app.staticTexts["Panel Text"], app.buttons["add-item"]])
        unlock(app)
        XCTAssertTrue(app.staticTexts["Panel Text"].waitForExistence(timeout: 3))
        backgroundAndReturn(app)
        assertLocked(app, hiding: [app.staticTexts["Panel Text"]])
        unlock(app)
        XCTAssertTrue(app.buttons["add-item"].waitForExistence(timeout: 3))
    }

    func testColdRelaunchRequiresExplicitUnlockEvenWithGracePeriod() {
        var app = launchApp(extraArguments: ["--ui-testing-seed-panel"])
        enableAppLock(in: app)
        choose("5 minutes", for: "lock-delay", in: app)
        completeNativeAuthentication(in: app)
        assertPicker("lock-delay", hasValue: "5 minutes", in: app)
        app.terminate()
        app = launchApp(extraArguments: ["--ui-testing-seed-panel"])
        assertLocked(app, hiding: [app.staticTexts["Panel Text"], app.buttons["add-item"]])
        XCTAssertFalse(app.staticTexts["Verifying identity…"].exists, "Cold start must wait for explicit Unlock Stow")
        unlock(app)
        XCTAssertTrue(app.navigationBars["Inbox"].waitForExistence(timeout: 3))
        selectSection("Settings", in: app)
        assertSwitch("app-lock-enabled", isOn: true, in: app)
        assertPicker("lock-delay", hasValue: "5 minutes", in: app)
    }

    func testQuickAddDraftIsHiddenWhileLockedAndRestoredAfterUnlock() {
        let app = launchApp()
        enableAppLock(in: app)
        selectSection("Inbox", in: app)
        openQuickAdd(in: app)
        let content = app.textViews["Content"]
        content.tap()
        content.typeText("let privateDraft = 42")
        setSwitch("Save as Code", isOn: true, in: app)
        backgroundAndReturn(app)
        assertLocked(app, hiding: [content, app.buttons["save-item"], app.switches["Save as Code"]])
        unlock(app)
        XCTAssertTrue(content.waitForExistence(timeout: 3))
        XCTAssertEqual(content.value as? String, "let privateDraft = 42")
        assertSwitch("Save as Code", isOn: true, in: app)
        app.buttons["save-item"].tap()
        XCTAssertTrue(app.staticTexts["let privateDraft = 42"].waitForExistence(timeout: 3))
    }

    func testEditorDraftIsHiddenWhileLockedAndRestoredAfterUnlock() {
        let app = launchApp(extraArguments: ["--ui-testing-seed-panel"])
        enableAppLock(in: app)
        selectSection("Inbox", in: app)
        openFixture("Panel Text", in: app)
        app.buttons["Edit"].tap()
        // A populated vertical Note field loses its placeholder identifier.
        // The text-item editor keeps title/note order across lock transitions.
        XCTAssertEqual(app.textFields.count, 2)
        let note = app.textFields.element(boundBy: 1)
        scrollTo(note, in: app)
        note.tap()
        note.typeText("Private unsaved editor note")
        backgroundAndReturn(app)
        assertLocked(app, hiding: [note, app.textFields["Title"], app.buttons["Done"], app.navigationBars["Panel Text"]])
        unlock(app)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        XCTAssertEqual(note.value as? String, "Private unsaved editor note")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Private unsaved editor note"].waitForExistence(timeout: 3))
    }

    func testNativeQuickLookIsProtectedAndRestored() {
        let app = launchApp(extraArguments: ["--ui-testing-seed-panel"])
        enableAppLock(in: app)
        selectSection("Inbox", in: app)
        openFixture("Panel File", in: app)
        scrollTo(app.buttons["Quick Look"], in: app)
        app.buttons["Quick Look"].tap()
        // iOS 26 labels this native button "close", not "Done".
        let done = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        let previewText = app.textViews.matching(NSPredicate(format: "value == 'panel file' OR label == 'panel file'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Native Quick Look must be presented")
        XCTAssertTrue(previewText.waitForExistence(timeout: 3))
        attachScreenshot("Quick Look before background", from: app)
        backgroundAndReturn(app)
        assertLocked(app, hiding: [done, previewText, app.staticTexts["panel.txt"], app.navigationBars["Panel File"]])
        attachScreenshot("Quick Look covered by App Lock", from: app)
        unlock(app)
        XCTAssertTrue(done.waitForExistence(timeout: 3), "Unlock must restore the existing Quick Look presentation")
        XCTAssertTrue(previewText.waitForExistence(timeout: 3), "Unlock must restore the preview content")
        attachScreenshot("Quick Look restored after unlock", from: app)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Panel File"].waitForExistence(timeout: 3))
    }

    func testNativeShareSheetIsProtectedAndRestored() {
        let app = launchApp(extraArguments: ["--ui-testing-seed-panel"])
        enableAppLock(in: app)
        selectSection("Inbox", in: app)
        openFixture("Panel Text", in: app)
        scrollTo(app.buttons["Share"], in: app)
        app.buttons["Share"].tap()
        let close = nativeShareCloseButton(in: app)
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Native activity sheet must expose Close or Cancel")
        backgroundAndReturn(app)
        assertLocked(app, hiding: [close, app.buttons["Copy"], app.navigationBars["Panel Text"]])
        unlock(app)
        XCTAssertTrue(close.waitForExistence(timeout: 3), "Unlock must restore the existing native share sheet")
        close.tap()
        XCTAssertTrue(app.navigationBars["Panel Text"].waitForExistence(timeout: 3))
    }

    func testLargestDynamicTypeKeepsSettingsAndUnlockControlsReachable() {
        let app = launchApp(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        selectSection("Settings", in: app)
        for identifier in ["app-lock-enabled", "automatic-link-previews", "save-shared-items-immediately", "launch-page", "appearance"] {
            scrollTo(app.descendants(matching: .any)[identifier].firstMatch, in: app)
        }
        choose("Dark", for: "appearance", in: app)
        choose("Last Library Section", for: "launch-page", in: app)
        enableAppLock(in: app)
        scrollTo(app.buttons["lock-delay"], in: app)
        backgroundAndReturn(app)
        assertLocked(app, hiding: [app.buttons["lock-delay"]])
        scrollTo(app.buttons["unlock-stow"], in: app)
        attachScreenshot("Dark lock screen at largest Dynamic Type", from: app)
        unlock(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        assertPicker("appearance", hasValue: "Dark", in: app)
    }

    func testSidebarExposesCompleteInformationArchitecture() {
        let app = launchApp()
        revealSections(in: app)

        for section in ["Inbox", "Recent", "Pinned", "Archive", "Trash", "Settings"] {
            let element = app.buttons[section].exists ? app.buttons[section] : app.staticTexts[section]
            XCTAssertTrue(element.waitForExistence(timeout: 3), "Missing \(section)")
        }
    }

    func testQuickAddCreatesInboxItem() {
        let app = launchApp()
        openQuickAdd(in: app)
        let content = app.textViews["Content"]
        XCTAssertTrue(content.waitForExistence(timeout: 3))
        content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.typeText("A searchable thought")
        app.buttons["save-item"].tap()

        XCTAssertTrue(app.staticTexts["A searchable thought"].waitForExistence(timeout: 3))
    }

    func testTypeSpecificDetailsExposeRequiredActions() {
        let app = launchApp(extraArguments: ["--ui-testing-seed-panel"])
        let expectations: [(String, [String])] = [
            ("Panel Link", ["Open Link", "Copy", "Share"]),
            ("Panel Text", ["Copy", "Share"]),
            ("Panel Code", ["Copy", "Share"]),
            ("Panel Image", ["Save Image", "Share"]),
            ("Panel File", ["Quick Look", "Open In", "Share"])
        ]

        for (title, controls) in expectations {
            openFixture(title, in: app)
            if title == "Panel Code" { XCTAssertTrue(app.descendants(matching: .any)["syntax-highlighted-code"].exists) }
            if title == "Panel Image" { XCTAssertTrue(app.descendants(matching: .any)["zoomable-image"].exists) }
            for _ in 0..<3 { app.swipeUp() }
            for control in controls {
                XCTAssertTrue(app.buttons[control].exists, "Missing \(control) for \(title)")
            }
            XCTAssertTrue(app.buttons["Pin"].exists)
            XCTAssertTrue(app.buttons["Archive"].exists)
            XCTAssertTrue(app.buttons["Delete"].exists)
            app.navigationBars.buttons["Inbox"].tap()
        }
    }

    func testDetailEditingPersistsNote() {
        let app = launchApp(extraArguments: ["--ui-testing-seed-panel"])
        openFixture("Panel Text", in: app)
        app.buttons["Edit"].tap()
        let note = app.textFields["Note"].exists ? app.textFields["Note"] : app.textViews["Note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.tap()
        note.typeText("Edited note")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Edited note"].waitForExistence(timeout: 3))
    }

    func testDetailSaveFailureRetainsDraftAndAllowsRetry() {
        let app = launchApp(extraArguments: ["--ui-testing-seed-panel"])
        openFixture("Panel Code", in: app)
        app.buttons["Edit"].tap()

        func replace(_ element: XCUIElement, with value: String) {
            for _ in 0..<6 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.isHittable)
            let previous = element.value as? String ?? ""
            element.tap()
            if element.elementType == .textView {
                // These fixtures are one line. Initial TextEditor focus can leave the caret at
                // the start; a second tap beyond the first line places it after the content.
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.1)).tap()
            }
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value)
            XCTAssertEqual(element.value as? String ?? "", value)
        }
        let title = app.textFields["Title"]
        // The vertical Note field loses its placeholder identifier once populated.
        // This code-item editor has exactly three fields in title/note/language order.
        XCTAssertEqual(app.textFields.count, 3)
        let note = app.textFields.element(boundBy: 1)
        let content = app.textViews.matching(NSPredicate(format: "identifier != 'Note' AND label != 'Note'")).firstMatch
        let language = app.textFields["Language"]
        XCTAssertTrue(content.waitForExistence(timeout: 3))
        let savedContent = content.value as? String ?? ""
        XCTAssertFalse(savedContent.isEmpty)
        replace(title, with: "Retained draft title")
        replace(note, with: "Retained draft note")
        replace(content, with: "")
        replace(language, with: "Retained language")
        app.buttons["Done"].tap()

        let alert = app.alerts["Stow couldn't complete that action"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["Done"].exists)
        XCTAssertEqual(title.value as? String, "Retained draft title")
        XCTAssertEqual(note.value as? String, "Retained draft note")
        XCTAssertEqual(content.value as? String, "")
        XCTAssertEqual(language.value as? String, "Retained language")
        XCTAssertTrue(app.navigationBars["Panel Code"].exists)
        XCTAssertTrue(app.staticTexts[savedContent].exists, "Failed save must not replace the saved preview")

        replace(content, with: "let retry = true")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Retained draft title"].exists)
        app.navigationBars.buttons["Inbox"].tap()
        openFixture("Retained draft title", in: app)
        app.buttons["Edit"].tap()
        XCTAssertEqual(title.value as? String, "Retained draft title")
        XCTAssertEqual(note.value as? String, "Retained draft note")
        XCTAssertEqual(content.value as? String, "let retry = true")
        XCTAssertEqual(language.value as? String, "retained language", "Saved language retains existing lowercase normalization")
    }

    func testGalleryContextMenuPinsArchivesAndRestoresItem() {
        let app = launchApp()
        let title = "Process this thought"
        addText(title, in: app)
        performContextAction("Pin", on: title, in: app)
        selectSection("Pinned", in: app)
        XCTAssertTrue(items(titled: title, in: app).firstMatch.waitForExistence(timeout: 3))
        performContextAction("Archive", on: title, in: app)
        selectSection("Inbox", in: app)
        XCTAssertTrue(items(titled: title, in: app).firstMatch.waitForNonExistence(timeout: 3))
        selectSection("Archive", in: app)
        XCTAssertTrue(items(titled: title, in: app).firstMatch.waitForExistence(timeout: 3))
        performContextAction("Restore to Inbox", on: title, in: app)
        XCTAssertTrue(items(titled: title, in: app).firstMatch.waitForNonExistence(timeout: 3))
        selectSection("Inbox", in: app)
        XCTAssertTrue(items(titled: title, in: app).firstMatch.waitForExistence(timeout: 3))
        selectSection("Pinned", in: app)
        XCTAssertTrue(items(titled: title, in: app).firstMatch.waitForExistence(timeout: 3), "Archive and restore must retain the pin")
    }

    func testSafariShareExtensionCapturesURLInOneSave() throws {
        let app = launchApp()
        enableAppLock(in: app)
        selectSection("Inbox", in: app)
        backgroundAndReturn(app)
        assertLocked(app, hiding: [app.buttons["add-item"]])
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        openExampleDomainShareSheet(in: safari)

        let shareExtension = XCUIApplication(bundleIdentifier: "dev.narumi.stow.share-ios")
        _ = shareExtension.state
        XCTAssertTrue(openStowShareExtension(from: safari, extensionApp: shareExtension))
        XCTAssertTrue(shareExtension.textFields["Title"].exists)
        let advanced = shareExtension.buttons["Advanced"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 3))
        advanced.tap()
        XCTAssertTrue(shareExtension.switches["Pin"].waitForExistence(timeout: 3))
        XCTAssertTrue(shareExtension.switches["Directly Archive"].exists)
        shareExtension.buttons["Save"].tap()

        app.activate()
        assertLocked(app, hiding: [app.staticTexts["example.com"], app.buttons["add-item"]])
        unlock(app)
        XCTAssertTrue(app.staticTexts["example.com"].waitForExistence(timeout: 5))
        XCTAssertEqual(items(titled: "example.com", in: app).count, 1)

        safari.activate()
        openSafariShareSheet(in: safari)
        XCTAssertTrue(openStowShareExtension(from: safari, extensionApp: shareExtension))
        XCTAssertTrue(shareExtension.buttons["Cancel"].waitForExistence(timeout: 5))
        let cancelledTitle = shareExtension.textFields["Title"]
        cancelledTitle.tap()
        cancelledTitle.typeText(" CANCELLED")
        shareExtension.buttons["Cancel"].tap()
        app.activate()
        assertLocked(app, hiding: [app.staticTexts["example.com"], app.buttons["add-item"]])
        unlock(app)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'CANCELLED'")).firstMatch.exists)
        XCTAssertEqual(items(titled: "example.com", in: app).count, 1)
    }

    func testSafariShareExtensionCanSaveImmediately() {
        let app = launchApp()
        selectSection("Settings", in: app)
        setSwitch("save-shared-items-immediately", isOn: true, in: app)
        enableAppLock(in: app)
        selectSection("Inbox", in: app)
        backgroundAndReturn(app)
        assertLocked(app, hiding: [app.buttons["add-item"]])

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        openExampleDomainShareSheet(in: safari)
        let shareActivity = safari.staticTexts["Stow"].firstMatch
        XCTAssertTrue(tapStowShareActivity(in: safari))

        let shareExtension = XCUIApplication(bundleIdentifier: "dev.narumi.stow.share-ios")
        XCTAssertFalse(shareExtension.staticTexts["Save to Stow"].waitForExistence(timeout: 1))
        XCTAssertTrue(shareActivity.waitForNonExistence(timeout: 8))

        app.activate()
        assertLocked(app, hiding: [app.staticTexts["example.com"], app.buttons["add-item"]])
        unlock(app)
        XCTAssertTrue(app.staticTexts["example.com"].waitForExistence(timeout: 5))
        XCTAssertEqual(items(titled: "example.com", in: app).count, 1)
    }

    func testSearchFindsMatchingContentAndHidesNonmatchingContent() {
        let app = launchApp()
        addText("Alpha banana", in: app)
        addText("Beta orange", in: app)

        let search = app.searchFields["Search saved content"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("banana")

        XCTAssertTrue(items(titled: "Beta orange", in: app).firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(items(titled: "Alpha banana", in: app).firstMatch.waitForExistence(timeout: 3))
    }

    func testQuickAddSupportsCodePinAndDirectArchiveOptions() {
        let app = launchApp()
        openQuickAdd(in: app)
        let content = app.textViews["Content"]
        XCTAssertTrue(content.waitForExistence(timeout: 3))
        content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.typeText("let answer = 42")
        let codeToggle = app.switches["Save as Code"]
        codeToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(codeToggle.value as? String, "1")
        app.swipeUp()
        for name in ["Pin", "Directly Archive"] {
            let toggle = app.switches[name]
            XCTAssertTrue(toggle.waitForExistence(timeout: 3))
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "1")
        }
        app.buttons["save-item"].tap()

        revealSections(in: app)
        let archive = app.buttons["Archive"].exists ? app.buttons["Archive"] : app.staticTexts["Archive"]
        archive.tap()
        XCTAssertTrue(app.staticTexts["let answer = 42"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.images["Pinned"].exists || app.staticTexts["Pinned"].exists)
    }

    private func galleryCards(in app: XCUIApplication) -> XCUIElementQuery {
        // Match item UUIDs, not the item-gallery/item-list containers or media previews.
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", "item-[0-9A-Fa-f-]{36}"))
    }

    private func items(titled title: String, in app: XCUIApplication) -> XCUIElementQuery {
        galleryCards(in: app).containing(.staticText, identifier: title)
    }

    private func assertGalleryPage(_ number: Int, of total: Int, cardCount: Int, firstTitle: String, in app: XCUIApplication) {
        let status = app.staticTexts.matching(NSPredicate(
            format: "identifier == %@ AND label == %@", "gallery-page-status", "Page \(number) of \(total)"
        )).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(galleryCards(in: app).count, cardCount, "Only the current page must create cards")
        let first = items(titled: firstTitle, in: app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(first.isHittable, "Page navigation must scroll to the first card")
    }

    private func preview(for item: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        let itemID = item.identifier.dropFirst("item-".count)
        return app.descendants(matching: .any)["item-preview-\(itemID)"].firstMatch
    }

    private func performContextAction(_ action: String, on title: String, in app: XCUIApplication) {
        let item = items(titled: title, in: app).firstMatch
        scrollTo(item, in: app)
        item.press(forDuration: 1)
        let button = app.buttons[action].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing context action: \(action)")
        button.tap()
        XCTAssertTrue(button.waitForNonExistence(timeout: 3))
    }

    private func selectSection(_ section: String, in app: XCUIApplication) {
        if app.navigationBars[section].exists { return }
        revealSections(in: app)
        let element = app.buttons[section].exists ? app.buttons[section] : app.staticTexts[section].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Missing section \(section)")
        element.tap()
        XCTAssertTrue(app.navigationBars[section].waitForExistence(timeout: 3))
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Control is not reachable: \(element)")
    }

    private func tapSwitch(_ identifier: String, in app: XCUIApplication) {
        let toggle = app.switches[identifier]
        scrollTo(toggle, in: app)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func assertSwitch(_ identifier: String, isOn: Bool, in app: XCUIApplication) {
        let toggle = app.switches[identifier]
        scrollTo(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, isOn ? "1" : "0", identifier)
    }

    private func setSwitch(_ identifier: String, isOn: Bool, in app: XCUIApplication) {
        let toggle = app.switches[identifier]
        scrollTo(toggle, in: app)
        if (toggle.value as? String == "1") != isOn { tapSwitch(identifier, in: app) }
        assertSwitch(identifier, isOn: isOn, in: app)
    }

    private func choose(_ option: String, for identifier: String, in app: XCUIApplication) {
        let picker = app.buttons[identifier]
        scrollTo(picker, in: app)
        picker.tap()
        let button = app.buttons[option].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing \(option) in \(identifier)")
        button.tap()
    }

    private func libraryControl(_ identifier: String, label: String, in app: XCUIApplication) -> XCUIElement {
        let control = app.buttons[identifier].firstMatch
        if control.exists && control.isHittable { return control }
        let namedControl = app.buttons[label].firstMatch
        if namedControl.exists && namedControl.isHittable { return namedControl }
        let actions = app.buttons["library-actions"]
        if actions.exists && actions.isHittable { actions.tap() }
        return control.exists ? control : app.buttons[label].firstMatch
    }

    private func openFilters(in app: XCUIApplication) {
        let button = libraryControl("show-filters", label: "Filters", in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
        XCTAssertTrue(app.buttons["filter-type"].waitForExistence(timeout: 3))
    }

    private func dismissFilters(in app: XCUIApplication) {
        let button = app.buttons["dismiss-filters"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
        XCTAssertTrue(app.buttons["filter-type"].waitForNonExistence(timeout: 3))
    }

    private func assertPicker(_ identifier: String, hasValue expected: String, in app: XCUIApplication) {
        let picker = app.buttons[identifier]
        scrollTo(picker, in: app)
        let rendered = [picker.label, picker.value as? String ?? ""].joined(separator: " ")
        XCTAssertTrue(rendered.contains(expected), "\(identifier) should show \(expected), got \(rendered)")
    }

    private func backgroundAndReturn(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
    }

    private func assertLocked(_ app: XCUIApplication, hiding elements: [XCUIElement]) {
        XCTAssertTrue(app.descendants(matching: .any)["privacy-shield"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["unlock-stow"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["unlock-stow"].isEnabled)
        XCTAssertFalse(app.buttons["show-sections"].exists, "Locked navigation must not be accessible")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Locking must dismiss the editor keyboard and suggestions")
        for element in elements {
            XCTAssertFalse(element.exists, "The privacy window must hide source accessibility, not only block taps: \(element)")
        }
    }

    private func enableAppLock(in app: XCUIApplication) {
        selectSection("Settings", in: app)
        assertSwitch("app-lock-enabled", isOn: false, in: app)
        tapSwitch("app-lock-enabled", in: app)
        completeNativeAuthentication(in: app)
        assertSwitch("app-lock-enabled", isOn: true, in: app)
    }

    private func unlock(_ app: XCUIApplication) {
        let button = app.buttons["unlock-stow"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
        completeNativeAuthentication(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["privacy-shield"].firstMatch.waitForNonExistence(timeout: 5))
    }

    private func authenticationCancelButton(in app: XCUIApplication) -> XCUIElement {
        let candidates = [
            XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Cancel"].firstMatch,
            app.buttons["Cancel"].firstMatch
        ]
        return candidates.first(where: { $0.exists }) ?? candidates[0]
    }

    private func faceIDPermissionButton(in app: XCUIApplication) -> XCUIElement? {
        for owner in [XCUIApplication(bundleIdentifier: "com.apple.springboard"), app] {
            let alert = owner.alerts.matching(NSPredicate(format: "label CONTAINS[c] 'Face ID'")).firstMatch
            guard alert.exists else { continue }
            for label in ["Allow", "OK"] where alert.buttons[label].exists { return alert.buttons[label] }
        }
        return nil
    }

    private func waitForNativeAuthentication(in app: XCUIApplication) {
        // iOS 26 first shows a Face ID HUD without a Cancel button. Cancellation
        // controls appear after a nonmatch. Do not require Cancel before matching.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.faceIDPermissionButton(in: app) != nil || self.authenticationCancelButton(in: app).exists ||
            [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")].contains { owner in
                owner.descendants(matching: .any).matching(NSPredicate(format: "label == 'Face ID'")).firstMatch.exists
            }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed,
                       "Native authentication did not appear. Run the final batch through Scripts/ui_tests.sh ios with Simulator biometrics enrolled.")
        if let permission = faceIDPermissionButton(in: app) { permission.tap() }
        XCTAssertTrue(app.staticTexts["Verifying identity…"].waitForExistence(timeout: 5),
                      "The app must still have a pending real authentication request")
    }

    private func completeNativeAuthentication(in app: XCUIApplication) {
        waitForNativeAuthentication(in: app)
        XCTAssertEqual(notify_post("com.apple.BiometricKit_Sim.fingerTouch.match"), UInt32(NOTIFY_STATUS_OK))
        XCTAssertTrue(app.staticTexts["Verifying identity…"].waitForNonExistence(timeout: 5), "Native biometric authentication did not complete")
        XCTAssertTrue(authenticationCancelButton(in: app).waitForNonExistence(timeout: 3))
    }

    private func cancelNativeAuthentication(in app: XCUIApplication) {
        waitForNativeAuthentication(in: app)
        if !authenticationCancelButton(in: app).exists {
            XCTAssertEqual(notify_post("com.apple.BiometricKit_Sim.fingerTouch.nomatch"), UInt32(NOTIFY_STATUS_OK))
        }
        let cancel = authenticationCancelButton(in: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Native cancellation must be available after a nonmatch")
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Verifying identity…"].waitForNonExistence(timeout: 5))
        let error = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Authentication did not complete.'")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 3), "Cancellation must retain the setting or lock and offer retry guidance")
    }

    private func openFixture(_ title: String, in app: XCUIApplication) {
        let item = items(titled: title, in: app).firstMatch
        scrollTo(item, in: app)
        item.staticTexts[title].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
    }

    private func nativeShareCloseButton(in app: XCUIApplication) -> XCUIElement {
        let buttons = app.buttons.matching(NSPredicate(format: "identifier == 'header.closeButton' OR label ==[c] 'Close' OR label ==[c] 'Cancel'"))
        return buttons.firstMatch
    }

    private func attachScreenshot(_ name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func audit(_ app: XCUIApplication) throws {
        let previous = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = previous }
        try app.performAccessibilityAudit { issue in
            if self.isOffscreenGalleryContrast(issue, in: app) { return true }
            let label = issue.element?.label ?? ""
            let knownSystemRenderedLabels = ["Inbox", "Archive", "Search saved content", "Its contents and actions will appear here."]
            let isKnownSystemElement = knownSystemRenderedLabels.contains(label) || knownSystemRenderedLabels.contains {
                issue.element?.descendants(matching: .any)[$0].exists == true
            }
            // iPadOS 26 reports contrast failures for its own NavigationSplitView sidebar material.
            let isIPadSystemContrast = app.frame.width > 700 && issue.auditType == .contrast
            return isIPadSystemContrast || (isKnownSystemElement && (issue.auditType == .contrast || issue.auditType == .textClipped))
        }
    }

    private func isOffscreenGalleryContrast(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication) -> Bool {
        guard issue.auditType == .contrast, let element = issue.element else { return false }
        print("Contrast element: id=\(element.identifier), label=\(element.label), frame=\(element.frame)")
        let prefix = "card-title-"
        guard element.identifier.hasPrefix(prefix) else { return false }
        let itemID = String(element.identifier.dropFirst(prefix.count))
        guard UUID(uuidString: itemID) != nil, app.buttons["item-\(itemID)"].exists else { return false }
        let navigation = app.navigationBars.firstMatch
        let search = app.searchFields["Search saved content"].firstMatch
        guard navigation.exists, search.exists else { return false }
        let viewport = CGRect(
            x: app.frame.minX, y: navigation.frame.maxY,
            width: app.frame.width, height: max(0, search.frame.minY - navigation.frame.maxY)
        )
        let frame = element.frame
        print("Gallery contrast geometry: \(element.label), frame=\(frame), viewport=\(viewport)")
        guard !viewport.isEmpty, !frame.isEmpty, !viewport.intersects(frame) else { return false }
        print("Offscreen gallery title contrast: \(element.label), frame=\(frame), viewport=\(viewport)")
        return true
    }

    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-preferences-id=\(preferencesID.uuidString)"] + extraArguments
        if extraArguments.contains("--ui-testing-seed-gallery") {
            do {
                let bundle = Bundle(for: StowUITests.self)
                var images: [String: String] = [:]
                for name in ["cafe", "workspace", "mountains"] {
                    let url = try XCTUnwrap(bundle.url(forResource: "gallery-\(name)", withExtension: "jpg"), "Missing gallery-\(name).jpg fixture")
                    images[name] = try Data(contentsOf: url).base64EncodedString()
                }
                let payload = try JSONSerialization.data(withJSONObject: images, options: [.sortedKeys])
                app.launchEnvironment["STOW_UI_TEST_GALLERY_IMAGES"] = String(decoding: payload, as: UTF8.self)
            } catch {
                XCTFail("Could not load gallery fixture images: \(error)")
            }
        }
        app.launch()
        return app
    }

    private func addText(_ text: String, in app: XCUIApplication) {
        openQuickAdd(in: app)
        let content = app.textViews["Content"]
        XCTAssertTrue(content.waitForExistence(timeout: 3))
        content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.typeText(text)
        app.buttons["save-item"].tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 3))
    }

    private func revealSections(in app: XCUIApplication) {
        let button = app.buttons["show-sections"]
        if button.waitForExistence(timeout: 1) { button.tap() }
    }

    private func openQuickAdd(in app: XCUIApplication) {
        for _ in 0..<2 {
            let toolbarAdd = libraryControl("add-item", label: "Add", in: app)
            let addButton = toolbarAdd.exists ? toolbarAdd : app.buttons["Add Item"]
            XCTAssertTrue(addButton.waitForExistence(timeout: 3))
            addButton.tap()
            if app.textViews["Content"].waitForExistence(timeout: 2) { return }
        }
        XCTFail("Quick Add did not appear after retrying its primary action")
    }

    private func openExampleDomainShareSheet(in safari: XCUIApplication) {
        safari.launch()
        // The address label can change to "Translation Available" during launch.
        let address = safari.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ OR ((identifier == 'Address' OR label == 'Address') AND (elementType == %d OR elementType == %d))",
            "CapsuleNavigationBar?", XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.textField.rawValue
        )).firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        let editor = safari.textFields["Address"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        safari.typeText("https://example.com")
        safari.typeText(XCUIKeyboardKey.return.rawValue)
        XCTAssertTrue(safari.webViews.otherElements["Example Domain"].waitForExistence(timeout: 8))
        openSafariShareSheet(in: safari)
    }

    private func openSafariShareSheet(in safari: XCUIApplication) {
        let more = safari.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        for _ in 0..<3 where !more.isHittable { safari.swipeDown() }
        XCTAssertTrue(more.isHittable)
        // Safari can report an invalid native hit point for this visible control.
        more.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let share = safari.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
    }

    private func tapStowShareActivity(in safari: XCUIApplication) -> Bool {
        let label = safari.staticTexts["Stow"].firstMatch
        let activity = label.waitForExistence(timeout: 3) ? label : safari.cells["Stow"].firstMatch
        guard activity.waitForExistence(timeout: 3) else { return false }
        activity.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    private func openStowShareExtension(
        from safari: XCUIApplication,
        extensionApp: XCUIApplication
    ) -> Bool {
        for _ in 0..<2 {
            guard tapStowShareActivity(in: safari) else { return false }
            if extensionApp.staticTexts["Save to Stow"].waitForExistence(timeout: 5) { return true }
        }
        return false
    }
}
