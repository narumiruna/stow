import notify
import XCTest

@MainActor
final class StowUITests: XCTestCase {
    // Reuse only this test's dedicated Simulator preferences domain on relaunch.
    private var preferencesID = UUID()

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
        let app = launchApp(extraArguments: ["-AppleInterfaceStyle", "Dark", "-UIAccessibilityReduceMotionEnabled", "YES"])
        try audit(app)
    }

    func testLargestDynamicTypeKeepsPrimaryActionReachable() {
        let app = launchApp(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let addItem = app.buttons["Add Item"]
        XCTAssertTrue(addItem.waitForExistence(timeout: 3))
        for _ in 0..<5 where !addItem.isHittable { app.swipeUp() }
        XCTAssertTrue(addItem.isHittable)
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

    func testDetailSaveFailureRetainsDraftAndAllowsRetry() {
        let app = launchApp(extraArguments: ["--ui-testing-seed-panel"])
        let row = app.cells.containing(.staticText, identifier: "Panel Code").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.staticTexts["Panel Code"].firstMatch.tap()
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
        let savedRow = app.cells.containing(.staticText, identifier: "Retained draft title").firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 3))
        savedRow.staticTexts["Retained draft title"].firstMatch.tap()
        app.buttons["Edit"].tap()
        XCTAssertEqual(title.value as? String, "Retained draft title")
        XCTAssertEqual(note.value as? String, "Retained draft note")
        XCTAssertEqual(content.value as? String, "let retry = true")
        XCTAssertEqual(language.value as? String, "retained language", "Saved language retains existing lowercase normalization")
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
        XCTAssertEqual(app.cells.containing(.staticText, identifier: "example.com").count, 1)
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
        XCTAssertEqual(app.cells.containing(.staticText, identifier: "example.com").count, 1)
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
        let row = app.cells.containing(.staticText, identifier: title).firstMatch
        scrollTo(row, in: app)
        row.staticTexts[title].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
    }

    private func nativeShareCloseButton(in app: XCUIApplication) -> XCUIElement {
        let buttons = app.buttons.matching(NSPredicate(format: "label IN {'Close', 'Cancel'}"))
        return buttons.firstMatch
    }

    private func attachScreenshot(_ name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        app.launchArguments = ["--ui-testing", "--ui-testing-preferences-id=\(preferencesID.uuidString)"] + extraArguments
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
            let toolbarAdd = app.buttons.matching(identifier: "add-item").firstMatch
            let addButton = toolbarAdd.exists ? toolbarAdd : app.buttons["Add Item"]
            XCTAssertTrue(addButton.waitForExistence(timeout: 3))
            addButton.tap()
            if app.textViews["Content"].waitForExistence(timeout: 2) { return }
        }
        XCTFail("Quick Add did not appear after retrying its primary action")
    }

    private func openExampleDomainShareSheet(in safari: XCUIApplication) {
        safari.launch()
        let address = safari.buttons["Address"].exists ? safari.buttons["Address"] : safari.textFields["Address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        let editor = safari.textFields["Address"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        safari.typeText("https://example.com")
        safari.typeText(XCUIKeyboardKey.return.rawValue)
        XCTAssertTrue(safari.webViews.otherElements["Example Domain"].waitForExistence(timeout: 8))
        let more = safari.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        for _ in 0..<3 where !more.isHittable { safari.swipeDown() }
        XCTAssertTrue(more.isHittable)
        more.tap()
        let share = safari.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 3))
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
