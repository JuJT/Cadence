import Foundation
import XCTest
@testable import CadenceCore

final class PronoteLoginTests: XCTestCase {
    func testPastedAddressDropsSessionInformationAndKeepsSchoolPath() throws {
        let address = try XCTUnwrap(PronoteLoginAddress(" HTTPS://LYCEE.INDEX-EDUCATION.NET:443/site/pronote/eleve.html?ticket=fictif#accueil "))
        XCTAssertEqual(address.base.absoluteString, "https://lycee.index-education.net/site/pronote")
        XCTAssertEqual(address.mobileStudent.path, "/site/pronote/mobile.eleve.html")
        XCTAssertTrue(address.recognizes(URL(string: "https://lycee.index-education.net/site/pronote/mobile.eleve.html?fd=1"), as: address.mobileStudent))
        XCTAssertFalse(address.recognizes(URL(string: "https://identite.exemple.fr/site/pronote/mobile.eleve.html"), as: address.mobileStudent))
        XCTAssertFalse(address.recognizes(URL(string: "https://lycee.index-education.net/site/autre/mobile.eleve.html"), as: address.mobileStudent))
        XCTAssertFalse(address.recognizes(URL(string: "https://lycee.index-education.net:8443/site/pronote/mobile.eleve.html"), as: address.mobileStudent))
    }

    func testSchoolAddressRejectsPrivateAndAmbiguousDestinations() {
        for value in ["http://lycee.index-education.net/pronote", "https://127.0.0.1/pronote", "https://test.local/",
                      "https://user@lycee.index-education.net/pronote", "https://lycee.index-education.net/pronote/parent.html",
                      "https://lycee.index-education.net/autre%2Fpronote", "https://lycee.index-education.net/%2E%2E/pronote"] {
            XCTAssertNil(PronoteLoginAddress(value), value)
        }
    }

    func testPairingOnlyParsesStudentCodesWithFourASCIIDigits() throws {
        let valid = #"{"url":"https://lycee.index-education.net/pronote/mobile.eleve.html","login":"identifiant-fictif","jeton":"jeton-fictif"}"#
        let pair = try XCTUnwrap(PronotePairingCode.parse(valid))
        XCTAssertEqual(pair.login, "identifiant-fictif")
        XCTAssertNil(PronotePairingCode.parse(valid.replacingOccurrences(of: "mobile.eleve.html", with: "mobile.parent.html")))
        XCTAssertNil(PronotePairingCode.parse(valid.replacingOccurrences(of: "jeton-fictif", with: "")))
        XCTAssertNil(PronotePairingCode.parse("https://lycee.index-education.net/pronote"))
        XCTAssertTrue(PronotePairingCode.isValidPIN("0012"))
        for pin in ["123", "12345", "１２３４", "1234\n", "12 3"] { XCTAssertFalse(PronotePairingCode.isValidPIN(pin)) }
    }
}
