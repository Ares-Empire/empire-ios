import XCTest

/// Settings → Language on the real screens: the confirmation, Cancel, and Restart, which rebuilds the app in the other
/// language with Settings closed (Shared/Language/AppRoot.swift). Sample data; the app starts in German.
nonisolated final class LanguageSwitchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func testRestartsInEnglishAndBackInGerman() {
        let app = launchInGerman()
        openLanguage(settings: "Einstellungen", row: "Sprache", in: app)
        row("Deutsch", in: app).tap()                // the language shown: saved without a question
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 1))

        row("English", in: app).tap()
        let english = app.alerts["Switch to English?"]
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        XCTAssertTrue(english.staticTexts["Aresus restarts in English."].exists)
        XCTAssertTrue(english.buttons["Abbrechen"].exists)          // Cancel in the language shown now
        english.buttons["Restart"].tap()

        XCTAssertTrue(text("checked", in: app).waitForExistence(timeout: 15), "the main screen in English")
        XCTAssertFalse(text("geprüft", in: app).exists)
        XCTAssertFalse(app.navigationBars["Language"].exists, "Settings closed")
        XCTAssertFalse(app.navigationBars["Sprache"].exists)
        keepScreenshot("after the switch to English", of: app)
        // Aresync: a plural and the days, in English too.
        app.buttons["Aresync"].tap()
        XCTAssertTrue(text("quiet runs", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(text("YESTERDAY", in: app).exists || text("Yesterday", in: app).exists)
        XCTAssertFalse(text("ruhige Läufe", in: app).exists)
        keepScreenshot("Aresync after the switch to English", of: app)
        app.buttons["Aresus"].tap()

        openLanguage(settings: "Settings", row: "Language", in: app)
        row("Deutsch", in: app).tap()
        let german = app.alerts["Auf Deutsch umstellen?"]
        XCTAssertTrue(german.waitForExistence(timeout: 5))
        XCTAssertTrue(german.staticTexts["Aresus startet auf Deutsch neu."].exists)
        XCTAssertTrue(german.buttons["Cancel"].exists)
        german.buttons["Neu starten"].tap()

        XCTAssertTrue(text("geprüft", in: app).waitForExistence(timeout: 15), "the main screen in German again")
        XCTAssertFalse(text("checked", in: app).exists)
        XCTAssertFalse(app.navigationBars["Sprache"].exists, "Settings closed")
        app.buttons["Aresync"].tap()
        XCTAssertTrue(text("ruhige Läufe", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(text("quiet runs", in: app).exists)
        keepScreenshot("Aresync after the switch back to German", of: app)
    }

    @MainActor func testCancelKeepsTheLanguageAndThePage() {
        let app = launchInGerman()
        openLanguage(settings: "Einstellungen", row: "Sprache", in: app)
        row("Deutsch", in: app).tap()
        row("English", in: app).tap()
        let alert = app.alerts["Switch to English?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Abbrechen"].tap()

        XCTAssertFalse(alert.waitForExistence(timeout: 1))
        XCTAssertTrue(app.navigationBars["Sprache"].exists, "still on the page, still in German")
        XCTAssertTrue(row("Deutsch", in: app).isSelected)
        XCTAssertFalse(row("English", in: app).isSelected)
    }

    // MARK: helpers

    @MainActor private func launchInGerman() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(text("geprüft", in: app).waitForExistence(timeout: 15), "the main screen in German")
        return app
    }

    @MainActor private func openLanguage(settings: String, row title: String, in app: XCUIApplication) {
        let gear = app.buttons[settings]
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        gear.tap()
        let language = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        language.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }

    /// A screenshot kept in the result bundle (`xcrun xcresulttool export attachments`), for the eyes.
    @MainActor private func keepScreenshot(_ name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func row(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    @MainActor private func text(_ part: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }
}
