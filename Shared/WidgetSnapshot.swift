import Foundation

struct WidgetSnapshot: Codable {
    let updatedAt: Date
    let courseMeasured: Double
    let courseEstimated: Double
    let revisions: Double
    let activeSubject: String?
    let activeKind: String?
    let isPaused: Bool
    let nextCourseTitle: String?
    let nextCourseStart: Date?
}

enum SharedSnapshotStore {
    static var container: URL? {
        #if CADENCE_SHARED_GROUP
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "CadenceAppGroupIdentifier") as? String,
              !identifier.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #else
        return nil
        #endif
    }

    static func read() -> WidgetSnapshot? {
        guard let url = container?.appendingPathComponent("widget-snapshot-v1.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = container?.appendingPathComponent("widget-snapshot-v1.json") else { return false }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }
}

enum CompactDuration {
    static func clock(_ seconds: Double) -> String {
        let value = Int(max(0, seconds).rounded(.down))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    static func text(_ seconds: Double) -> String {
        let minutes = Int(max(0, seconds).rounded(.down)) / 60
        return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }
}
