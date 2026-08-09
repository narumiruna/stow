import AppKit
import XCTest

@MainActor
final class StowMacUITests: XCTestCase {
    func testLibraryAndPasteInspiredQuickPanelWorkflow() {
        let app = launchApp()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        for section in ["Inbox", "Recent", "Pinned", "Archive", "Trash", "Settings"] {
            XCTAssertTrue(app.staticTexts[section].waitForExistence(timeout: 3), "Missing \(section)")
        }
        attach(app.windows.firstMatch.screenshot(), named: "stow-mac-library")

        app.cells.containing(.staticText, identifier: "Settings").firstMatch.click()
        XCTAssertTrue(app.staticTexts["Registered"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Access"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Copy-only fallback"].exists || app.staticTexts["Granted"].exists)
        app.cells.containing(.staticText, identifier: "Inbox").firstMatch.click()

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
        attach(panel.screenshot(), named: "stow-panel-normal")

        let searchButton = panel.buttons["Search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 3))
        searchButton.click()
        var search = panel.textFields["Search Stow"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        attach(panel.screenshot(), named: "stow-panel-search")
        let filters = panel.menuButtons["Search Filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 2))
        filters.click()
        app.menuItems["Images"].click()
        XCTAssertTrue(panel.buttons["Remove Image filter"].waitForExistence(timeout: 2))
        attach(panel.screenshot(), named: "stow-panel-filter-token")
        panel.buttons["Remove Image filter"].click()

        replaceSearch(search, with: "Panel Text")
        search.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "panel text payload")
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
        panel.menuButtons["More"].click()
        app.menuItems["Archive"].firstMatch.click()
        XCTAssertTrue(panel.buttons["Code, Panel Code"].waitForExistence(timeout: 3))
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

        showQuickAdd(in: app)
        XCTAssertTrue(app.staticTexts["Quick Add"].waitForExistence(timeout: 3) || app.textViews["Content"].waitForExistence(timeout: 3))
        textEdit.terminate()
        app.terminate()
    }

    func testGlobalQuickPanelShortcutFromAnotherApp() {
        let app = launchApp(extraArguments: ["--ui-testing-utility-mode"])
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

        textEdit.terminate()
        app.terminate()
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

    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-seed-panel",
            "--ui-testing-disable-direct-paste",
            "-ApplePersistenceIgnoreState", "YES",
            "-clipboardMonitoringEnabled", "YES"
        ] + extraArguments
        app.launch()
        return app
    }

    private func showPanel(in app: XCUIApplication) {
        app.activate()
        let fileMenu = app.menuBars.menuBarItems["File"]
        fileMenu.click()
        fileMenu.menus.menuItems["Quick Panel…"].click()
    }

    private func showQuickAdd(in app: XCUIApplication) {
        app.activate()
        let fileMenu = app.menuBars.menuBarItems["File"]
        fileMenu.click()
        fileMenu.menus.menuItems["Quick Add…"].click()
    }

    private func replaceSearch(_ search: XCUIElement, with value: String) {
        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        search.typeText(value)
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
