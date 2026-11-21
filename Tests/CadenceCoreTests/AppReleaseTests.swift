import Foundation
import XCTest
@testable import CadenceCore

final class AppReleaseTests: XCTestCase {
    private let page = "https://github.com/JuJT/Cadence/releases/tag/v0.10.0"
    private let installerURL = "https://github.com/JuJT/Cadence/releases/download/v0.10.0/Cadenza-iPhone-0.10.0.ipa"
    private let hash = String(repeating: "a", count: 64)

    func testStableReleaseUsesNumericComparisonAndCanonicalInstaller() throws {
        let data = try response(assets: [asset(url: installerURL)])

        let result = try AppReleaseCheck.evaluate(status: 200, data: data, installedVersion: "0.9.2")
        guard case .available(let release) = result else { return XCTFail("Expected a newer release") }
        XCTAssertEqual(release.version, "0.10.0")
        XCTAssertEqual(release.page.absoluteString, page)
        XCTAssertEqual(release.notes, "Changements de la version")
        XCTAssertEqual(release.installer?.url.absoluteString, installerURL)
        XCTAssertEqual(release.installer?.sha256, hash)
        XCTAssertEqual(release.installer?.size, 4_059_869)

        for version in ["0.10.0", "0.11.0"] {
            XCTAssertEqual(
                try AppReleaseCheck.evaluate(status: 200, data: data, installedVersion: version),
                .upToDate
            )
        }
    }

    func testUnavailableInstallerStillShowsPublishedRelease() throws {
        let remoteURL = installerURL.replacingOccurrences(of: "github.com", with: "example.com")
        let assetLists: [[[String: Any]]] = [
            [],
            [asset(url: remoteURL)],
            [asset(url: installerURL, state: "new")],
            [asset(url: installerURL, digest: "sha256:truncated")],
        ]
        for assets in assetLists {
            let data = try response(assets: assets)
            let result = try AppReleaseCheck.evaluate(status: 200, data: data, installedVersion: "0.5.0")
            guard case .available(let release) = result else { return XCTFail("Expected release without installer") }
            XCTAssertNil(release.installer)
        }
    }

    func testDraftPrereleaseAndWrongRepositoryAreRejected() throws {
        let responses = [
            try response(overrides: ["draft": true]),
            try response(overrides: ["prerelease": true]),
            try response(overrides: ["tag_name": "v0.10.0-beta"]),
            try response(overrides: ["html_url": page.replacingOccurrences(of: "JuJT", with: "AnotherOwner")]),
        ]
        for data in responses {
            XCTAssertThrowsError(try AppReleaseCheck.evaluate(status: 200, data: data, installedVersion: "0.5.0"))
        }
    }

    func testMissingPublicReleaseIsDistinctFromAnHTTPFailureOrInvalidPayload() throws {
        XCTAssertEqual(
            try AppReleaseCheck.evaluate(status: 404, data: Data(), installedVersion: "0.5.0"),
            .noPublishedRelease
        )
        for status in [200, 403, 429, 503] {
            XCTAssertThrowsError(try AppReleaseCheck.evaluate(status: status, data: Data(), installedVersion: "0.5.0"))
        }
    }

    private func response(assets: [[String: Any]] = [], overrides: [String: Any] = [:]) throws -> Data {
        var fields: [String: Any] = [
            "tag_name": "v0.10.0", "html_url": page, "draft": false, "prerelease": false,
            "body": "  Changements de la version\n", "assets": assets,
        ]
        fields.merge(overrides) { _, replacement in replacement }
        return try JSONSerialization.data(withJSONObject: fields)
    }

    private func asset(url: String, state: String = "uploaded", digest: String? = nil) -> [String: Any] {
        [
            "name": "Cadenza-iPhone-0.10.0.ipa", "browser_download_url": url,
            "state": state, "size": 4_059_869, "digest": digest ?? "sha256:" + hash,
        ]
    }
}
