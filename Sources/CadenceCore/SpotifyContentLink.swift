import Foundation

public struct SpotifyContentLink: Equatable {
    private let kind: String
    private let id: String

    public init?(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var components: [String]
        if text.hasPrefix("spotify:") {
            components = text.split(separator: ":", omittingEmptySubsequences: false).dropFirst().map(String.init)
        } else {
            guard let url = URLComponents(string: text), url.scheme == "https",
                  url.host?.lowercased() == "open.spotify.com", url.port == nil,
                  url.user == nil, url.password == nil else { return nil }
            components = url.path.split(separator: "/").map(String.init)
            if components.first?.hasPrefix("intl-") == true { components.removeFirst() }
            if components.first == "embed" { components.removeFirst() }
        }
        guard components.count == 2, ["track", "playlist", "album", "episode", "show", "artist"].contains(components[0]),
              components[1].utf8.count == 22, components[1].utf8.allSatisfy({
                  (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
              }) else { return nil }
        kind = components[0]
        id = components[1]
    }

    public var url: URL { URL(string: "https://open.spotify.com/\(kind)/\(id)")! }
    public var embedURL: URL { URL(string: "https://open.spotify.com/embed/\(kind)/\(id)")! }
    public var compact: Bool { kind == "track" || kind == "episode" }
}
