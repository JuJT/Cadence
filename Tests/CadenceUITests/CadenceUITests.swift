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
        capture(app, name: "ipad-accueil-paysage")
        courses.tap()
        XCTAssertTrue(app.navigationBars["Cours"].waitForExistence(timeout: 4))
        capture(app, name: "ipad-cours-paysage")
        let statistics = app.buttons["Statistiques"].firstMatch
        XCTAssertTrue(statistics.waitForExistence(timeout: 4))
        statistics.tap()
        XCTAssertTrue(app.navigationBars["Statistiques"].waitForExistence(timeout: 4))
        capture(app, name: "ipad-statistiques-paysage")
    }

    @MainActor
    func testDarkStatistics() throws {
        // La CI applique le mode sombre au simulateur avant ce test séparé.
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let stats = app.tabBars.buttons["Statistiques"]
        XCTAssertTrue(stats.waitForExistence(timeout: 8))
        stats.tap()
        XCTAssertTrue(app.navigationBars["Statistiques"].waitForExistence(timeout: 4))
        capture(app, name: "statistiques-sombre")
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
        capture(app, name: "accueil-clair")
        tabs.buttons["Cours"].tap()
        XCTAssertTrue(app.navigationBars["Cours"].waitForExistence(timeout: 3))
        capture(app, name: "cours-clair")
        tabs.buttons["Révision"].tap()
        XCTAssertTrue(app.navigationBars["Révision"].waitForExistence(timeout: 3))
        capture(app, name: "revision-clair")
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
        capture(app, name: "revision-active")
        app.buttons["session.finish"].tap()
        let finish = app.buttons["Terminer et enregistrer"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        finish.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        tabs.buttons["Statistiques"].tap()
        XCTAssertTrue(app.navigationBars["Statistiques"].waitForExistence(timeout: 3))
        capture(app, name: "statistiques-clair")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
