import XCTest

final class CadenceUITests: XCTestCase {
    @MainActor
    func testPronoteLoginRequiresPublicHTTPSWithoutRequestingLocation() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments()
        app.launch()
        tap(app.buttons["Réglages"], in: app)
        tap(app.buttons["Connexion PRONOTE"], in: app)
        XCTAssertTrue(app.navigationBars["Connexion PRONOTE"].waitForExistence(timeout: 4))
        // The login screen does not request GPS. This test never taps nearby or connect.
        XCTAssertEqual(app.alerts.count, 0)
        let nearby = app.buttons["school.find.nearby"]
        XCTAssertTrue(nearby.exists)
        let url = app.textFields["school.login.url"]
        let connect = app.buttons["school.login.connect"]
        tap(url, in: app)
        url.typeText("http://school-example.index-education.net/pronote/")
        let username = app.textFields["school.login.username"]
        tap(username, in: app)
        username.typeText("compte-fictif-test-ui")
        let password = app.secureTextFields["school.login.password"]
        tap(password, in: app)
        password.typeText("MotDePasseFictif42\n")
        XCTAssertTrue(reveal(connect, in: app))
        XCTAssertFalse(connect.isEnabled)

        tap(url, in: app)
        let invalidValue = (url.value as? String) ?? ""
        url.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: invalidValue.count))
        url.typeText("https://127.0.0.1/pronote/")
        XCTAssertFalse(connect.isEnabled)

        let localValue = (url.value as? String) ?? ""
        url.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: localValue.count))
        url.typeText("https://school-example.index-education.net/pronote/")
        XCTAssertTrue(connect.isEnabled)
        capture(app, name: "pronote-connexion-directe-formulaire")
        // No network authentication and no real credentials are used by this test.
    }

    @MainActor
    func testMusicAndFocusSheetHasNavigationAndClosesToSession() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments()
        app.launch()
        app.tabBars.buttons["Révision"].tap()
        tap(app.buttons["session.start"], in: app)
        XCTAssertTrue(app.buttons["session.pause"].waitForExistence(timeout: 4))
        tap(app.buttons["session.companion"], in: app)
        XCTAssertTrue(app.navigationBars["Son et concentration"].waitForExistence(timeout: 4))
        let volume = app.descendants(matching: .any).matching(identifier: "companion.system.volume").firstMatch
        XCTAssertTrue(volume.waitForExistence(timeout: 3))
        let focusGuide = app.staticTexts["companion.focus.guide"]
        XCTAssertTrue(reveal(focusGuide, in: app))
        XCTAssertFalse(app.buttons["companion.focus.add"].exists)
        capture(app, name: "musique-et-concentration")
        tap(app.buttons["Fermer"], in: app)
        XCTAssertFalse(app.navigationBars["Son et concentration"].exists)
        XCTAssertTrue(reveal(app.buttons["session.pause"], in: app))
    }

    @MainActor
    func testPronotePortalReadsSyntheticGradesLessonAndMessages() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["--uitesting-school"])
        app.launch()
        tap(app.buttons["pronote.portal"], in: app)
        XCTAssertTrue(app.navigationBars["Mon espace scolaire"].waitForExistence(timeout: 4))
        tap(app.buttons["pronote.portal.grades"], in: app)
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 4))
        XCTAssertTrue(reveal(app.staticTexts["Évaluation fictive — équations"], in: app))
        capture(app, name: "pronote-notes")
        app.navigationBars.buttons.firstMatch.tap()

        tap(app.buttons["pronote.portal.contents"], in: app)
        XCTAssertTrue(app.navigationBars["Contenus des cours"].waitForExistence(timeout: 4))
        tap(app.buttons["pronote.contents.subject.Mathématiques"], in: app)
        tap(app.buttons["pronote.resource.fixture-resource"], in: app)
        XCTAssertTrue(app.navigationBars["Contenu du cours"].waitForExistence(timeout: 4))
        XCTAssertTrue(reveal(app.staticTexts["Leçon fictive : les équations"], in: app))
        XCTAssertTrue(app.staticTexts["Contenu entièrement fictif : isoler une inconnue puis vérifier la solution."].exists)
        capture(app, name: "pronote-lecon")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Mathématiques"].waitForExistence(timeout: 4))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()

        tap(app.buttons["pronote.portal.discussions"], in: app)
        XCTAssertTrue(app.navigationBars["Messagerie"].waitForExistence(timeout: 4))
        tap(app.buttons["pronote.discussion.fixture-discussion"], in: app)
        XCTAssertTrue(app.navigationBars["Discussion fictive de test"].waitForExistence(timeout: 4))
        XCTAssertTrue(reveal(app.staticTexts["Message fictif : pensez à relire la leçon."], in: app))
        XCTAssertFalse(app.textViews["pronote.thread.reply"].exists)
        capture(app, name: "pronote-messages")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Messagerie"].waitForExistence(timeout: 4))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Mon espace scolaire"].waitForExistence(timeout: 4))
        let context = XCTAttachment(string: "Portail PRONOTE testé avec un cache local entièrement fictif. Aucune connexion, aucun message envoyé, aucun accusé de réception et aucune donnée personnelle réelle.")
        context.name = "pronote-portail-contexte"
        context.lifetime = .keepAlways
        add(context)
    }

    @MainActor
    func testSchoolOverviewOpensReadableAttendanceAndNews() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["--uitesting-school"])
        app.launch()
        tap(app.buttons["pronote.quick.attendance"], in: app)
        XCTAssertTrue(app.navigationBars["Vie scolaire"].waitForExistence(timeout: 4))
        XCTAssertTrue(reveal(app.staticTexts["Motif fictif : maladie"], in: app))
        XCTAssertTrue(app.staticTexts["4 h 00 de cours manqués"].exists)
        XCTAssertTrue(app.staticTexts["Régularisée"].exists)
        capture(app, name: "pronote-absences-refonte")
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.buttons["pronote.quick.news"], in: app)
        tap(app.buttons["pronote.news.fixture-news"], in: app)
        let content = app.staticTexts["pronote.news.content"]
        XCTAssertTrue(content.waitForExistence(timeout: 4))
        XCTAssertFalse(content.label.contains("<div"))
        capture(app, name: "pronote-information-refonte")
    }

    @MainActor
    func testPronoteMessageDraftCanBeCancelledWithoutSending() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["--uitesting-school"])
        app.launch()
        tap(app.buttons["pronote.portal"], in: app)
        tap(app.buttons["pronote.portal.discussions"], in: app)
        XCTAssertTrue(app.navigationBars["Messagerie"].waitForExistence(timeout: 4))
        tap(app.buttons["pronote.compose.open"], in: app)
        XCTAssertTrue(app.navigationBars["Nouveau message"].waitForExistence(timeout: 4))

        let recipient = app.buttons["pronote.compose.recipient.fixture-teacher"]
        tap(recipient, in: app)
        XCTAssertEqual(recipient.value as? String, "Sélectionné")
        // SwiftUI's vertically expanding TextField may expose a native text
        // view depending on iOS. Match the actual editable control in either form.
        let subject = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND (elementType == %@ OR elementType == %@)",
            "pronote.compose.subject", NSNumber(value: XCUIElement.ElementType.textField.rawValue),
            NSNumber(value: XCUIElement.ElementType.textView.rawValue))).firstMatch
        tap(subject, in: app)
        subject.typeText("Brouillon fictif de test")
        let message = app.textViews["pronote.compose.text"]
        tap(message, in: app)
        message.typeText("Texte entièrement fictif, annulé sans envoi.")
        XCTAssertEqual(subject.value as? String, "Brouillon fictif de test")
        XCTAssertEqual(message.value as? String, "Texte entièrement fictif, annulé sans envoi.")
        XCTAssertTrue(app.buttons["pronote.compose.send"].isEnabled)
        XCTAssertEqual(app.alerts.count, 0)
        capture(app, name: "pronote-nouveau-message-brouillon")

        // Only cancellation is exercised. The send button and its confirmation
        // are never touched, and --uitesting forbids remote writes in AppStore.
        tap(app.buttons["pronote.compose.cancel"], in: app)
        XCTAssertTrue(app.navigationBars["Messagerie"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.navigationBars["Nouveau message"].exists)
        XCTAssertTrue(app.buttons["pronote.discussion.fixture-discussion"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        let context = XCTAttachment(string: "Brouillon entièrement fictif : destinataire synthétique, aucun clic Envoyer, aucune confirmation, aucun message transmis.")
        context.name = "pronote-brouillon-contexte"
        context.lifetime = .keepAlways
        add(context)
    }

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

    @MainActor
    func testSchoolHomeworkFiltersAndDetails() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["--uitesting-school"])
        app.launch()
        let homeworkTab = app.tabBars.buttons["Devoirs"]
        XCTAssertTrue(homeworkTab.waitForExistence(timeout: 8))
        homeworkTab.tap()
        let math = app.buttons["homework.row.fixture-homework-math-today"]
        let english = app.buttons["homework.row.fixture-homework-english-tomorrow"]
        let overdue = app.buttons["homework.row.fixture-homework-svt-overdue"]
        let completed = app.buttons["homework.row.fixture-homework-french-done"]
        XCTAssertTrue(reveal(math, in: app))
        XCTAssertFalse(completed.exists)
        tap(app.segmentedControls.buttons["Tous"], in: app)
        XCTAssertTrue(reveal(completed, in: app))
        tap(app.segmentedControls.buttons["Retard"], in: app)
        XCTAssertTrue(overdue.waitForExistence(timeout: 3))
        XCTAssertFalse(math.exists)
        XCTAssertFalse(english.exists)
        XCTAssertFalse(completed.exists)
        tap(app.segmentedControls.buttons["À faire"], in: app)
        XCTAssertTrue(reveal(math, in: app))
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        let key = DateFormatter()
        key.calendar = paris; key.timeZone = paris.timeZone; key.locale = Locale(identifier: "en_US_POSIX")
        key.dateFormat = "yyyy-MM-dd"
        let todayHeader = app.descendants(matching: .any).matching(identifier: "homework.date." + key.string(from: Date())).firstMatch
        XCTAssertTrue(reveal(todayHeader, in: app))
        let tomorrow = paris.date(byAdding: .day, value: 1, to: Date())!
        let tomorrowHeader = app.descendants(matching: .any).matching(identifier: "homework.date." + key.string(from: tomorrow)).firstMatch
        XCTAssertTrue(reveal(tomorrowHeader, in: app))
        XCTAssertFalse(app.staticTexts["Plus tard"].exists)
        scrollToTop(app)
        let context = XCTAttachment(string: "Captures natives de --uitesting-school : cours et devoirs entièrement fictifs, cache isolé du simulateur, sans requête Supabase ni donnée scolaire réelle.")
        context.name = "devoirs-contexte-fictif"
        context.lifetime = .keepAlways
        add(context)
        capture(app, name: "devoirs-liste")
        tap(math, in: app)
        XCTAssertTrue(app.staticTexts["Exemple fictif : résoudre deux équations et vérifier les résultats."].waitForExistence(timeout: 3))
        scrollToTop(app)
        capture(app, name: "devoirs-detail")
        tap(app.buttons["homework.complete"], in: app)
        XCTAssertTrue(app.buttons["homework.complete"].label.contains("Remettre à faire"))
        app.tabBars.buttons["Accueil"].tap()
        homeworkTab.tap()
        XCTAssertTrue(app.buttons["homework.complete"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["homework.complete"].label.contains("Remettre à faire"))
    }

    @MainActor
    func testHomeworkQuickActionsCleanHTMLAndKeepNavigationSimple() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["--uitesting-school"])
        app.launch()
        let tabs = app.tabBars
        XCTAssertTrue(tabs.buttons["Devoirs"].waitForExistence(timeout: 8))
        tabs.buttons["Devoirs"].tap()
        let mathID = "fixture-homework-math-today"
        let row = app.buttons["homework.row." + mathID]
        XCTAssertTrue(reveal(row, in: app))
        XCTAssertTrue(row.label.contains("Exemple fictif : résoudre deux équations et vérifier les résultats."))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "<div")).firstMatch.exists)
        tap(app.buttons["homework.quick.complete." + mathID], in: app)
        XCTAssertTrue(app.navigationBars["Devoirs"].exists)
        XCTAssertFalse(row.exists)
        tap(app.segmentedControls.buttons["Terminés"], in: app)
        tap(app.buttons["homework.quick.complete." + mathID], in: app)
        tap(app.segmentedControls.buttons["À faire"], in: app)
        tap(app.buttons["homework.quick.start." + mathID], in: app)
        XCTAssertTrue(app.buttons["session.pause"].waitForExistence(timeout: 4))
        let instructions = app.staticTexts["session.homework.description"]
        XCTAssertTrue(reveal(instructions, in: app))
        XCTAssertEqual(instructions.label, "Exemple fictif : résoudre deux équations et vérifier les résultats.")
        tabs.buttons["Devoirs"].tap()
        XCTAssertTrue(app.navigationBars["Devoirs"].exists)
        XCTAssertTrue(reveal(app.buttons["homework.quick.start." + mathID], in: app))
        XCTAssertTrue(app.buttons["homework.quick.start." + mathID].label.contains("Séance en cours"))
        capture(app, name: "devoirs-actions-directes")
    }

    @MainActor
    func testSchoolHomeworkStartsRevisionAndCompletesWithoutLosingTimer() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["--uitesting-school"])
        app.launch()
        let homeworkTab = app.tabBars.buttons["Devoirs"]
        XCTAssertTrue(homeworkTab.waitForExistence(timeout: 8))
        homeworkTab.tap()
        tap(app.buttons["homework.row.fixture-homework-math-today"], in: app)
        tap(app.buttons["homework.start"], in: app)
        XCTAssertTrue(app.buttons["session.pause"].waitForExistence(timeout: 4))
        tap(app.buttons["session.pause"], in: app)
        XCTAssertTrue(app.buttons["session.resume"].waitForExistence(timeout: 3))
        scrollToTop(app)
        capture(app, name: "devoir-seance-liee")
        homeworkTab.tap()
        XCTAssertTrue(app.buttons["homework.open.session"].waitForExistence(timeout: 4))
        tap(app.buttons["homework.complete"], in: app)
        XCTAssertTrue(app.buttons["homework.complete"].label.contains("Remettre à faire"))
        XCTAssertFalse(app.buttons["homework.open.session"].exists)
        app.tabBars.buttons["Révision"].tap()
        XCTAssertTrue(app.buttons["session.resume"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["session.start"].exists)
        tap(app.buttons["session.resume"], in: app)
        tap(app.buttons["session.finish"], in: app)
        let finish = app.alerts.buttons["Terminer et enregistrer"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        finish.tap()
        XCTAssertTrue(reveal(app.buttons["session.start"], in: app))
    }

    @MainActor
    func testSchoolHomeworkAttachesToExistingSessionOfAnotherSubject() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["--uitesting-school"])
        app.launch()
        let revisionTab = app.tabBars.buttons["Révision"]
        XCTAssertTrue(revisionTab.waitForExistence(timeout: 8))
        revisionTab.tap()
        tap(app.buttons["session.start"], in: app)
        XCTAssertTrue(app.buttons["session.pause"].waitForExistence(timeout: 4))
        let homeworkTab = app.tabBars.buttons["Devoirs"]
        homeworkTab.tap()
        tap(app.buttons["homework.row.fixture-homework-english-tomorrow"], in: app)
        XCTAssertTrue(app.buttons["homework.attach"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["homework.start"].exists)
        tap(app.buttons["homework.attach"], in: app)
        XCTAssertTrue(app.buttons["session.pause"].waitForExistence(timeout: 4))
        scrollToTop(app)
        XCTAssertTrue(app.staticTexts["Mathématiques"].firstMatch.waitForExistence(timeout: 3))
        homeworkTab.tap()
        XCTAssertTrue(app.buttons["homework.open.session"].waitForExistence(timeout: 4))
        tap(app.buttons["homework.detach"], in: app)
        revisionTab.tap()
        XCTAssertTrue(app.buttons["session.pause"].waitForExistence(timeout: 3))
        tap(app.buttons["session.finish"], in: app)
        let finish = app.alerts.buttons["Terminer et enregistrer"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        finish.tap()
        XCTAssertTrue(reveal(app.buttons["session.start"], in: app))
    }

    @MainActor
    func testTabNavigationPreservesHomeworkDetailAndFilter() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments(["--uitesting-school"])
        app.launch()
        let tabs = app.tabBars
        XCTAssertTrue(tabs.buttons["Devoirs"].waitForExistence(timeout: 8))
        tabs.buttons["Devoirs"].tap()
        tap(app.segmentedControls.buttons["Terminés"], in: app)
        tap(app.buttons["homework.row.fixture-homework-french-done"], in: app)
        XCTAssertTrue(app.buttons["homework.complete"].waitForExistence(timeout: 4))
        for title in ["Accueil", "Cours", "Statistiques", "Révision"] { tabs.buttons[title].tap() }
        tabs.buttons["Devoirs"].tap()
        XCTAssertTrue(app.buttons["homework.complete"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["homework.complete"].label.contains("Remettre à faire"))
        app.navigationBars.buttons["Devoirs"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Terminés"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.segmentedControls.buttons["Terminés"].isSelected)
        XCTAssertFalse(app.buttons["homework.row.fixture-homework-math-today"].exists)
        tabs.buttons["Statistiques"].tap()
        tap(app.segmentedControls.buttons["Mois"], in: app)
        XCTAssertFalse(app.staticTexts["Estimés"].exists)
        XCTAssertFalse(app.staticTexts["Cours estimés"].exists)
        scrollToTop(app)
        capture(app, name: "statistiques-deux-categories")
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
