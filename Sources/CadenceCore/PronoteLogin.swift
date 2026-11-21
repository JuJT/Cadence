import Foundation

public struct PronoteLoginAddress: Equatable, Sendable {
    public let base: URL

    public init?(_ text: String) {
        guard var components = Self.publicHTTPS(text) else { return nil }
        var path = components.path.split(separator: "/").map(String.init)
        guard path.allSatisfy({ $0 != "." && $0 != ".." }),
              !components.percentEncodedPath.lowercased().contains("%2f"),
              !components.percentEncodedPath.lowercased().contains("%5c"),
              !components.path.contains("\\") else { return nil }
        if let page = path.last?.lowercased(), page.hasSuffix(".html") {
            guard ["index.html", "eleve.html", "mobile.eleve.html"].contains(page) else { return nil }
            path.removeLast()
        }
        components.path = path.isEmpty ? "" : "/" + path.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { return nil }
        base = url
    }

    public var mobileInfo: URL {
        base.appendingPathComponent("InfoMobileApp.json").appending(queryItems: [
            URLQueryItem(name: "id", value: "0D264427-EEFC-4810-A9E9-346942A862A4")
        ])
    }

    public var mobileStudent: URL {
        base.appendingPathComponent("mobile.eleve.html").appending(queryItems: [URLQueryItem(name: "fd", value: "1")])
    }

    public func recognizes(_ url: URL?, as page: URL) -> Bool {
        guard let url, let current = Self.publicHTTPS(url.absoluteString), let trusted = URLComponents(url: page, resolvingAgainstBaseURL: false),
              current.host == trusted.host else { return false }
        return current.path == trusted.path
    }

    public static func publicHTTPS(_ text: String) -> URLComponents? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.utf8.count <= 8_192,
              !clean.utf8.contains(where: { $0 < 32 || $0 == 127 }),
              var components = URLComponents(string: clean),
              components.scheme?.lowercased() == "https", components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(), host.utf8.count <= 253 else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let suffix = labels.last, suffix.utf8.contains(where: { (97...122).contains($0) }),
              !["localhost", "local", "localdomain", "lan", "home", "internal", "intranet", "test", "invalid", "example", "onion", "arpa"].contains(String(suffix)),
              labels.allSatisfy({ label in
                  !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-") &&
                  label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
              }) else { return nil }
        components.scheme = "https"
        components.host = host
        components.port = nil
        return components
    }
}

public struct PronotePairingCode: Sendable {
    public let url: String
    public let login: String
    public let token: String

    private struct Payload: Decodable { let url: String; let login: String; let jeton: String }

    public static func parse(_ text: String) -> Self? {
        guard text.utf8.count <= 8_192, let code = try? JSONDecoder().decode(Payload.self, from: Data(text.utf8)),
              let location = PronoteLoginAddress.publicHTTPS(code.url), location.fragment == nil, location.query == nil,
              let portal = location.url, ["eleve.html", "mobile.eleve.html"].contains(portal.lastPathComponent),
              PronoteLoginAddress(code.url) != nil,
              (1...2_048).contains(code.login.utf8.count), (1...4_096).contains(code.jeton.utf8.count) else { return nil }
        return Self(url: code.url, login: code.login, token: code.jeton)
    }

    public static func isValidPIN(_ value: String) -> Bool {
        value.utf8.count == 4 && value.utf8.allSatisfy { (48...57).contains($0) }
    }
}
