import XCTest

@MainActor
final class StowUITests: XCTestCase {
    func testInProcessLaunchReadinessMeetsOneSecondTarget() {
        let app = launchApp()
        revealSections(in: app)
        app.buttons["Settings"].tap()
        let readiness = app.descendants(matching: .any)["launch-readiness"]
        XCTAssertTrue(readiness.waitForExistence(timeout: 3))
        let value = readiness.value as? String ?? ""
        let rendered = value.isEmpty ? readiness.label : value
        let milliseconds = rendered.split(whereSeparator: { !$0.isNumber && $0 != "." }).lazy.compactMap { Double(String($0)) }.first
        XCTAssertNotNil(milliseconds)
        XCTAssertLessThan(milliseconds ?? .infinity, 1_000)
    }

    func testInstrumentedLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing"]
            app.launch()
            XCTAssertTrue(app.buttons["add-item"].waitForExistence(timeout: 3))
            app.terminate()
        }
    }

    func testAccessibilityAuditHasNoCriticalFindings() throws {
        try audit(launchApp())
    }

    func testDarkModeAndReducedMotionAccessibility() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleInterfaceStyle", "Dark", "-UIAccessibilityReduceMotionEnabled", "YES"]
        app.launch()
        try audit(app)
    }

    func testLargestDynamicTypeKeepsPrimaryActionReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let addItem = app.buttons["Add Item"]
        XCTAssertTrue(addItem.waitForExistence(timeout: 3))
        for _ in 0..<5 where !addItem.isHittable { app.swipeUp() }
        XCTAssertTrue(addItem.isHittable)
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
            let row = app.cells.containing(.staticText, identifier: title).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 3), "Missing \(title)")
            row.staticTexts[title].firstMatch.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
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
        let row = app.cells.containing(.staticText, identifier: "Panel Text").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.staticTexts["Panel Text"].firstMatch.tap()
        app.buttons["Edit"].tap()
        let note = app.textFields["Note"].exists ? app.textFields["Note"] : app.textViews["Note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.tap()
        note.typeText("Edited note")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Edited note"].waitForExistence(timeout: 3))
    }

    func testInboxSwipePinsAndArchivesItem() {
        let app = launchApp()
        addText("Swipe me", in: app)
        var rowTitle = app.cells.containing(.staticText, identifier: "Swipe me").firstMatch
        XCTAssertTrue(rowTitle.waitForExistence(timeout: 3))

        rowTitle.swipeRight()
        app.buttons["Pin"].tap()
        XCTAssertTrue(app.images["Pinned"].waitForExistence(timeout: 2))

        rowTitle = app.cells.containing(.staticText, identifier: "Swipe me").firstMatch
        rowTitle.swipeLeft()
        app.buttons["Archive"].tap()
        revealSections(in: app)
        let archive = app.buttons["Archive"].exists ? app.buttons["Archive"] : app.staticTexts["Archive"]
        archive.tap()
        XCTAssertTrue(app.staticTexts["Swipe me"].waitForExistence(timeout: 3))
    }

    func testSafariShareExtensionCapturesURLInOneSave() throws {
        let app = launchApp()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        let address = safari.buttons["Address"].exists ? safari.buttons["Address"] : safari.textFields["Address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        let editor = safari.textFields["Address"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("https://example.com")
        editor.typeText(XCUIKeyboardKey.return.rawValue)
        XCTAssertTrue(safari.staticTexts["Example Domain"].waitForExistence(timeout: 8))
        let more = safari.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        for _ in 0..<3 where !more.isHittable { safari.swipeDown() }
        XCTAssertTrue(more.isHittable)
        more.tap()
        let share = safari.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        share.tap()

        let stowActivity = safari.cells["Stow"]
        XCTAssertTrue(stowActivity.waitForExistence(timeout: 5))
        stowActivity.tap()
        let shareExtension = XCUIApplication(bundleIdentifier: "dev.narumi.stow.share.ios")
        XCTAssertTrue(shareExtension.staticTexts["Save to Stow"].waitForExistence(timeout: 5))
        XCTAssertTrue(shareExtension.textFields["Title"].exists)
        let advanced = shareExtension.buttons["Advanced"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 3))
        advanced.tap()
        XCTAssertTrue(shareExtension.switches["Pin"].waitForExistence(timeout: 3))
        XCTAssertTrue(shareExtension.switches["Directly Archive"].exists)
        shareExtension.buttons["Save"].tap()

        app.activate()
        XCTAssertTrue(app.staticTexts["example.com"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.cells.containing(.staticText, identifier: "example.com").count, 1)

        safari.activate()
        let secondMore = safari.buttons["More"]
        XCTAssertTrue(secondMore.waitForExistence(timeout: 5))
        for _ in 0..<3 where !secondMore.isHittable { safari.swipeDown() }
        XCTAssertTrue(secondMore.isHittable)
        secondMore.tap()
        let secondShare = safari.buttons["Share"]
        XCTAssertTrue(secondShare.waitForExistence(timeout: 3))
        secondShare.tap()
        XCTAssertTrue(safari.cells["Stow"].waitForExistence(timeout: 5))
        safari.cells["Stow"].tap()
        XCTAssertTrue(shareExtension.buttons["Cancel"].waitForExistence(timeout: 5))
        let cancelledTitle = shareExtension.textFields["Title"]
        cancelledTitle.tap()
        cancelledTitle.typeText(" CANCELLED")
        shareExtension.buttons["Cancel"].tap()
        app.activate()
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'CANCELLED'")).firstMatch.exists)
    }

    func testSearchFindsMatchingContentAndHidesNonmatchingContent() {
        let app = launchApp()
        addText("Alpha banana", in: app)
        addText("Beta orange", in: app)

        let search = app.searchFields["Search saved content"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("banana")

        XCTAssertTrue(app.staticTexts["Alpha banana"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Beta orange"].exists)
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

    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
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

    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + extraArguments
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
        let toolbarAdd = app.buttons.matching(identifier: "add-item").firstMatch
        let addButton = toolbarAdd.exists ? toolbarAdd : app.buttons["Add Item"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.tap()
    }
}
