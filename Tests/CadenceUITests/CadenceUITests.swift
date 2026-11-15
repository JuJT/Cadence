import XCTest

final class CadenceUITests: XCTestCase {
    @MainActor
    func testCourseDateNavigationAndSubjectNames() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["--uitesting-courses"])
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
        app.launchArguments = testArguments()
        app.launch()
        let choice = app.buttons["session.new"]
        tap(choice, in: app)
        let revision = app.buttons["session.choose.revision"]
        XCTAssertTrue(revision.waitForExistence(timeout: 4))
        XCTAssertTrue(revision.isHittable)
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
        tap(start, in: app)
        XCTAssertTrue(app.buttons["session.pause"].waitForExistence(timeout: 4))
        tap(app.buttons["session.finish"], in: app)
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        capture(app, name: "terminer-seance-alerte")
        confirmation.buttons["Annuler"].tap()
        XCTAssertTrue(app.buttons["session.pause"].waitForExistence(timeout: 3))
        tap(app.buttons["session.finish"], in: app)
        app.alerts.buttons["Terminer et enregistrer"].tap()
        XCTAssertTrue(reveal(app.buttons["session.start"], in: app))
    }

    @MainActor
    func testDarkStatistics() throws {
        // La CI applique le mode sombre au simulateur avant ce test séparé.
        let app = XCUIApplication()
        app.launchArguments = testArguments()
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
        app.launchArguments = testArguments()
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
        XCTAssertTrue(app.navigationBars["Emploi du temps"].waitForExistence(timeout: 3))
        capture(app, name: "cours-clair")
        tabs.buttons["Révision"].tap()
        XCTAssertTrue(app.navigationBars["Révision"].waitForExistence(timeout: 3))
        capture(app, name: "revision-clair")
        let start = app.buttons["session.start"]
        tap(start, in: app)
        let pause = app.buttons["session.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        tap(pause, in: app)
        let resume = app.buttons["session.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        tap(resume, in: app)
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        scrollToTop(app)
        capture(app, name: "revision-active")
        tap(app.buttons["session.finish"], in: app)
        let finish = app.buttons["Terminer et enregistrer"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        finish.tap()
        XCTAssertTrue(reveal(start, in: app))
        tabs.buttons["Statistiques"].tap()
        XCTAssertTrue(app.navigationBars["Statistiques"].waitForExistence(timeout: 3))
        capture(app, name: "statistiques-clair")
    }

    @MainActor
    func testShowcaseDesign() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["--uitesting-showcase"])
        app.launch()
        let tabs = app.tabBars
        XCTAssertTrue(tabs.buttons["Cours"].waitForExistence(timeout: 8))
        let context = XCTAttachment(string: "Captures natives du simulateur, avec les données fictives isolées de --uitesting-showcase. Les chiffres sont calculés par les mêmes vues et le même moteur que l’app. Aucune donnée de démonstration sur appareil physique.")
        context.name = "vitrine-contexte"
        context.lifetime = .keepAlways
        add(context)
        capture(app, name: "vitrine-accueil")

        tabs.buttons["Cours"].tap()
        XCTAssertTrue(app.navigationBars["Emploi du temps"].waitForExistence(timeout: 4))
        app.segmentedControls.buttons["Jour"].tap()
        tap(app.buttons["courses.next"], in: app)
        XCTAssertTrue(app.staticTexts["Mathématiques"].firstMatch.waitForExistence(timeout: 4))
        capture(app, name: "vitrine-emploi-du-temps")

        tabs.buttons["Révision"].tap()
        tap(app.buttons["session.start"], in: app)
        XCTAssertTrue(app.buttons["session.pause"].waitForExistence(timeout: 4))
        scrollToTop(app)
        capture(app, name: "vitrine-revision-active")

        tabs.buttons["Statistiques"].tap()
        XCTAssertTrue(app.navigationBars["Statistiques"].waitForExistence(timeout: 4))
        capture(app, name: "vitrine-statistiques")

        tabs.buttons["Révision"].tap()
        tap(app.buttons["session.finish"], in: app)
        let finish = app.alerts.buttons["Terminer et enregistrer"]
        XCTAssertTrue(finish.waitForExistence(timeout: 4))
        finish.tap()
        XCTAssertTrue(reveal(app.buttons["session.start"], in: app))
    }

    @MainActor
    func testLargeTextSessionControls() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments([
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        app.launch()
        let revisionTab = app.tabBars.buttons["Révision"]
        XCTAssertTrue(revisionTab.waitForExistence(timeout: 8))
        revisionTab.tap()
        tap(app.buttons["session.start"], in: app)
        tap(app.buttons["session.pause"], in: app)
        XCTAssertTrue(app.buttons["session.resume"].waitForExistence(timeout: 4))
        scrollToTop(app)
        capture(app, name: "accessibilite-grand-texte")
        tap(app.buttons["session.resume"], in: app)
        tap(app.buttons["session.finish"], in: app)
        let finish = app.alerts.buttons["Terminer et enregistrer"]
        XCTAssertTrue(finish.waitForExistence(timeout: 4))
        finish.tap()
        XCTAssertTrue(reveal(app.buttons["session.start"], in: app))
    }

    @MainActor
    func testWidgetDesignPreview() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["--uitesting-widget-preview"])
        app.launch()
        let preview = app.descendants(matching: .any).matching(identifier: "widget.preview.screen").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        let context = XCTAttachment(string: "Aperçu SwiftUI natif des composants réels des widgets sur simulateur. Ce scénario ne représente pas l’écran d’accueil système de WidgetKit et ne valide pas les droits de partage de données sur un iPhone signé.")
        context.name = "widgets-apercu-contexte"
        context.lifetime = .keepAlways
        add(context)
        capture(app, name: "widgets-apercu-simulateur-haut")
        let surface = scrollingSurface(in: app)
        XCTAssertTrue(surface.exists)
        if surface.exists { surface.swipeUp() }
        capture(app, name: "widgets-apercu-simulateur-bas")
    }

    private func testArguments(_ extra: [String] = []) -> [String] {
        ["--uitesting", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"] + extra
    }

    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        guard reveal(element, in: app) else {
            XCTFail("L’action doit rester accessible après défilement.", file: file, line: line)
            return
        }
        element.tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        _ = element.waitForExistence(timeout: 3)
        let surface = scrollingSurface(in: app)
        for _ in 0..<10 {
            if isVisibleForTap(element, in: app) { return true }
            guard surface.exists else { return false }
            let window = app.windows.firstMatch.frame
            let navigation = app.navigationBars.allElementsBoundByIndex.filter {
                $0.frame.intersects(window) && ($0.isHittable || $0.buttons.allElementsBoundByIndex.contains { $0.isHittable })
            }.max { $0.frame.minY < $1.frame.minY }
            let visibleTop = max(surface.frame.minY, navigation?.frame.maxY ?? window.minY)
            if element.exists && element.frame.midY <= visibleTop {
                surface.swipeDown()
            } else {
                surface.swipeUp()
            }
        }
        return isVisibleForTap(element, in: app)
    }

    @MainActor
    private func isVisibleForTap(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let window = app.windows.firstMatch.frame
        let navigation = app.navigationBars.allElementsBoundByIndex.filter {
            $0.frame.intersects(window) && ($0.isHittable || $0.buttons.allElementsBoundByIndex.contains { $0.isHittable })
        }.max { $0.frame.minY < $1.frame.minY }
        // Démarrer dans un formulaire est un vrai bouton de barre de navigation.
        // Les actions du contenu, même déclarées hittables, doivent rester en dessous.
        if let navigation, navigation.buttons.allElementsBoundByIndex.contains(where: {
            $0.isHittable && $0.label == element.label && $0.frame == element.frame
        }) { return true }
        let visibleTop = navigation?.frame.maxY ?? window.minY
        let tabs = app.tabBars.allElementsBoundByIndex.first {
            $0.frame.intersects(window) && $0.buttons.allElementsBoundByIndex.contains { $0.isHittable }
        }
        let visibleBottom = tabs?.frame.minY ?? window.maxY
        return element.frame.midY > visibleTop && element.frame.midY < visibleBottom
    }

    @MainActor
    private func scrollingSurface(in app: XCUIApplication) -> XCUIElement {
        if app.scrollViews.firstMatch.exists { return app.scrollViews.firstMatch }
        if app.collectionViews.firstMatch.exists { return app.collectionViews.firstMatch }
        return app.tables.firstMatch
    }

    @MainActor
    private func scrollToTop(_ app: XCUIApplication) {
        let surface = scrollingSurface(in: app)
        guard surface.exists else { return }
        for _ in 0..<3 { surface.swipeDown() }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        // Capture the complete native display, including presentation safe areas.
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

}
