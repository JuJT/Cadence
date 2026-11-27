import Foundation
import UIKit
import Vision
import XCTest

final class CadenzaTapTests: XCTestCase {
    private struct Line {
        let text: String
        let bounds: CGRect
    }

    private struct Screen {
        let lines: [Line]
        let screenshot: XCUIScreenshot
        let uptime: TimeInterval
    }

    private let app = XCUIApplication(bundleIdentifier: "com.cadence.study")
    private let subjects = ["Mathématiques", "Français", "Histoire-Géographie", "Anglais", "Physique-Chimie",
                            "SVT", "SES", "EPS", "Sciences", "Éducation physique"]
    private let homeworkSnippets = ["Lire les chapitres", "Réviser le chapitre", "Apprendre le vocabulaire",
                                    "Rédiger le compte rendu", "Terminer le schéma", "Faire les exercices"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--cadenza-preview", "home"]
        app.launch()
        _ = try waitFor("Accueil de démonstration") { screen in
            self.line(screen, "Camille Martin") != nil && self.line(screen, "Statistiques") != nil
        }
    }

    func test01SettingsFromHome() throws {
        attach(try capture(), "home-before-settings")
        try openHomeControl(x: 0.93, expected: "Personnalisation")
    }

    func test02PaletteFromHome() throws {
        try openHomeControl(x: 0.84, expected: "Personnaliser le fond")
    }

    func test03CourseStartsAndReducesClock() throws {
        try tapTab("Cours")
        let calendar = try waitFor("titres des cours") { self.courseLine($0) != nil }
        try press(try XCTUnwrap(courseLine(calendar)))
        try tapText("Chronométrer ce cours")
        try verifyClockAdvances(status: "Cours en cours")
        try tapText("Réduire")
        let reduced = try waitFor("retour aux cours") {
            self.courseLine($0) != nil && self.line($0, "Réduire") == nil
        }
        attach(reduced, "course-returned")
        try finishFromStudy()
    }

    func test04HomeworkStartsAndReducesClock() throws {
        try tapTab("Tâches")
        var tasks = try waitFor("devoirs de démonstration") {
            self.line($0, "Semaine") != nil &&
                (self.line($0, "Faire le devoir") != nil || self.homeworkLine($0) != nil)
        }
        attach(tasks, "homework-list-before-tap")
        for _ in 0..<3 where visibleHomeworkAction(tasks) == nil {
            point(x: 0.52, y: 0.70).press(forDuration: 0.05, thenDragTo: point(x: 0.52, y: 0.46))
            tasks = try capture()
        }
        attach(tasks, "homework-card-action")
        try press(try XCTUnwrap(visibleHomeworkAction(tasks), "Le pied de carte doit proposer Faire le devoir."))
        try verifyClockAdvances(status: "Révision en cours")
        _ = try waitFor("devoir associé") { self.line($0, "Devoir associé") != nil }
        try tapText("Réduire")
        let reduced = try waitFor("retour aux tâches") {
            (self.homeworkLine($0) != nil || self.line($0, "Ouvrir la séance") != nil || self.line($0, "Faire le devoir") != nil)
                && self.line($0, "Réduire") == nil
        }
        attach(reduced, "homework-returned")
    }

    private func openHomeControl(x: CGFloat, expected: String) throws {
        var before = try capture()
        if let tip = line(before, "Change de fond") {
            point(x: 0.90, y: 1 - tip.bounds.midY).tap()
            before = try capture()
        }
        let account = try XCTUnwrap(line(before, "Camille Martin"))
        let attempts: [CGFloat] = x < 0.9 ? [x, x + 0.023, x - 0.02] : [x]
        for candidate in attempts {
            point(x: candidate, y: 1 - account.bounds.midY).tap()
            Thread.sleep(forTimeInterval: 1.4)
            let after = try capture()
            if line(after, expected) != nil {
                attach(after, expected)
                return
            }
            if line(after, "Camille Martin") == nil { break }
        }
        let opened = try waitFor(expected) { self.line($0, expected) != nil }
        attach(opened, expected)
    }

    private func verifyClockAdvances(status: String) throws {
        let start = try waitFor(status) {
            self.line($0, status) != nil && self.seconds($0) != nil
        }
        let startSeconds = try XCTUnwrap(seconds(start))
        attach(start, status + " first clock")
        let next = try waitFor("augmentation du temps depuis \(startSeconds) s", timeout: 18) { screen in
            guard let nextSeconds = self.seconds(screen) else { return false }
            let delta = nextSeconds - startSeconds
            let elapsed = screen.uptime - start.uptime
            return delta >= 2 && abs(Double(delta) - elapsed) <= 3.5 && self.line(screen, status) != nil
        }
        attach(next, status + " advanced clock")
        print("CADENZA_CLOCK_ADVANCED \(status): \(startSeconds) -> \(seconds(next) ?? -1) s")
    }

    private func finishFromStudy() throws {
        try tapTab("Révision")
        try tapText("Terminer")
        try tapText("Terminer et enregistrer")
        _ = try waitFor("séance enregistrée") { self.line($0, "Terminer et enregistrer") == nil }
    }

    private func tapTab(_ text: String) throws {
        let screen = try waitFor("onglet \(text)") { self.line($0, text, bottom: true) != nil }
        try press(try XCTUnwrap(line(screen, text, bottom: true)))
    }

    private func tapText(_ text: String) throws {
        let screen = try waitFor(text) { self.line($0, text) != nil }
        try press(try XCTUnwrap(line(screen, text)))
    }

    private func press(_ line: Line) throws {
        point(x: line.bounds.midX, y: 1 - line.bounds.midY).tap()
    }

    private func point(x: CGFloat, y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private func line(_ screen: Screen, _ query: String, bottom: Bool = false) -> Line? {
        let expected = normalize(query)
        return screen.lines.first { line in
            let text = normalize(line.text)
            return bottom ? line.bounds.midY <= 0.14 && text == expected : text.contains(expected)
        }
    }

    private func courseLine(_ screen: Screen) -> Line? {
        screen.lines.filter { line in
            (0.18...0.84).contains(line.bounds.midY)
                && subjects.contains { normalize(line.text).hasPrefix(normalize($0)) }
        }.max { first, second in first.bounds.midY < second.bounds.midY }
    }

    private func homeworkLine(_ screen: Screen) -> Line? {
        for snippet in homeworkSnippets {
            if let found = line(screen, snippet), (0.20...0.78).contains(found.bounds.midY) { return found }
        }
        return nil
    }

    private func visibleHomeworkAction(_ screen: Screen) -> Line? {
        guard let action = line(screen, "Faire le devoir"), (0.17...0.82).contains(action.bounds.midY) else { return nil }
        return action
    }

    private func seconds(_ screen: Screen) -> Int? {
        if let value = clockSeconds(screen.lines) { return value }
        let clockArea = CGRect(x: 0.17, y: 0.30, width: 0.66, height: 0.39)
        let cropped = (try? recognize(screen.screenshot, region: clockArea, numbersOnly: true)) ?? []
        return clockSeconds(cropped)
    }

    private func clockSeconds(_ lines: [Line]) -> Int? {
        let clock = #"^00\s*:\s*[0-1][0-9]\s*:\s*[0-5][0-9]$"#
        for line in lines where line.bounds.midX > 0.25 && line.bounds.midX < 0.75
            && line.bounds.height > 0.018 && line.text.range(of: clock, options: .regularExpression) != nil {
            let fields = line.text.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if fields.count == 3, fields[1] < 2 { return fields[1] * 60 + fields[2] }
        }
        return nil
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "’", with: "'")
    }

    private func waitFor(_ message: String, timeout: TimeInterval = 25,
                         matching predicate: (Screen) -> Bool) throws -> Screen {
        let deadline = Date().addingTimeInterval(timeout)
        var screen = try capture()
        while !predicate(screen), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.45)
            screen = try capture()
        }
        guard predicate(screen) else {
            attach(screen, "échec " + message)
            throw NSError(domain: "CadenzaTapQA", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message + " — OCR: " + screen.lines.map(\.text).joined(separator: " | ")])
        }
        return screen
    }

    private func capture() throws -> Screen {
        let screenshot = XCUIScreen.main.screenshot()
        let uptime = ProcessInfo.processInfo.systemUptime
        return Screen(lines: try recognize(screenshot), screenshot: screenshot, uptime: uptime)
    }

    private func recognize(_ screenshot: XCUIScreenshot, region: CGRect? = nil, numbersOnly: Bool = false) throws -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = numbersOnly ? ["en-US"] : ["fr-FR", "en-US"]
        request.usesLanguageCorrection = !numbersOnly
        if let region { request.regionOfInterest = region }
        try VNImageRequestHandler(data: screenshot.pngRepresentation).perform([request])
        return (request.results ?? []).compactMap { observation -> Line? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return Line(text: text, bounds: observation.boundingBox)
        }
    }

    private func attach(_ screen: Screen, _ name: String) {
        let screenshot = XCTAttachment(screenshot: screen.screenshot)
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let labels = XCTAttachment(string: screen.lines.map(\.text).joined(separator: "\n"))
        labels.name = name + " OCR"
        labels.lifetime = .keepAlways
        add(labels)
    }
}
