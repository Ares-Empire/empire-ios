import XCTest

/// Coordinates are resolved before measurement: querying Aresium's accessibility tree can itself hold its main thread.
/// Gestures use SpringBoard's screen coordinate space, so dispatch does not snapshot Aresium again inside the window.
nonisolated final class SettingsTimingUITests: XCTestCase {
    @MainActor func testSettings() throws {
        continueAfterFailure = false
        let size = ProcessInfo.processInfo.environment["SETTINGS_SIZE"] ?? "1250"
        let app = XCUIApplication(bundleIdentifier: "de.ares-empire.aresium")
        let screen = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launchArguments = ["-samplePhone", "-sampleSize", size, "-settingsTimings", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 60))
        Thread.sleep(forTimeInterval: 3)
        func row(_ title: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        }
        func step(_ name: String, _ action: () -> Void) {
            Thread.sleep(forTimeInterval: 0.15) // Let the preceding accessibility lookup return to idle.
            let start = Date().timeIntervalSince1970
            action()
            Thread.sleep(forTimeInterval: 1)
            print("SETTINGS_STEP size=\(size) step=\(name) start=\(start) end=\(Date().timeIntervalSince1970)")
        }
        func point(_ frame: CGRect) -> XCUICoordinate {
            screen.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        }
        func tap(_ name: String, _ element: XCUIElement) {
            var frame = element.frame // Outside the measured window.
            if element.elementType == .switch {
                frame.origin.x = frame.maxX - 30 // The native switch, rather than blank space beside its label.
                frame.size.width = 1
            }
            let target = point(frame)
            step(name) { target.tap() }
        }
        func swipe(_ name: String, up: Bool) {
            let start = screen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.78 : 0.28))
            let end = screen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.28 : 0.78))
            step(name) { start.press(forDuration: 0.05, thenDragTo: end) }
        }
        func reveal(_ element: XCUIElement, up: Bool = true, measured: String? = nil) {
            for _ in 0..<8 {
                if !element.exists {
                    if let measured { swipe(measured, up: up) }
                    else if up { app.swipeUp() } else { app.swipeDown() }
                    continue
                }
                // isHittable can be true for a row partly behind the navigation bar; its centre must be visible.
                let frame = element.frame
                let top = app.navigationBars.firstMatch.frame.maxY + 4
                let bottom = app.frame.maxY - 36
                if element.isHittable && frame.minY >= top && frame.maxY <= bottom { return }
                let direction = frame.minY < top ? false : (frame.maxY > bottom ? true : up)
                if let measured { swipe(measured, up: direction) }
                else if direction { app.swipeUp() } else { app.swipeDown() }
            }
            XCTAssertTrue(element.isHittable)
        }
        func page(_ title: String, _ label: String? = nil, up: Bool = true) {
            reveal(row(label ?? title), up: up)
            let suffix = title.replacingOccurrences(of: " ", with: "_")
            tap("open-" + suffix, row(label ?? title))
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            tap("close-" + suffix, app.navigationBars.buttons.firstMatch)
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        }
        func flip(_ name: String, _ element: XCUIElement) {
            let old = element.value as? String
            tap(name, element)
            XCTAssertNotEqual(element.value as? String, old)
        }
        tap("open", app.buttons["Settings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        for _ in 0..<4 { swipe("scroll-end", up: true) }
        reveal(row("Categories"), up: false, measured: "scroll-back")
        if ProcessInfo.processInfo.environment["SETTINGS_PROFILE"] == "1" { return }
        page("Receipts")
        page("Messages", "Reminder and review")
        reveal(row("Reminder and review"), up: false)
        row("Reminder and review").tap()
        let master = app.switches.matching(NSPredicate(format: "label == %@", "Messages")).firstMatch
        let reminder = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Import reminder")).firstMatch
        let review = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Month review")).firstMatch
        flip("Messages-on", master)
        flip("Import-reminder-off", reminder)
        flip("Import-reminder-on", reminder)
        flip("Month-review-off", review)
        flip("Month-review-on", review)
        flip("Messages-off", master)
        app.navigationBars.buttons.firstMatch.tap()
        page("Own code")
        let names = app.switches["ownNames"]
        reveal(names, up: false)
        flip("Own-names-off", names)
        flip("Own-names-on", names)
        let graph = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Graph")).firstMatch
        reveal(graph)
        flip("Graph-off", graph)
        flip("Graph-on", graph)
        let sums = app.switches["sumEverywhere"]
        reveal(sums)
        flip("Add-up-on", sums)
        flip("Add-up-off", sums)
        page("Language")
        page("Appearance")
        reveal(row("Fonts & licences"))
        page("Fonts & licences")
        let face = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Lock with Face ID")).firstMatch
        reveal(face, up: false)
        if face.isEnabled {
            var frame = face.frame
            frame.origin.x = frame.maxX - 30
            frame.size.width = 1
            let target = point(frame)
            step("Face-ID-cancel") {
                target.tap()
                Thread.sleep(forTimeInterval: 1)
                screen.coordinate(withNormalizedOffset: CGVector(dx: 0.09, dy: 0.115)).tap()
            }
        }
        tap("close", app.buttons["Done"])
        app.buttons["Settings"].tap()
        page("Categories", up: false)
        app.buttons["Done"].tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
