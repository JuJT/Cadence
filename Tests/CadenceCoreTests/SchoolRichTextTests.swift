import XCTest
@testable import CadenceCore

final class SchoolRichTextTests: XCTestCase {
    func testHomeworkAndCourseFragmentsKeepReadableLines() {
        XCTAssertEqual(SchoolRichText.plain("<div>QCM 10 à 22 page 293<br>Exercices 26, 27 et 30 page 297</div>"),
                       "QCM 10 à 22 page 293\nExercices 26, 27 et 30 page 297")
        XCTAssertEqual(SchoolRichText.plain("<div style=\"font-family: Arial; font-size:13px;\">Parcours dans mon schéma de l’œuvre.&nbsp;</div>"),
                       "Parcours dans mon schéma de l’œuvre.")
    }

    func testEncodedMarkupAndDangerousElementsAreNeverDisplayed() {
        XCTAssertEqual(SchoolRichText.plain("&lt;div&gt;R&eacute;viser &#233; &#xE0;&lt;br&gt;&lt;script&gt;alert(1)&lt;/script&gt;le cours&lt;/div&gt;"),
                       "Réviser é à\nle cours")
        XCTAssertEqual(SchoolRichText.plain("<style>body{color:red}</style><!--secret--><p>Leçon</p><iframe src='https://example.com'>masqué</iframe>"), "Leçon")
    }

    func testPlainMathsAndEntitiesRemainReadable() {
        XCTAssertEqual(SchoolRichText.plain("Si x < 2 et y > 3 : 5 &times; 2 = 10 &amp; 20&nbsp;&euro;"),
                       "Si x < 2 et y > 3 : 5 × 2 = 10 & 20 €")
        XCTAssertEqual(SchoolRichText.plain("<ul><li>Relire</li><li>Apprendre</li></ul>"), "• Relire\n• Apprendre")
    }
}
