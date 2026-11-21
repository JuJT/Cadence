import Foundation

public struct AppRelease: Equatable, Sendable {
    public struct Installer: Equatable, Sendable {
        public let name: String
        public let url: URL
        public let size: Int64
        public let sha256: String?
    }

    public let version: String
    public let page: URL
    public let notes: String?
    public let installer: Installer?
}

public enum AppReleaseCheck: Equatable, Sendable {
    case noPublishedRelease
    case upToDate
    case available(AppRelease)

    public static let latestURL = URL(string: "https://api.github.com/repos/JuJT/Cadence/releases/latest")!

    private static let releaseBase = "/JuJT/Cadence/releases/"

    public static func evaluate(status: Int, data: Data, installedVersion: String) throws -> Self {
        if status == 404 { return .noPublishedRelease }
        guard status == 200, data.count <= 1_000_000 else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = release.tag.hasPrefix("v") ? String(release.tag.dropFirst()) : release.tag
        guard !release.draft, !release.prerelease,
              let remote = versionComponents(version),
              let installed = versionComponents(installedVersion),
              isReleaseURL(release.page, path: releaseBase + "tag/" + release.tag) else {
            throw URLError(.cannotParseResponse)
        }
        guard installed.lexicographicallyPrecedes(remote) else { return .upToDate }

        let installerName = "Cadenza-iPhone-\(version).ipa"
        let installer = release.assets?.first { asset in
            asset.name == installerName && asset.state == "uploaded" && asset.size > 0
                && isReleaseURL(asset.url, path: releaseBase + "download/" + release.tag + "/" + installerName)
        }.flatMap { asset -> AppRelease.Installer? in
            let hash = asset.digest?.lowercased()
            let prefix = "sha256:"
            if let hash, hash.range(of: "^sha256:[0-9a-f]{64}$", options: .regularExpression) == nil {
                return nil
            }
            return AppRelease.Installer(
                name: asset.name, url: asset.url, size: asset.size,
                sha256: hash.map { String($0.dropFirst(prefix.count)) }
            )
        }
        let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .available(AppRelease(
            version: version, page: release.page, notes: notes.flatMap { $0.isEmpty ? nil : $0 },
            installer: installer
        ))
    }

    private static func versionComponents(_ version: String) -> [Int]? {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3, components.allSatisfy({ component in
            !component.isEmpty && component.utf8.allSatisfy { (48...57).contains($0) }
        }) else { return nil }
        let numbers = components.compactMap { Int($0) }
        return numbers.count == components.count ? numbers : nil
    }

    private static func isReleaseURL(_ url: URL, path: String) -> Bool {
        url.absoluteString == "https://github.com" + path
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let state: String
        let size: Int64
        let url: URL
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, state, size, digest
            case url = "browser_download_url"
        }
    }

    let tag: String
    let page: URL
    let draft: Bool
    let prerelease: Bool
    let body: String?
    let assets: [Asset]?

    enum CodingKeys: String, CodingKey {
        case draft, prerelease, body, assets
        case tag = "tag_name"
        case page = "html_url"
    }
}
