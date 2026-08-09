import AppKit
import XCTest

@MainActor
final class StowMacUITests: XCTestCase {
    func testMainWindowQuickPanelAndQuickAdd() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-seed-panel", "-ApplePersistenceIgnoreState", "YES", "-clipboardMonitoringEnabled", "YES"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        for section in ["Inbox", "Recent", "Pinned", "Archive", "Trash", "Settings"] {
            XCTAssertTrue(app.staticTexts[section].waitForExistence(timeout: 3), "Missing \(section)")
        }
        app.activate()
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "stow-mac-library"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.cells.containing(.staticText, identifier: "Settings").firstMatch.click()
        XCTAssertTrue(app.staticTexts["Registered"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Access"].waitForExistence(timeout: 3))
        app.cells.containing(.staticText, identifier: "Inbox").firstMatch.click()

        let textEdit = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        textEdit.launch()
        textEdit.typeKey("v", modifierFlags: [.command, .shift])
        var search = app.textFields["Search Stow"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))

        replaceSearch(search, with: "Panel Text")
        search.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "panel text payload")

        replaceSearch(search, with: "Panel Code")
        app.typeKey("c", modifierFlags: .command)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "let panel = true")
        app.typeKey("a", modifierFlags: [.command, .shift])
        app.cells.containing(.staticText, identifier: "Archive").firstMatch.click()
        XCTAssertTrue(app.staticTexts["Panel Code"].waitForExistence(timeout: 3))

        app.typeKey("v", modifierFlags: [.command, .shift])
        search = app.textFields["Search Stow"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        replaceSearch(search, with: "Panel Image")
        app.typeKey("c", modifierFlags: .command)
        XCTAssertTrue(NSPasteboard.general.canReadObject(forClasses: [NSImage.self]))

        textEdit.activate()
        textEdit.typeKey("s", modifierFlags: [.option, .shift])
        XCTAssertTrue(app.staticTexts["Quick Add"].waitForExistence(timeout: 3) || app.textViews["Content"].waitForExistence(timeout: 3))
        textEdit.terminate()
        app.terminate()
    }

    private func replaceSearch(_ search: XCUIElement, with value: String) {
        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        search.typeText(value)
    }
}
