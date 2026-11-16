import Foundation
import XCTest
@testable import CadenceCore

final class SchoolLoginLinkTests: XCTestCase {
    private let project = URL(string: "https://school-example.supabase.co")!

    func testAcceptsSixToTenASCIIDigits() throws {
        for code in ["123456", "12345678", "1234567890"] {
            XCTAssertEqual(try SchoolLoginLink.parse(" \n" + code + "\n", projectURL: project), .code(code))
        }
        for invalid in ["12345", "12345678901", "12x456", "１２３４５６", "123 456"] {
            XCTAssertThrowsError(try SchoolLoginLink.parse(invalid, projectURL: project))
        }
    }

    func testAcceptsOnlyTheProjectsSupportedEmailLinkTypes() throws {
        for type in ["email", "magiclink", "signup"] {
            for parameter in ["token", "token_hash"] {
                let text = "https://school-example.supabase.co/auth/v1/verify?\(parameter)=fixture-hash&type=\(type)&redirect_to=https%3A%2F%2Fexample.test"
                XCTAssertEqual(try SchoolLoginLink.parse(text, projectURL: project), .tokenHash("fixture-hash", type: type))
            }
        }
    }

    func testRejectsForeignHostsCredentialsAndUnexpectedPorts() {
        let urls = [
            "http://school-example.supabase.co/auth/v1/verify?token=x&type=email",
            "https://other.supabase.co/auth/v1/verify?token=x&type=email",
            "https://school-example.supabase.co.attacker.test/auth/v1/verify?token=x&type=email",
            "https://school-example.supabase.co@attacker.test/auth/v1/verify?token=x&type=email",
            "https://user@school-example.supabase.co/auth/v1/verify?token=x&type=email",
            "https://school-example.supabase.co:8443/auth/v1/verify?token=x&type=email",
            "https://school-example.supabase.co./auth/v1/verify?token=x&type=email"
        ]
        for url in urls { XCTAssertThrowsError(try SchoolLoginLink.parse(url, projectURL: project)) }
    }

    func testRejectsWrongPathsFragmentsDuplicateFieldsAndOtherAuthFlows() {
        let suffixes = [
            "/auth/v1/token?token=x&type=email",
            "/auth/v1/%76erify?token=x&type=email",
            "/auth/v1/verify?token=x&type=email#access_token=fixture",
            "/auth/v1/verify?token=x&token_hash=y&type=email",
            "/auth/v1/verify?token=x&type=email&type=signup",
            "/auth/v1/verify?token=&type=email",
            "/auth/v1/verify?token=x&type=recovery",
            "/auth/v1/verify?token=x&type=invite",
            "/auth/v1/verify?token=x&type=email_change",
            "/auth/v1/verify?token=x&type=sms",
            "/auth/v1/verify?token=a%0Ab&type=email"
        ]
        for suffix in suffixes {
            XCTAssertThrowsError(try SchoolLoginLink.parse(project.absoluteString + suffix, projectURL: project))
        }
    }

    func testErrorsContainNoInputAndInputsAreBounded() {
        let synthetic = "fixture-secret-that-must-not-appear-in-errors"
        do {
            _ = try SchoolLoginLink.parse("https://attacker.test/auth/v1/verify?token=" + synthetic + "&type=email", projectURL: project)
            XCTFail("Foreign link unexpectedly accepted")
        } catch { XCTAssertFalse(error.localizedDescription.contains(synthetic)) }
        XCTAssertThrowsError(try SchoolLoginLink.parse(String(repeating: "a", count: 12_289), projectURL: project))
        XCTAssertThrowsError(try SchoolLoginLink.parse(project.absoluteString + "/auth/v1/verify?token=" + String(repeating: "a", count: 4_097) + "&type=email", projectURL: project))
    }
}
