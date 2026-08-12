import AppKit
import XCTest

@MainActor
final class StowMacUITests: XCTestCase {
    func testLibraryAndPasteInspiredQuickPanelWorkflow() {
        let app = launchApp()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        for section in ["Inbox", "Recently Used", "Pinned", "Archive", "Trash"] {
            XCTAssertTrue(app.staticTexts[section].waitForExistence(timeout: 3), "Missing \(section)")
        }
        XCTAssertFalse(app.staticTexts["Settings"].exists, "Settings belongs in the native Settings window, not the Library sidebar")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "library-filter-menu").firstMatch.waitForExistence(timeout: 3))
        attach(app.windows.firstMatch.screenshot(), named: "stow-mac-library")

        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        textEdit.launch()
        showPanel(in: app)

        let panel = app.windows["Stow Quick Panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(panel.frame.width, 700)
        XCTAssertLessThan(panel.frame.height, 430)
        XCTAssertGreaterThan(panel.frame.maxY, (NSScreen.main?.frame.height ?? 800) * 0.60)
        for mode in ["Clipboard", "Inbox", "Pinned"] {
            XCTAssertTrue(panel.buttons[mode].waitForExistence(timeout: 2), "Missing panel mode \(mode)")
        }
        XCTAssertFalse(panel.staticTexts["Settings"].exists)
        XCTAssertTrue(panel.buttons["Quick Add"].exists)
        XCTAssertTrue(panel.buttons["Close Quick Panel"].exists)
        XCTAssertTrue(panel.descendants(matching: .any).matching(identifier: "panel-status").firstMatch.exists)
        XCTAssertTrue(panel.staticTexts["Paste mode: Copy only"].exists)
        attach(panel.screenshot(), named: "stow-panel-normal")

        let searchButton = panel.buttons["Search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 3))
        searchButton.click()
        var search = panel.textFields["Search Stow"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertTrue(panel.descendants(matching: .any).matching(identifier: "panel-active-mode").firstMatch.exists)
        attach(panel.screenshot(), named: "stow-panel-search")
        let filters = panel.menuButtons["Search Filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 2))
        filters.click()
        app.menuItems["Images"].click()
        XCTAssertTrue(panel.buttons["Remove Image filter"].waitForExistence(timeout: 2))
        attach(panel.screenshot(), named: "stow-panel-filter-token")
        panel.buttons["Remove Image filter"].click()
        search = panel.textFields["Search Stow"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))

        replaceSearch(search, with: "Ｐａｎｅｌ　Ｔｅｘｔ")
        XCTAssertTrue(panel.buttons["Clear Search"].waitForExistence(timeout: 2))
        XCTAssertTrue(panel.buttons["Close Quick Panel"].exists, "Clear Search and Close must remain distinct")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "panel text payload")
        XCTAssertTrue(panel.staticTexts["Copied — paste with Command-V"].waitForExistence(timeout: 2))
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3), "Return should close the panel after the copy fallback")

        showPanel(in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        panel.buttons["Search"].click()
        search = panel.textFields["Search Stow"]
        replaceSearch(search, with: "Panel Code")
        app.typeKey("c", modifierFlags: .command)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "let panel = true")
        XCTAssertTrue(panel.staticTexts["Copied"].waitForExistence(timeout: 2))
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(panel.staticTexts["Edit Item"].waitForExistence(timeout: 3))
        attach(panel.screenshot(), named: "stow-panel-edit")
        attach(XCUIScreen.main.screenshot(), named: "stow-panel-edit-screen")
        panel.buttons["Cancel"].click()
        app.typeKey("a", modifierFlags: [.command, .shift])
        panel.buttons["More"].click()
        panel.buttons["Archive"].click()
        XCTAssertTrue(panel.buttons["Code, Panel Code"].waitForExistence(timeout: 3))
        if !panel.buttons["Clipboard"].exists {
            showPanel(in: app)
            if !panel.waitForExistence(timeout: 1) { showPanel(in: app) }
        }
        XCTAssertTrue(panel.buttons["Clipboard"].waitForExistence(timeout: 3))
        panel.buttons["Clipboard"].click()

        showPanel(in: app)
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3), "The panel command should toggle the panel")
        showPanel(in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        panel.buttons["Search"].click()
        search = panel.textFields["Search Stow"]
        replaceSearch(search, with: "Panel Image")
        app.typeKey("c", modifierFlags: .command)
        XCTAssertTrue(NSPasteboard.general.canReadObject(forClasses: [NSImage.self]))
        let imageCard = panel.buttons["Image, Panel Image"]
        XCTAssertTrue(imageCard.waitForExistence(timeout: 3))
        imageCard.click()
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(panel.staticTexts["Preview"].waitForExistence(timeout: 3))
        panel.buttons["Done"].click()
        search = panel.textFields["Search Stow"]
        replaceSearch(search, with: "No Such Clip")
        XCTAssertTrue(panel.staticTexts["No Results"].waitForExistence(timeout: 3))
        attach(panel.screenshot(), named: "stow-panel-no-results")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.buttons["Search"].waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))

        showPanel(in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        panel.buttons["Quick Add"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Quick Add"].waitForExistence(timeout: 3) || app.textViews["Content"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.sheets.count, 0, "Dedicated Quick Add must not also open a Library sheet")
        textEdit.terminate()
        app.terminate()
    }

    func testVisibleCloseOutsideDismissAndDestinationHandoffs() {
        let app = launchApp()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        let panel = app.windows["Stow Quick Panel"]

        showPanel(in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        XCTAssertTrue(panel.buttons["Close Quick Panel"].waitForExistence(timeout: 2))
        panel.buttons["Close Quick Panel"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))

        showPanel(in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        let library = app.windows.matching(identifier: "stow-library-window").firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 3))
        library.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3), "A click in another Stow window should dismiss the panel")

        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        textEdit.launch()
        showPanel(in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        textEdit.activate()
        XCTAssertTrue(textEdit.windows.firstMatch.waitForExistence(timeout: 3))
        textEdit.windows.firstMatch.click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3), "An outside click should dismiss a clean panel")

        showPanel(in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        panel.buttons["More"].click()
        XCTAssertTrue(panel.buttons["Archive"].waitForExistence(timeout: 2))
        for action in ["Quick Add", "Open Library", "Settings", "Close Quick Panel"] {
            XCTAssertTrue(panel.buttons[action].exists, "More must expose \(action) in its flat action group")
        }
        XCTAssertTrue(panel.checkBoxes["Monitor Clipboard"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.waitForExistence(timeout: 2), "Escape should dismiss More before the panel")
        XCTAssertTrue(panel.buttons["Archive"].waitForNonExistence(timeout: 2))

        panel.buttons["More"].click()
        panel.buttons["Open Library"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.windows.matching(identifier: "stow-library-window").firstMatch.exists || app.staticTexts["Inbox"].exists)

        showPanel(in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        panel.buttons["More"].click()
        panel.buttons["Settings"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.windows.matching(identifier: "stow-settings-window").firstMatch.waitForExistence(timeout: 5))
        for page in ["Capture", "Paste & Shortcuts", "Sync & Storage", "Privacy"] {
            XCTAssertTrue(app.buttons[page].exists || app.radioButtons[page].exists, "Missing Settings page \(page)")
        }

        textEdit.terminate()
        app.terminate()
    }

    func testDirtyEditorCancellationAndExplicitCloseConfirmation() {
        let app = launchApp()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        let panel = app.windows["Stow Quick Panel"]
        showPanel(in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        openCodeEditor(in: panel, app: app)

        let title = app.textFields["panel-editor-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        replaceSearch(title, with: "Unsaved Panel Code")

        requestQuickAdd(in: app)
        let destinationDiscard = confirmationButton("Discard Changes and Close", in: app)
        XCTAssertTrue(destinationDiscard.waitForExistence(timeout: 3), "A destination handoff must wait for dirty-edit confirmation")
        XCTAssertEqual(destinationDiscard.label, "Discard Changes and Close")
        confirmationButton("Keep Editing", in: app).click()
        XCTAssertTrue(app.staticTexts["Edit Item"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.textViews["Content"].exists, "Keeping the draft must cancel the destination handoff")

        app.typeKey(.escape, modifierFlags: [])
        let escapeDiscard = confirmationButton("Discard Changes", in: app)
        XCTAssertTrue(escapeDiscard.waitForExistence(timeout: 3))
        XCTAssertEqual(escapeDiscard.label, "Discard Changes")
        confirmationButton("Keep Editing", in: app).click()
        XCTAssertTrue(app.staticTexts["Edit Item"].waitForExistence(timeout: 2))

        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        textEdit.launch()
        XCTAssertTrue(textEdit.windows.firstMatch.waitForExistence(timeout: 3))
        textEdit.windows.firstMatch.click()
        let outsideDiscard = confirmationButton("Discard Changes and Close", in: app)
        XCTAssertTrue(outsideDiscard.waitForExistence(timeout: 3), "Outside dismissal must protect a dirty draft")
        XCTAssertEqual(outsideDiscard.label, "Discard Changes and Close")
        confirmationButton("Keep Editing", in: app).click()
        XCTAssertTrue(app.staticTexts["Edit Item"].waitForExistence(timeout: 2))

        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey("v", modifierFlags: [.command, .shift])
        let shortcutDiscard = confirmationButton("Discard Changes and Close", in: app)
        XCTAssertTrue(shortcutDiscard.waitForExistence(timeout: 3))
        XCTAssertEqual(shortcutDiscard.label, "Discard Changes and Close")
        attach(panel.screenshot(), named: "stow-panel-dirty-confirmation")
        shortcutDiscard.click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))

        showPanel(in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        panel.buttons["Search"].click()
        let search = panel.textFields["Search Stow"]
        replaceSearch(search, with: "Panel Code")
        XCTAssertTrue(panel.buttons["Code, Panel Code"].waitForExistence(timeout: 3), "Discarding must not persist the draft title")
        textEdit.terminate()
        app.terminate()
    }

    func testSuccessfulDragClosesOnlyAfterDestinationAcceptsItem() {
        let app = launchApp(extraArguments: ["--ui-testing-drop-target"])
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        let dropTarget = app.staticTexts["panel-drop-target"]
        XCTAssertTrue(dropTarget.waitForExistence(timeout: 3))

        showPanel(in: app)
        let panel = app.windows["Stow Quick Panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        panel.buttons["Search"].click()
        replaceSearch(panel.textFields["Search Stow"], with: "Panel Text")
        let card = panel.buttons["Text, Panel Text"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.press(forDuration: 0.7, thenDragTo: dropTarget, withVelocity: .slow, thenHoldForDuration: 1.0)

        XCTAssertTrue(app.staticTexts["Drop accepted"].waitForExistence(timeout: 3), "The destination should accept the dragged text")
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "The panel should close only after the destination accepts the drag")
        app.terminate()
    }

    func testFailedSaveAndSearchPreserveUsableState() {
        let saveFailureApp = launchApp(extraArguments: ["--ui-testing-fail-save"])
        XCTAssertTrue(saveFailureApp.windows.firstMatch.waitForExistence(timeout: 15))
        let savePanel = saveFailureApp.windows["Stow Quick Panel"]
        showPanel(in: saveFailureApp)
        XCTAssertTrue(savePanel.waitForExistence(timeout: 3))
        openCodeEditor(in: savePanel, app: saveFailureApp)
        let title = saveFailureApp.textFields["panel-editor-title"]
        replaceSelectedText(in: title, with: "Failed Save Draft")
        XCTAssertEqual(title.value as? String, "Failed Save Draft")
        XCTAssertTrue(saveFailureApp.buttons["Save"].isEnabled)
        saveFailureApp.buttons["Save"].click()
        XCTAssertTrue(saveFailureApp.staticTexts["panel-editor-error"].waitForExistence(timeout: 3))
        let retainedTitle = saveFailureApp.textFields["panel-editor-title"]
        XCTAssertTrue(retainedTitle.waitForExistence(timeout: 3), "A failed save must preserve the editor and editable draft")
        XCTAssertEqual(retainedTitle.value as? String, "Failed Save Draft", "A failed save must preserve the draft")
        attach(saveFailureApp.screenshot(), named: "stow-panel-save-error")
        saveFailureApp.terminate()

        let searchFailureApp = launchApp(extraArguments: ["--ui-testing-fail-retrieval-search", "--ui-testing-panel-width=480"])
        XCTAssertTrue(searchFailureApp.windows.firstMatch.waitForExistence(timeout: 15))
        let searchPanel = searchFailureApp.windows["Stow Quick Panel"]
        showPanel(in: searchFailureApp)
        XCTAssertTrue(searchPanel.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(searchPanel.frame.width, 520)
        XCTAssertTrue(searchPanel.buttons["Close Quick Panel"].exists)
        searchPanel.buttons["Search"].click()
        XCTAssertTrue(searchPanel.descendants(matching: .any).matching(identifier: "panel-active-mode").firstMatch.exists, "Narrow Search must retain the active collection")
        let search = searchPanel.textFields["Search Stow"]
        replaceSearch(search, with: "Ｐａｎｅｌ　Ｔｅｘｔ")
        XCTAssertTrue(searchFailureApp.staticTexts["Search unavailable — showing local matches"].waitForExistence(timeout: 3))
        XCTAssertTrue(searchPanel.buttons["Text, Panel Text"].exists, "Search failure should retain local matches")
        attach(searchPanel.screenshot(), named: "stow-panel-narrow-search-error")
        searchFailureApp.terminate()
    }

    func testGlobalQuickPanelShortcutFromAnotherApp() {
        let app = launchApp(extraArguments: ["--ui-testing-utility-mode", "--ui-testing-preserve-frontmost-application"])
        XCTAssertNotEqual(app.state, .notRunning)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertFalse(app.windows.firstMatch.exists, "Utility launch must not force the Library in front")
        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        textEdit.launch()
        textEdit.activate()

        let panel = app.windows["Stow Quick Panel"]
        for _ in 0..<3 where !panel.exists {
            textEdit.typeKey("v", modifierFlags: [.command, .shift])
            _ = panel.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(panel.exists, "The registered global shortcut must show Stow from another app")
        XCTAssertTrue(panel.buttons["Clipboard"].exists)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.apple.TextEdit", "The nonactivating panel must preserve the originating app")
        textEdit.windows.firstMatch.click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3), "A click in the already-active originating app must dismiss the panel")

        textEdit.terminate()
        app.terminate()
    }

    func testSensitiveClipboardMarkersAreExcludedBeforePayloadCapture() throws {
        let app = launchApp(extraArguments: ["--ui-testing-utility-mode"])
        XCTAssertNotEqual(app.state, .notRunning)
        Thread.sleep(forTimeInterval: 0.6)

        let token = "concealed-fixture-\(UUID().uuidString)"
        writeClipboardFixture(
            token,
            marker: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        )
        Thread.sleep(forTimeInterval: 0.8)

        app.activate()
        let fileMenu = app.menuBars.menuBarItems["File"]
        fileMenu.click()
        fileMenu.menus.menuItems["Quick Panel…"].click()
        let panel = app.windows["Stow Quick Panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        app.typeText(token)
        XCTAssertTrue(panel.staticTexts["No Results"].waitForExistence(timeout: 3))
        XCTAssertTrue(panel.descendants(matching: .any).matching(identifier: "panel-active-mode").firstMatch.waitForExistence(timeout: 2))
        panel.buttons["More"].click()
        panel.buttons["Open Library"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))

        let library = app.windows.matching(identifier: "stow-library-window").firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 3))
        let search = app.searchFields["Search saved content"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        replaceSearch(search, with: token)
        XCTAssertTrue(app.staticTexts["No Results"].waitForExistence(timeout: 3))

        let concealedSearch = try runCLI(["search", token, "--json"])
        let concealedMatches = try XCTUnwrap((concealedSearch["data"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertTrue(concealedMatches.isEmpty)

        writeClipboardFixture(token)
        XCTAssertTrue(app.staticTexts[token].waitForExistence(timeout: 5), "An ordinary fixture following the protected change must still be captured")
        let ordinarySearch = try runCLI(["search", token, "--json"])
        let ordinaryMatches = try XCTUnwrap((ordinarySearch["data"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(ordinaryMatches.count, 1)

        app.terminate()
    }

    func testClipboardDuplicateCoalescingAndTrashIsolation() throws {
        let app = launchApp(extraArguments: ["--ui-testing-utility-mode"])
        XCTAssertNotEqual(app.state, .notRunning)
        Thread.sleep(forTimeInterval: 0.6)

        let token = "duplicate-fixture-\(UUID().uuidString)"
        writeClipboardFixture(token)
        Thread.sleep(forTimeInterval: 0.8)
        let firstSearch = try runCLI(["search", token, "--json"])
        let firstMatches = try XCTUnwrap((firstSearch["data"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(firstMatches.count, 1)
        let originalID = try XCTUnwrap(firstMatches.first?["id"] as? String)

        writeClipboardFixture("older-\(token)")
        Thread.sleep(forTimeInterval: 0.8)
        writeClipboardFixture(token)
        Thread.sleep(forTimeInterval: 0.8)
        let recopySearch = try runCLI(["search", token, "--json"])
        let recopyMatches = try XCTUnwrap((recopySearch["data"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(recopyMatches.filter { ($0["title"] as? String) == token }.count, 1)
        XCTAssertEqual(recopyMatches.first { ($0["title"] as? String) == token }?["id"] as? String, originalID)

        app.activate()
        let fileMenu = app.menuBars.menuBarItems["File"]
        fileMenu.click()
        fileMenu.menus.menuItems["Quick Panel…"].click()
        let panel = app.windows["Stow Quick Panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        XCTAssertTrue(panel.buttons["Text, \(token)"].waitForExistence(timeout: 3), "Recopy must move the existing card to the front")
        panel.buttons["Text, \(token)"].click()
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(panel.staticTexts["Moved to Trash"].waitForExistence(timeout: 3))
        panel.buttons["Close Quick Panel"].click()

        writeClipboardFixture(token)
        Thread.sleep(forTimeInterval: 0.8)
        let afterTrashSearch = try runCLI(["search", token, "--status", "all", "--json"])
        let afterTrashMatches = try XCTUnwrap((afterTrashSearch["data"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(afterTrashMatches.filter { ($0["title"] as? String) == token }.count, 2, "Trash remains and a new Inbox item is created")
        XCTAssertEqual(afterTrashMatches.filter { ($0["status"] as? String) == "trashed" }.count, 1)
        XCTAssertEqual(afterTrashMatches.filter { ($0["status"] as? String) == "inbox" }.count, 1)

        app.terminate()
    }

    func testOriginalRichTextPlainTextAndImageRoundTrips() throws {
        let app = launchApp(extraArguments: ["--ui-testing-utility-mode"])
        XCTAssertNotEqual(app.state, .notRunning)
        Thread.sleep(forTimeInterval: 0.6)

        let richToken = "rich-fixture-\(UUID().uuidString)"
        let richItem = NSPasteboardItem()
        richItem.setString(richToken, forType: .string)
        richItem.setData(Data("{\\rtf1\\b \(richToken)}".utf8), forType: .rtf)
        richItem.setString("<b>\(richToken)</b>", forType: .html)
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.writeObjects([richItem]))
        Thread.sleep(forTimeInterval: 0.8)

        showPanel(in: app)
        let panel = app.windows["Stow Quick Panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        panel.buttons["Search"].click()
        var search = panel.textFields["Search Stow"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        replaceSearch(search, with: richToken)
        XCTAssertTrue(panel.buttons["Text, \(richToken)"].waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), richToken)
        XCTAssertEqual(NSPasteboard.general.data(forType: .rtf), Data("{\\rtf1\\b \(richToken)}".utf8))
        XCTAssertEqual(NSPasteboard.general.string(forType: .html), "<b>\(richToken)</b>")
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))

        showPanel(in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        panel.buttons["Search"].click()
        search = panel.textFields["Search Stow"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        replaceSearch(search, with: richToken)
        XCTAssertTrue(panel.buttons["Text, \(richToken)"].waitForExistence(timeout: 3))
        search.typeKey(.return, modifierFlags: .shift)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), richToken)
        XCTAssertNil(NSPasteboard.general.data(forType: .rtf))
        XCTAssertNil(NSPasteboard.general.data(forType: .html))

        let png = try XCTUnwrap(NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)?.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        let originalPNG = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let imageItem = NSPasteboardItem()
        imageItem.setData(originalPNG, forType: .png)
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.writeObjects([imageItem]))
        Thread.sleep(forTimeInterval: 0.8)
        showPanel(in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        panel.buttons["Search"].click()
        search = panel.textFields["Search Stow"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        replaceSearch(search, with: "Clipboard Image")
        XCTAssertTrue(panel.buttons["Image, Clipboard Image"].waitForExistence(timeout: 3))
        search.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(NSPasteboard.general.data(forType: .png), originalPNG)

        let imageID: String = try waitForCLIItemID(query: "Clipboard Image", type: "image")

        app.terminate()
    }

    func testImmediateSearchAndPasteFromTextEdit() {
        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        textEdit.launch()
        let editor = textEdit.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        clear(editor)

        let fallbackApp = launchApp(extraArguments: [
            "--ui-testing-utility-mode",
            "--ui-testing-preserve-frontmost-application",
        ])
        let fallbackPanel = fallbackApp.windows["Stow Quick Panel"]
        showPanel(from: textEdit, panel: fallbackPanel)
        XCTAssertTrue(fallbackPanel.staticTexts["Paste mode: Copy only"].waitForExistence(timeout: 2))
        fallbackApp.typeText("Panel Text")
        let fallbackSearch = fallbackPanel.textFields["Search Stow"]
        XCTAssertTrue(fallbackSearch.waitForExistence(timeout: 3), "Typing must open Search without a click")
        XCTAssertEqual(fallbackSearch.value as? String, "Panel Text", "The first typed character must be preserved exactly once")
        XCTAssertTrue(fallbackPanel.buttons["Text, Panel Text"].waitForExistence(timeout: 3))
        fallbackApp.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "panel text payload")
        XCTAssertTrue(fallbackPanel.staticTexts["Copied — paste with Command-V"].waitForExistence(timeout: 2))
        XCTAssertTrue(fallbackPanel.waitForNonExistence(timeout: 3))
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.apple.TextEdit")
        fallbackApp.terminate()

        clear(editor)
        let directApp = launchApp(extraArguments: [
            "--ui-testing-utility-mode",
            "--ui-testing-preserve-frontmost-application",
            "--ui-testing-force-direct-paste",
        ])
        let directPanel = directApp.windows["Stow Quick Panel"]
        showPanel(from: textEdit, panel: directPanel)
        XCTAssertTrue(directPanel.staticTexts["Paste mode: Direct"].waitForExistence(timeout: 2))
        directApp.typeText("Panel Text")
        let directSearch = directPanel.textFields["Search Stow"]
        XCTAssertTrue(directSearch.waitForExistence(timeout: 3))
        XCTAssertEqual(directSearch.value as? String, "Panel Text")
        directApp.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(directPanel.waitForNonExistence(timeout: 3))
        let pasted = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (editor.value as? String)?.contains("panel text payload") == true },
            object: editor
        )
        XCTAssertEqual(XCTWaiter.wait(for: [pasted], timeout: 5), .completed)

        directApp.terminate()
        textEdit.terminate()
    }

    func testCLILaunchesHostWithoutWindowsAndCompletesAgentSmokeFlow() throws {
        let app = XCUIApplication()
        app.terminate()
        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        textEdit.launch()
        textEdit.activate()
        XCTAssertTrue(textEdit.windows.firstMatch.waitForExistence(timeout: 5))

        let status = try runCLI(["status", "--json", "--timeout", "10"])
        XCTAssertEqual(status["ok"] as? Bool, true)
        XCTAssertNotEqual(app.state, .notRunning)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertFalse(app.windows.firstMatch.exists, "CLI launch must not present a Stow window")
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.apple.TextEdit", "CLI launch must preserve the frontmost app")
        app.terminate()

        let utilityApp = launchApp(extraArguments: ["--ui-testing-utility-mode", "--ui-testing-preserve-frontmost-application"])
        XCTAssertNotEqual(utilityApp.state, .notRunning)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertFalse(utilityApp.windows.firstMatch.exists)
        let requestID = UUID()
        let token = "agent-smoke-\(requestID.uuidString)"
        let addArguments = [
            "add", "--type", "code", "--title", "Agent Smoke", "--language", "swift",
            "--text", "let \(token) = true", "--request-id", requestID.uuidString, "--json",
        ]
        let firstAdd = try runCLI(addArguments)
        let secondAdd = try runCLI(addArguments)
        let firstItem = try XCTUnwrap((firstAdd["data"] as? [String: Any])?["item"] as? [String: Any])
        let secondItem = try XCTUnwrap((secondAdd["data"] as? [String: Any])?["item"] as? [String: Any])
        let itemID = try XCTUnwrap(firstItem["id"] as? String)
        XCTAssertEqual(secondItem["id"] as? String, itemID, "Retrying one request ID must not duplicate the item")

        let search = try runCLI(["search", token, "--type", "code", "--json"])
        let matches = try XCTUnwrap((search["data"] as? [String: Any])?["items"] as? [[String: Any]])
        XCTAssertEqual(matches.compactMap { $0["id"] as? String }, [itemID])
        let get = try runCLI(["get", itemID, "--json"])
        let fetched = try XCTUnwrap((get["data"] as? [String: Any])?["item"] as? [String: Any])
        XCTAssertEqual(fetched["text_content"] as? String, "let \(token) = true")

        let imageSearch = try runCLI(["search", "Panel Image", "--type", "image", "--json"])
        let imageMatches = try XCTUnwrap((imageSearch["data"] as? [String: Any])?["items"] as? [[String: Any]])
        let imageID = try XCTUnwrap(imageMatches.first?["id"] as? String)
        let imageGet = try runCLI(["get", imageID, "--json"])
        let imageItem = try XCTUnwrap((imageGet["data"] as? [String: Any])?["item"] as? [String: Any])
        let attachments = try XCTUnwrap(imageItem["attachments"] as? [[String: Any]])
        XCTAssertEqual(attachments.first?["content_type"] as? String, "image/png")
        let exported = try runCLI(["export", imageID, "--json"])
        let exportResult = try XCTUnwrap((exported["data"] as? [String: Any])?["export"] as? [String: Any])
        let exportPath = try XCTUnwrap(exportResult["path"] as? String)
        XCTAssertGreaterThan(try Data(contentsOf: URL(fileURLWithPath: exportPath)).count, 0)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.apple.TextEdit")

        textEdit.terminate()
        utilityApp.terminate()
    }

    func testQuickPanelCompactMode() {
        let app = launchApp(extraArguments: ["--ui-testing-panel-height=225"])
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        textEdit.launch()
        showPanel(in: app)
        let panel = app.windows["Stow Quick Panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(panel.frame.height, 250)
        XCTAssertGreaterThan(panel.frame.width, 700)
        XCTAssertTrue(panel.buttons["Clipboard"].exists)
        attach(panel.screenshot(), named: "stow-panel-compact")

        textEdit.terminate()
        app.terminate()
    }

    func testQuickPanelDarkModeAndReducedMotion() {
        let app = launchApp(extraArguments: ["-AppleInterfaceStyle", "Dark", "-NSReduceMotion", "YES"])
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        showPanel(in: app)
        let panel = app.windows["Stow Quick Panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.buttons["Clipboard"].exists)
        attach(panel.screenshot(), named: "stow-panel-dark-reduced-motion")
        app.terminate()
    }

    func testQuickPanelIncreaseContrastAndStatusSemantics() {
        let app = launchApp(
            extraArguments: ["--ui-testing-force-direct-paste", "-AppleIncreaseContrast", "YES"],
            monitoringEnabled: false
        )
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        textEdit.launch()
        textEdit.activate()

        let panel = app.windows["Stow Quick Panel"]
        for _ in 0..<3 where !panel.exists {
            textEdit.typeKey("v", modifierFlags: [.command, .shift])
            _ = panel.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(panel.exists)
        XCTAssertTrue(panel.staticTexts["Paste mode: Direct"].waitForExistence(timeout: 2))
        XCTAssertTrue(panel.staticTexts["Clipboard monitoring paused"].exists)
        XCTAssertTrue(panel.buttons["Close Quick Panel"].exists)
        attach(panel.screenshot(), named: "stow-panel-increase-contrast-direct-paused")

        textEdit.terminate()
        app.terminate()
    }

    func testLibraryAdaptiveWidthsEditingFailureAndTrashRecovery() {
        for (size, attachmentName) in [("840x560", "stow-library-minimum"), ("1080x720", "stow-library-normal"), ("1440x900", "stow-library-wide")] {
            let app = launchApp(extraArguments: [
                "--ui-testing-library-size=\(size)",
                "--ui-testing-library-long-content",
                "--ui-testing-fail-save"
            ])
            let library = app.windows.matching(identifier: "stow-library-window").firstMatch
            XCTAssertTrue(library.waitForExistence(timeout: 15))
            for identifier in ["library-filter-bar", "library-filter-menu", "library-storage-status", "library-quick-add"] {
                let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
                XCTAssertTrue(element.waitForExistence(timeout: 3), "Missing \(identifier) at \(size)")
                assertContained(element, in: library, message: "\(identifier) must not cross a Library boundary at \(size)")
            }
            XCTAssertTrue(app.staticTexts["A deliberately long Library title that must remain understandable at the minimum supported window width"].waitForExistence(timeout: 3))
            if size == "1440x900" { Thread.sleep(forTimeInterval: 6) }
            attach(library.screenshot(), named: attachmentName)

            if size == "1080x720" {
                app.staticTexts["A deliberately long Library title that must remain understandable at the minimum supported window width"].click()
                app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .shift)
                XCTAssertTrue(app.staticTexts["2 Items Selected"].waitForExistence(timeout: 3))
                XCTAssertTrue(app.buttons["Pin All"].exists)

                app.staticTexts["Panel Text"].firstMatch.click()
                let edit = app.buttons.matching(identifier: "library-edit-item").firstMatch
                XCTAssertTrue(edit.waitForExistence(timeout: 3))
                edit.click()
                let title = app.textFields.matching(identifier: "library-edit-title").firstMatch
                XCTAssertTrue(title.waitForExistence(timeout: 3))
                replaceSelectedText(in: title, with: "Draft retained after failure")
                app.buttons.matching(identifier: "library-save-changes").firstMatch.click()
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "library-edit-error").firstMatch.waitForExistence(timeout: 3))
                XCTAssertEqual(app.textFields.matching(identifier: "library-edit-title").firstMatch.value as? String, "Draft retained after failure")
                attach(library.screenshot(), named: "stow-library-edit-failure")
                app.buttons["Cancel"].click()
                let discardChanges = app.buttons["Discard Changes"]
                XCTAssertTrue(discardChanges.waitForExistence(timeout: 3))
                discardChanges.click()

                let panelText = app.staticTexts["Panel Text"].firstMatch
                XCTAssertTrue(panelText.waitForExistence(timeout: 3))
                panelText.click()
                var manageItem = app.descendants(matching: .any).matching(identifier: "library-manage-item").firstMatch
                XCTAssertTrue(manageItem.waitForExistence(timeout: 3))
                manageItem.click()
                app.menuItems["Move to Trash"].click()
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "library-feedback").firstMatch.waitForExistence(timeout: 3))
                app.staticTexts["Trash"].click()
                XCTAssertTrue(app.staticTexts["Panel Text"].waitForExistence(timeout: 3))
                app.staticTexts["Panel Text"].click()
                manageItem = app.descendants(matching: .any).matching(identifier: "library-manage-item").firstMatch
                XCTAssertTrue(manageItem.waitForExistence(timeout: 3))
                manageItem.click()
                XCTAssertTrue(app.menuItems["Restore"].exists)
                XCTAssertFalse(app.menuItems["Archive"].exists)
                app.menuItems["Restore"].click()
            }
            app.terminate()
        }
    }

    func testSettingsPagesWrapLongStatesAndPreserveRecoveryPaths() {
        let app = launchApp(extraArguments: [
            "--ui-testing-settings-size=620x500",
            "--ui-testing-settings-long-status",
            "--ui-testing-settings-accessibility-denied",
            "--ui-testing-settings-sync-paused",
            "--ui-testing-fail-shortcut-registration",
            "--ui-testing-fail-search-index-rebuild"
        ])
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        openSettings(in: app)
        let settings = app.windows.matching(identifier: "stow-settings-window").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        selectSettingsPage("Capture", in: app)
        let clipboardStatus = app.staticTexts["Clipboard access needs attention in System Settings before automatic background capture can resume reliably."]
        XCTAssertTrue(clipboardStatus.waitForExistence(timeout: 3))
        assertContained(clipboardStatus, in: settings, message: "Clipboard recovery status must wrap inside Settings")
        attach(settings.screenshot(), named: "stow-settings-capture-minimum")

        selectSettingsPage("Paste & Shortcuts", in: app)
        XCTAssertTrue(app.staticTexts["Copy-only fallback"].waitForExistence(timeout: 3))
        let shortcutStatus = app.descendants(matching: .any).matching(identifier: "settings-global-shortcut-status").firstMatch
        XCTAssertTrue(shortcutStatus.waitForExistence(timeout: 3))
        assertContained(shortcutStatus, in: settings, message: "Shortcut conflict status must wrap inside Settings")
        let quickAddPicker = app.descendants(matching: .any).matching(identifier: "settings-quick-add-shortcut").firstMatch
        XCTAssertTrue(quickAddPicker.waitForExistence(timeout: 3))
        let previousShortcut = quickAddPicker.value as? String
        quickAddPicker.click()
        app.menuItems["⌃⌥S"].click()
        app.buttons.matching(identifier: "settings-apply-shortcuts").firstMatch.click()
        let shortcutFeedback = app.descendants(matching: .any).matching(identifier: "settings-shortcut-feedback").firstMatch
        XCTAssertTrue(shortcutFeedback.waitForExistence(timeout: 3))
        app.scrollViews["settings-paste-shortcuts-page"].scroll(byDeltaX: 0, deltaY: -240)
        assertContained(shortcutFeedback, in: settings, message: "Shortcut recovery feedback must remain visible inside Settings")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "settings-quick-add-shortcut").firstMatch.value as? String, previousShortcut)
        attach(settings.screenshot(), named: "stow-settings-shortcuts-conflict")

        selectSettingsPage("Sync & Storage", in: app)
        XCTAssertTrue(app.staticTexts["Sync paused"].waitForExistence(timeout: 3))
        let rebuild = app.buttons.matching(identifier: "settings-rebuild-search-index").firstMatch
        XCTAssertTrue(rebuild.waitForExistence(timeout: 3))
        rebuild.click()
        let searchIndexError = app.descendants(matching: .any).matching(identifier: "settings-search-index-error").firstMatch
        XCTAssertTrue(searchIndexError.waitForExistence(timeout: 3))
        let dismissSearchError = app.buttons["Dismiss"].firstMatch
        XCTAssertTrue(dismissSearchError.waitForExistence(timeout: 3))
        app.scrollViews["settings-sync-storage-page"].scroll(byDeltaX: 0, deltaY: -240)
        assertContained(searchIndexError, in: settings, message: "Search recovery feedback must remain visible inside Settings")
        assertContained(dismissSearchError, in: settings, message: "Search recovery action must remain visible inside Settings")
        attach(settings.screenshot(), named: "stow-settings-sync-search-failure")

        selectSettingsPage("Privacy", in: app)
        XCTAssertTrue(app.checkBoxes["Anonymous on-device product metrics"].exists || app.switches["Anonymous on-device product metrics"].exists)
        app.terminate()

        let appearanceApp = launchApp(extraArguments: [
            "--ui-testing-settings-size=680x520",
            "-AppleInterfaceStyle", "Dark",
            "--ui-testing-force-dark",
            "-NSReduceMotion", "YES",
            "-AppleIncreaseContrast", "YES"
        ])
        XCTAssertTrue(appearanceApp.windows.firstMatch.waitForExistence(timeout: 15))
        openSettings(in: appearanceApp)
        let appearanceSettings = appearanceApp.windows.matching(identifier: "stow-settings-window").firstMatch
        XCTAssertTrue(appearanceSettings.waitForExistence(timeout: 5))
        selectSettingsPage("Privacy", in: appearanceApp)
        attach(appearanceSettings.screenshot(), named: "stow-settings-dark-contrast-reduced-motion")
        appearanceApp.terminate()
    }

    private func launchApp(extraArguments: [String] = [], monitoringEnabled: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-seed-panel",
            "--ui-testing-disable-direct-paste",
            "-ApplePersistenceIgnoreState", "YES",
            "-clipboardMonitoringEnabled", monitoringEnabled ? "YES" : "NO"
        ] + extraArguments
        app.launch()
        return app
    }

    private func cliHelperURL() throws -> URL {
        var directory = Bundle(for: StowMacUITests.self).bundleURL
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("Stow-macOS.app/Contents/Helpers/stow")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "StowMacUITests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate the embedded Stow CLI helper."]
        )
    }

    private func waitForCLIItemID(query: String, type: String, timeout: TimeInterval = 5) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let response = try runCLI(["search", query, "--type", type, "--timeout", "30", "--json"])
            if let items = (response["data"] as? [String: Any])?["items"] as? [[String: Any]],
               let id = items.first?["id"] as? String {
                return id
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        throw NSError(
            domain: "StowMacUITests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for a \(type) item matching \(query)."]
        )
    }

    private func runCLI(_ arguments: [String]) throws -> [String: Any] {
        let process = Process()
        process.executableURL = try cliHelperURL()
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "StowMacUITests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(decoding: error + output, as: UTF8.self)]
            )
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
    }

    private func showPanel(in app: XCUIApplication) {
        app.activate()
        let fileMenu = app.menuBars.menuBarItems["File"]
        fileMenu.click()
        fileMenu.menus.menuItems["Quick Panel…"].click()
    }

    private func showPanel(from origin: XCUIApplication, panel: XCUIElement) {
        origin.activate()
        for _ in 0..<3 where !panel.exists {
            origin.typeKey("v", modifierFlags: [.command, .shift])
            _ = panel.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(panel.exists, "The global shortcut must open the panel from the originating app")
    }

    private func clear(_ textView: XCUIElement) {
        textView.click()
        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey(.delete, modifierFlags: [])
    }

    private func writeClipboardFixture(
        _ value: String,
        marker: NSPasteboard.PasteboardType? = nil
    ) {
        let item = NSPasteboardItem()
        item.setString(value, forType: .string)
        if let marker { item.setString("1", forType: marker) }
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.writeObjects([item]))
    }

    private func openSettings(in app: XCUIApplication) {
        app.activate()
        let appMenu = app.menuBars.menuBarItems["Stow"]
        appMenu.click()
        appMenu.menus.menuItems["Settings…"].click()
    }

    private func selectSettingsPage(_ title: String, in app: XCUIApplication) {
        let button = app.buttons[title]
        if button.exists { button.click(); return }
        let radio = app.radioButtons[title]
        XCTAssertTrue(radio.waitForExistence(timeout: 3), "Missing Settings page \(title)")
        radio.click()
    }

    private func assertContained(_ element: XCUIElement, in window: XCUIElement, message: String) {
        let elementFrame = element.frame
        let windowFrame = window.frame
        XCTAssertGreaterThanOrEqual(elementFrame.minX, windowFrame.minX - 1, message)
        XCTAssertGreaterThanOrEqual(elementFrame.minY, windowFrame.minY - 1, message)
        XCTAssertLessThanOrEqual(elementFrame.maxX, windowFrame.maxX + 1, message)
        XCTAssertLessThanOrEqual(elementFrame.maxY, windowFrame.maxY + 1, message)
    }

    private func requestQuickAdd(in app: XCUIApplication) {
        app.activate()
        let fileMenu = app.menuBars.menuBarItems["File"]
        fileMenu.click()
        fileMenu.menus.menuItems["Quick Add…"].click()
    }

    private func confirmationButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let identifier = title == "Keep Editing" ? "panel-keep-editing" : "panel-confirm-discard"
        return app.buttons.matching(identifier: identifier).firstMatch
    }

    private func openCodeEditor(in panel: XCUIElement, app: XCUIApplication) {
        panel.buttons["Search"].click()
        let search = panel.textFields["Search Stow"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        replaceSearch(search, with: "Panel Code")
        let codeCard = panel.buttons["Code, Panel Code"]
        XCTAssertTrue(codeCard.waitForExistence(timeout: 3))
        codeCard.click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Edit Item"].waitForExistence(timeout: 3))
    }

    private func replaceSearch(_ search: XCUIElement, with value: String) {
        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        search.typeText(value)
    }

    private func replaceSelectedText(in field: XCUIElement, with value: String) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
