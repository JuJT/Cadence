import Foundation
import XCTest
@testable import CadenceCore

final class SpotifyConnectionTests: XCTestCase {
    func testPublicContentLinksStripTrackingAndRequireSpotifyHost() throws {
        let id = "0123456789ABCDEFGHIJKL"
        let parsed = try XCTUnwrap(SpotifyContentLink("https://open.spotify.com/intl-fr/track/\(id)?si=example"))
        XCTAssertEqual(parsed.embedURL.absoluteString, "https://open.spotify.com/embed/track/" + id)
        XCTAssertEqual(parsed, SpotifyContentLink("spotify:track:" + id))
        XCTAssertNil(SpotifyContentLink("https://open.spotify.com.elsewhere.example/track/" + id))
        XCTAssertNil(SpotifyContentLink("https://open.spotify.com/track/%3Cinvalid%3E"))
    }

    @MainActor
    func testLoopbackAcceptsOnlyTheMatchingAuthorizationAttempt() async throws {
        let attempt = SpotifyConnection()
        let listener = SpotifyCallbackListener(challenge: attempt)
        let ready = expectation(description: "Loopback listener is ready")
        let received = expectation(description: "The authorized redirect reaches the app")
        var port: UInt16?
        var reply: SpotifyConnection.Callback?
        try listener.start { value in port = value; ready.fulfill() } result: { result in
            switch result {
            case .success(let value): reply = value
            case .failure(let error): XCTFail(error.localizedDescription)
            }
            received.fulfill()
        }
        defer { listener.stop() }

        await fulfillment(of: [ready], timeout: 4)
        let redirect = SpotifyConnection.redirect(port: try XCTUnwrap(port))
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (_, denied) = try await session.data(from: URL(string: redirect + "?state=unrelated&code=code")!)
        XCTAssertEqual((denied as? HTTPURLResponse)?.statusCode, 404)
        let (_, accepted) = try await session.data(from: URL(string: redirect + "?state=" + attempt.state + "&code=example")!)
        XCTAssertEqual((accepted as? HTTPURLResponse)?.statusCode, 200)
        await fulfillment(of: [received], timeout: 4)
        XCTAssertEqual(reply, .authorized("example"))
    }

    func testPKCECallbackRequiresExpectedStateAndPath() throws {
        let attempt = SpotifyConnection()
        let redirect = SpotifyConnection.redirect(port: 50401)
        let url = attempt.authorizeURL(clientID: String(repeating: "1", count: 32), redirect: redirect)
        let terms = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(terms.first { $0.name == "redirect_uri" }?.value, "http://127.0.0.1:50401/spotify/callback")
        XCTAssertEqual(terms.first { $0.name == "code_challenge_method" }?.value, "S256")
        XCTAssertNotEqual(terms.first { $0.name == "code_challenge" }?.value, attempt.verifier)
        XCTAssertEqual(attempt.verifier.count, 43)
        let query = "?state=\(attempt.state)&code=a%2Bb"
        XCTAssertEqual(attempt.callback(requestTarget: SpotifyConnection.callbackPath + query), .authorized("a+b"))
        XCTAssertNil(attempt.callback(requestTarget: "/other" + query))
        XCTAssertNil(SpotifyConnection().callback(requestTarget: SpotifyConnection.callbackPath + query))
        XCTAssertNil(attempt.callback(requestTarget: "//other/spotify/callback" + query))
        XCTAssertNil(attempt.callback(requestTarget: SpotifyConnection.callbackPath + query + "&code=duplicate"))
        XCTAssertEqual(attempt.callback(requestTarget: "/spotify/callback?error=access_denied&state=\(attempt.state)"), .denied)
        XCTAssertEqual(String(decoding: SpotifyConnection.form(["code": "A+B&é"]), as: UTF8.self), "code=A%2BB%26%C3%A9")
    }
}
