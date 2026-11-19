import XCTest

final class IntroductionUITests: XCTestCase {
    @MainActor
    func testSetupKeepsItsPlaceWhenPronoteConnectionIsCancelled() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-onboarding", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        XCTAssertTrue(app.buttons["intro.continue"].waitForExistence(timeout: 5))
        capture("installation-bienvenue")
        app.buttons["intro.continue"].tap()
        XCTAssertTrue(app.buttons["intro.connect"].waitForExistence(timeout: 3))
        app.buttons["intro.connect"].tap()
        XCTAssertTrue(app.navigationBars["Connexion PRONOTE"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.alerts.count, 0) // No GPS or login request merely by opening setup.
        app.buttons["Terminé"].tap()
        XCTAssertTrue(app.buttons["intro.connect"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["intro.skip"].exists)
        capture("installation-connexion-pronote")
        app.buttons["intro.skip"].tap()
        XCTAssertTrue(app.buttons["intro.finish"].waitForExistence(timeout: 3))
        capture("installation-prete")
        app.buttons["intro.finish"].tap()
        XCTAssertTrue(app.tabBars.buttons["Révision"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["intro.finish"].exists)
    }

    @MainActor
    func testUpdateShowsItsPagesWithoutRequiringAConnection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-whats-new", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        XCTAssertTrue(app.buttons["intro.continue"].waitForExistence(timeout: 5))
        capture("nouveautes-scolarite")
        app.buttons["intro.continue"].tap()
        capture("nouveautes-devoirs")
        app.buttons["intro.previous"].tap()
        XCTAssertTrue(app.buttons["intro.continue"].exists)
        app.buttons["intro.continue"].tap()
        app.buttons["intro.continue"].tap()
        XCTAssertTrue(app.buttons["intro.finish"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["intro.connect"].exists)
        capture("nouveautes-experience")
        app.buttons["intro.finish"].tap()
        XCTAssertTrue(app.tabBars.buttons["Devoirs"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["intro.finish"].exists)
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
