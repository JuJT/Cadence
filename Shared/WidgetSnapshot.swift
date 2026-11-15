import Foundation
import Security

struct WidgetDaySummary: Codable, Identifiable {
    let date: Date
    let courses: Double
    let revisions: Double
    let estimated: Double
    var id: Date { date }
    var measured: Double { courses + revisions }
}

struct WidgetCourseSummary: Codable {
    let title: String
    let start: Date
    let end: Date
}

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
    // Optional additions keep already-published v1 snapshots readable after an update.
    let weekDays: [WidgetDaySummary]?
    let topSubjectName: String?
    let upcomingCourses: [WidgetCourseSummary]?

    init(updatedAt: Date, courseMeasured: Double, courseEstimated: Double, revisions: Double,
         activeSubject: String?, activeKind: String?, isPaused: Bool,
         nextCourseTitle: String?, nextCourseStart: Date?, weekDays: [WidgetDaySummary]? = nil,
         topSubjectName: String? = nil, upcomingCourses: [WidgetCourseSummary]? = nil) {
        self.updatedAt = updatedAt; self.courseMeasured = courseMeasured
        self.courseEstimated = courseEstimated; self.revisions = revisions
        self.activeSubject = activeSubject; self.activeKind = activeKind; self.isPaused = isPaused
        self.nextCourseTitle = nextCourseTitle; self.nextCourseStart = nextCourseStart
        self.weekDays = weekDays; self.topSubjectName = topSubjectName; self.upcomingCourses = upcomingCourses
    }
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
        if let url = container?.appendingPathComponent("widget-snapshot-v1.json"),
           let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            acknowledgeWidgetRead()
            return snapshot
        }
        guard let data = KeychainSnapshotStore.read(),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return nil }
        acknowledgeWidgetRead()
        return snapshot
    }

    static var lastWidgetReadAt: Date? {
        let data: Data?
        if let url = container?.appendingPathComponent("widget-read-v1.json") { data = try? Data(contentsOf: url) }
        else { data = KeychainSnapshotStore.read(account: "widget-read-v1") }
        guard let data else { return nil }
        return try? JSONDecoder().decode(Date.self, from: data)
    }

    private static func acknowledgeWidgetRead() {
        // A receipt from the extension distinguishes publication from a verified read.
        // App reads and standalone serialization tests cannot create this receipt.
        guard Bundle.main.bundleURL.pathExtension == "appex", let data = try? JSONEncoder().encode(Date()) else { return }
        if let url = container?.appendingPathComponent("widget-read-v1.json") {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else { _ = KeychainSnapshotStore.write(data, account: "widget-read-v1") }
    }

    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        do {
            let data = try JSONEncoder().encode(snapshot)
            if let url = container?.appendingPathComponent("widget-snapshot-v1.json") {
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                return true
            }
            return KeychainSnapshotStore.write(data)
        } catch { return false }
    }
}

private enum KeychainSnapshotStore {
    // Derive the real signing prefix from an item created in the signed default group.
    // This survives re-signing and bundle-ID changes, without SecTask/private APIs or
    // assumptions about a Team ID. The explicit shared group is still enforced by iOS.
    private static func accessGroup() -> String? {
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.cadence.widget-group-probe",
            kSecAttrAccount as String: UUID().uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data([0]), kSecReturnAttributes as String: true]
        var result: CFTypeRef?
        guard SecItemAdd(probe as CFDictionary, &result) == errSecSuccess else { return nil }
        var deletion = probe
        deletion.removeValue(forKey: kSecReturnAttributes as String)
        deletion.removeValue(forKey: kSecValueData as String)
        deletion.removeValue(forKey: kSecAttrAccessible as String)
        _ = SecItemDelete(deletion as CFDictionary)
        guard let attributes = result as? [String: Any],
              let group = attributes[kSecAttrAccessGroup as String] as? String,
              let prefix = group.split(separator: ".").first, !prefix.isEmpty else { return nil }
        return String(prefix) + ".com.cadence.study.widget-summary"
    }

    private static func query(group: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.cadence.widget-summary",
         kSecAttrAccount as String: account,
         kSecAttrAccessGroup as String: group,
         kSecAttrSynchronizable as String: false]
    }

    static func read(account: String = "snapshot-v1") -> Data? {
        #if CADENCE_KEYCHAIN_SHARED
        guard let group = accessGroup() else { return nil }
        var attributes = query(group: group, account: account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
        #else
        return nil
        #endif
    }

    static func write(_ data: Data, account: String = "snapshot-v1") -> Bool {
        #if CADENCE_KEYCHAIN_SHARED
        // A small local aggregate, never credentials or the complete study database.
        guard data.count <= 16_384 else { return false }
        guard let group = accessGroup() else { return false }
        let attributesQuery = query(group: group, account: account)
        let changes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(attributesQuery as CFDictionary, changes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var attributes = attributesQuery
        for (key, value) in changes { attributes[key] = value }
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
        #else
        return false
        #endif
    }
}

enum CompactDuration {
    static func clock(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? min(max(0, seconds), 3_155_760_000_000) : 0
        let value = Int(safe.rounded(.down))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    static func text(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? min(max(0, seconds), 3_155_760_000_000) : 0
        let minutes = Int(safe.rounded(.down)) / 60
        return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }
}
