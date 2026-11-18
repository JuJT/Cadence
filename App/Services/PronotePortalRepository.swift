import Foundation
import CadenceCore

/// Re-fetchable school cache, kept separate from personal study history and all credentials.
actor PronotePortalRepository {
    private var cachedURL: URL?
    private func url() throws -> URL {
        if let cachedURL { return cachedURL }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("Cadence", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = directory.appendingPathComponent("pronote-portal.json"); cachedURL = result; return result
    }
    func load() throws -> PronotePortalCache {
        let path = try url()
        guard FileManager.default.fileExists(atPath: path.path) else { return .init() }
        let data = try Data(contentsOf: path)
        guard data.count <= BackupCodec.maximumBytes else { throw CadenceError.invalidSchoolSnapshot }
        return try PronoteSchoolService.decode(PronotePortalCache.self, data)
    }
    func save(_ cache: PronotePortalCache) throws {
        let data = try PronoteSchoolService.encoder().encode(cache)
        guard data.count <= BackupCodec.maximumBytes else { throw CadenceError.invalidSchoolSnapshot }
        try data.write(to: url(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
