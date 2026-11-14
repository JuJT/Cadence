import XCTest

final class CadenceUITests: XCTestCase {
    @MainActor
    func testIPadLandscapeLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        guard app.windows.firstMatch.frame.width > 600 else {
            throw XCTSkip("Ce scénario vérifie uniquement la navigation iPad.")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let courses = app.buttons["Cours"].firstMatch
        XCTAssertTrue(courses.waitForExistence(timeout: 8))
        courses.tap()
        XCTAssertTrue(app.navigationBars["Cours"].waitForExistence(timeout: 4))
        let statistics = app.buttons["Statistiques"].firstMatch
        XCTAssertTrue(statistics.waitForExistence(timeout: 4))
        statistics.tap()
        XCTAssertTrue(app.navigationBars["Statistiques"].waitForExistence(timeout: 4))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Cadence — iPad paysage"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testManualNavigationWithoutCalendarPermission() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let continueButton = app.buttons["Continuer"]
        if continueButton.waitForExistence(timeout: 8) {
            continueButton.tap()
            let skipCalendar = app.buttons["Commencer sans calendrier"]
            XCTAssertTrue(skipCalendar.waitForExistence(timeout: 3))
            skipCalendar.tap()
        }
        let tabs = app.tabBars
        XCTAssertTrue(tabs.buttons["Cours"].waitForExistence(timeout: 8))
        tabs.buttons["Cours"].tap()
        XCTAssertTrue(app.navigationBars["Cours"].waitForExistence(timeout: 3))
        tabs.buttons["Révision"].tap()
        XCTAssertTrue(app.navigationBars["Révision"].waitForExistence(timeout: 3))
        let start = app.buttons["session.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.tap()
        let pause = app.buttons["session.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        pause.tap()
        let resume = app.buttons["session.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        let activeScreenshot = XCTAttachment(screenshot: app.screenshot())
        activeScreenshot.name = "Cadence — Révision en cours"
        activeScreenshot.lifetime = .keepAlways
        add(activeScreenshot)
        app.buttons["session.finish"].tap()
        let finish = app.buttons["Terminer et enregistrer"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        finish.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Cadence — Révision native"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        tabs.buttons["Statistiques"].tap()
        XCTAssertTrue(app.navigationBars["Statistiques"].waitForExistence(timeout: 3))
    }
}
