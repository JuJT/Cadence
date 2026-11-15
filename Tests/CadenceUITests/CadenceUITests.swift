import XCTest

final class CadenceUITests: XCTestCase {
    @MainActor
    func testCourseDateNavigationAndSubjectNames() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-courses"]
        app.launch()
        app.tabBars.buttons["Cours"].tap()
        let previous = app.buttons["courses.previous"]
        let next = app.buttons["courses.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Jour"].tap()
        XCTAssertTrue(app.staticTexts["Français"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["FRANCAIS - PROF. EXEMPLE"].exists)
        next.tap()
        XCTAssertTrue(app.staticTexts["Anglais"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Français"].exists)
        XCTAssertFalse(app.staticTexts["ANGLAIS - PROF. EXEMPLE - [GROUPE-TEST]"].exists)
        capture(app, name: "cours-jour-matiere")
        previous.tap()
        XCTAssertTrue(app.staticTexts["Français"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Anglais"].exists)
        app.segmentedControls.buttons["Semaine"].tap()
        XCTAssertTrue(app.staticTexts["Français"].waitForExistence(timeout: 3))
        next.tap()
        XCTAssertTrue(app.staticTexts["SVT"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Français"].exists)
        previous.tap()
        XCTAssertTrue(app.staticTexts["Français"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testNewSessionSheetAndCancellation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let choice = app.buttons["session.new"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        let revision = app.buttons["session.choose.revision"]
        XCTAssertTrue(revision.waitForExistence(timeout: 4))
        XCTAssertGreaterThan(revision.frame.midY, app.windows.firstMatch.frame.height * 0.4)
        // Une feuille contient le choix ; aucune bulle de confirmation ancrée.
        XCTAssertEqual(app.alerts.count, 0)
        capture(app, name: "nouvelle-seance-feuille")
        revision.tap()
        let start = app.buttons["Démarrer"]
        guard start.waitForExistence(timeout: 5) else {
            capture(app, name: "echec-ouverture-formulaire")
            XCTFail("Le choix Révision doit ouvrir le formulaire de nouvelle séance.")
            return
        }
        capture(app, name: "nouvelle-seance-formulaire")
        start.tap()
        XCTAssertTrue(app.buttons["session.pause"].waitForExistence(timeout: 4))
        app.buttons["session.finish"].tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        capture(app, name: "terminer-seance-alerte")
        confirmation.buttons["Annuler"].tap()
        XCTAssertTrue(app.buttons["session.pause"].waitForExistence(timeout: 3))
        app.buttons["session.finish"].tap()
        app.alerts.buttons["Terminer et enregistrer"].tap()
        XCTAssertTrue(app.buttons["session.start"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testIPadLandscapeLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        guard app.windows.firstMatch.frame.height > 600 else {
            throw XCTSkip("Ce scénario vérifie uniquement la navigation iPad.")
        }
        let window = app.windows.firstMatch
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            window.exists && window.frame.width > window.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 15), .completed)
        let courses = app.buttons["Cours"].firstMatch
        XCTAssertTrue(courses.waitForExistence(timeout: 8))
        captureIPad(app, name: "ipad-accueil-paysage")
        courses.tap()
        XCTAssertTrue(app.navigationBars["Cours"].waitForExistence(timeout: 4))
        captureIPad(app, name: "ipad-cours-paysage")
        let statistics = app.buttons["Statistiques"].firstMatch
        XCTAssertTrue(statistics.waitForExistence(timeout: 4))
        statistics.tap()
        XCTAssertTrue(app.navigationBars["Statistiques"].waitForExistence(timeout: 4))
        captureIPad(app, name: "ipad-statistiques-paysage")
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

    @MainActor
    private func captureIPad(_ app: XCUIApplication, name: String) {
        // La capture de fenêtre peut être recadrée selon les anciennes bornes
        // portrait par XCTest. L'écran complet conserve le paysage réel.
        let screen = XCUIScreen.main.screenshot()
        XCTAssertGreaterThan(screen.image.size.width, screen.image.size.height)
        let diagnostic = XCTAttachment(string: "Fenêtre : \(app.windows.firstMatch.frame)\nÉcran : \(screen.image.size)\nOrientation : \(XCUIDevice.shared.orientation)")
        diagnostic.name = name + "-dimensions"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        let screenshot = XCTAttachment(screenshot: screen)
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
