import CryptoKit
import Foundation

public struct SpotifyConnection {
    public static let callbackPath = "/spotify/callback"
    public static let registeredRedirect = "http://127.0.0.1" + callbackPath
    public let verifier: String
    public let state: String

    public init() {
        verifier = Self.randomURLToken()
        state = Self.randomURLToken()
    }

    private static func randomURLToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }

    public static func redirect(port: UInt16) -> String {
        "http://127.0.0.1:\(port)" + callbackPath
    }

    public static func validClientID(_ id: String) -> Bool {
        id.utf8.count == 32 && id.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }

    public func authorizeURL(clientID: String, redirect: String) -> URL {
        var url = URLComponents(string: "https://accounts.spotify.com/authorize")!
        url.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "state", value: state),
            .init(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "scope", value: "user-read-playback-state user-modify-playback-state")
        ]
        return url.url!
    }

    public enum Callback: Equatable { case authorized(String), denied }

    public func callback(requestTarget: String) -> Callback? {
        guard let url = URLComponents(string: requestTarget), url.scheme == nil, url.host == nil,
              url.fragment == nil, url.percentEncodedPath == Self.callbackPath,
              let items = url.queryItems else { return nil }
        func values(_ key: String) -> [String] { items.filter { $0.name == key }.compactMap(\.value) }
        guard values("state") == [state] else { return nil }
        if values("error").count == 1 && values("code").isEmpty { return .denied }
        let codes = values("code")
        guard values("error").isEmpty, codes.count == 1, !codes[0].isEmpty else { return nil }
        return .authorized(codes[0])
    }

    public static func form(_ fields: [String: String]) -> Data {
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = fields.sorted { $0.key < $1.key }.map { key, value in
            key.addingPercentEncoding(withAllowedCharacters: safe)! + "=" + value.addingPercentEncoding(withAllowedCharacters: safe)!
        }
        return Data(encoded.joined(separator: "&").utf8)
    }
}
