import ActivityKit
import CryptoKit
import ExpoModulesCore
import Foundation
import WidgetKit

public final class CadenzaStudyModule: Module {
    public func definition() -> ModuleDefinition {
        Name("CadenzaStudy")

        AsyncFunction("previewRoute") { () -> String? in
            #if targetEnvironment(simulator)
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "--cadenza-preview"), arguments.indices.contains(flag + 1) {
                return arguments[flag + 1]
            }
            #endif
            return nil
        }

        AsyncFunction("readLegacyStudyState") { () throws -> String? in
            guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
            let url = directory.appendingPathComponent("Cadence/cadence-state.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            return try String(contentsOf: url, encoding: .utf8)
        }

        AsyncFunction("readLegacyNotificationPreference") { () -> Bool? in
            UserDefaults.standard.object(forKey: "cadenza.timetable.notify") as? Bool
        }

        AsyncFunction("syncStudySurface") { (serialized: String) async throws in
            guard serialized.utf8.count <= 65536 else { throw CocoaError(.fileReadTooLarge) }
            let snapshot = try JSONDecoder().decode(CadenzaStudySnapshot.self, from: Data(serialized.utf8))
            await CadenzaSurfaceCoordinator.shared.update(snapshot)
        }

        AsyncFunction("getStudyDiagnostics") { () -> [String: Bool] in
            ["sharedContainer": CadenzaWidgetStore.snapshotURL != nil,
             "liveActivities": ActivityAuthorizationInfo().areActivitiesEnabled]
        }

        AsyncFunction("verifyUpdateFile") { (uri: String, size: Double, digest: String?) throws -> Bool in
            guard let url = URL(string: uri), url.isFileURL, url.pathExtension == "ipa",
                  let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                  url.resolvingSymlinksInPath().path.hasPrefix(cache.resolvingSymlinksInPath().path + "/"),
                  let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, Double(bytes) == size else { return false }
            guard let digest else { return true }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var hash = SHA256()
            while let block = try file.read(upToCount: 128 * 1024), !block.isEmpty { hash.update(data: block) }
            return hash.finalize().map { String(format: "%02x", $0) }.joined() == digest
        }
    }
}

private actor CadenzaSurfaceCoordinator {
    static let shared = CadenzaSurfaceCoordinator()
    private var revision = 0

    func update(_ snapshot: CadenzaStudySnapshot) async {
        revision += 1
        let request = revision
        if let url = CadenzaWidgetStore.snapshotURL, let data = try? JSONEncoder().encode(snapshot) {
            do {
                let previous = try? Data(contentsOf: url)
                if previous != data {
                    try data.write(to: url, options: .atomic)
                    WidgetCenter.shared.reloadTimelines(ofKind: CadenzaWidgetStore.todayKind)
                    WidgetCenter.shared.reloadTimelines(ofKind: CadenzaWidgetStore.weekKind)
                }
            } catch { /* An unavailable App Group does not prevent Live Activities. */ }
        }

        let active = snapshot.activeSession
        let activities = Activity<CadenzaRevisionAttributes>.activities
        for activity in activities where activity.attributes.id != active?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
            guard request == revision else { return }
        }
        guard let active, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = CadenzaRevisionAttributes.ContentState(title: String(active.title.prefix(120)),
            kind: active.kind, elapsedSeconds: max(0, active.elapsedSeconds), paused: active.paused,
            start: Date(timeIntervalSince1970: active.effectiveStartedAt / 1000))
        let content = ActivityContent(state: state, staleDate: nil)
        if let current = activities.first(where: { $0.attributes.id == active.id }) {
            await current.update(content)
        } else {
            _ = try? Activity.request(attributes: CadenzaRevisionAttributes(id: active.id), content: content, pushType: nil)
        }
    }
}
