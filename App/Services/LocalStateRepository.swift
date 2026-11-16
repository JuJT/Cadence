import Foundation
import CadenceCore

/// Un seul écrivain : AppStore, sur MainActor. Les App Intents ouvrent le même
/// processus ; l'extension ne reçoit qu'une copie minimale, jamais cette base.
struct LocalStateRepository {
    let url: URL

    init(directory: URL? = nil) throws {
        let base = try directory ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("Cadence", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("cadence-state.json")
    }

    func load() throws -> CadenceState {
        guard FileManager.default.fileExists(atPath: url.path) else { return .initial() }
        let data = try Data(contentsOf: url)
        if let header = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = header["schemaVersion"] as? Int, version < 3 {
            let beforeSchool = url.deletingLastPathComponent().appendingPathComponent("cadence-before-school-v3.json")
            if !FileManager.default.fileExists(atPath: beforeSchool.path) {
                try data.write(to: beforeSchool, options: .atomic)
            }
        }
        return try BackupCodec.decode(data)
    }

    func save(_ state: CadenceState) throws {
        let data = try BackupCodec.encode(state)
        // Une génération antérieure récupérable, et remplacement atomique.
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            try previous.write(to: url.deletingLastPathComponent().appendingPathComponent("cadence-previous.json"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}
