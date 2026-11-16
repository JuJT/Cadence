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
    static var transportDiagnostic: String { KeychainSnapshotStore.diagnostic }
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
    private static let diagnostics = KeychainDiagnostics()

    static var diagnostic: String { diagnostics.summary }

    // Keep the complete group returned by iOS. Re-signers can change more than the
    // prefix, so rebuilding "prefix + expected suffix" loses valid shared groups.
    private static func defaultAccessGroup() -> String? {
        if let cached = diagnostics.defaultGroup { return cached }
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
              !group.isEmpty else { return nil }
        diagnostics.rememberDefault(group)
        return group
    }

    private static func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.cadence.widget-summary",
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    private static func candidateGroups() -> [String] {
        var groups: [String] = []
        if let group = defaultAccessGroup() {
            groups.append(group)
            // Compatibility with snapshots published by 0.2.0. This is only an
            // attempted destination: Security still checks the actual entitlement.
            if let prefix = group.split(separator: ".").first {
                groups.append(String(prefix) + ".com.cadence.study.widget-summary")
            }
        }
        // A profile is not proof of an executable entitlement. Only exact groups
        // belonging to this app are candidates; every write is checked by iOS.
        if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: url),
           let start = data.range(of: Data("<plist".utf8)),
           let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
           let profile = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], options: [], format: nil) as? [String: Any],
           let entitlements = profile["Entitlements"] as? [String: Any],
           let values = entitlements["keychain-access-groups"] as? [String] {
            groups.append(contentsOf: values.filter { $0.localizedCaseInsensitiveContains("cadence") })
        }
        var unique = Set<String>()
        return groups.filter {
            !$0.isEmpty && $0.count <= 512 && !$0.contains("*") &&
            !$0.hasPrefix("UNSIGNED00.") && unique.insert($0).inserted
        }.prefix(12).map { $0 }
    }

    static func read(account: String = "snapshot-v1") -> Data? {
        #if CADENCE_KEYCHAIN_SHARED
        // Omitting the group searches every group actually allowed by the signed
        // executable, while service/account remain exact. No unrelated items match.
        var attributes = query(account: account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess else { return nil }
        let values = (result as? [Data]) ?? (result as? Data).map { [$0] } ?? []
        // Several previously signed destinations can remain accessible after an
        // update. Prefer the newest valid copy rather than the first keychain hit.
        if account == "snapshot-v1" {
            return values.compactMap { data -> (Date, Data)? in
                guard data.count <= 16_384, let value = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return nil }
                return (value.updatedAt, data)
            }.max { $0.0 < $1.0 }?.1
        }
        return values.compactMap { data -> (Date, Data)? in
            guard let value = try? JSONDecoder().decode(Date.self, from: data) else { return nil }
            return (value, data)
        }.max { $0.0 < $1.0 }?.1
        #else
        return nil
        #endif
    }

    static func write(_ data: Data, account: String = "snapshot-v1") -> Bool {
        #if CADENCE_KEYCHAIN_SHARED
        // A small local aggregate, never credentials or the complete study database.
        guard data.count <= 16_384 else { return false }
        let groups = candidateGroups()
        let candidates: [String?] = groups.isEmpty ? [nil] : groups.map { Optional($0) }
        var successes = 0
        var lastStatus: OSStatus = errSecItemNotFound
        for group in candidates {
            var attributesQuery = query(account: account)
            if let group { attributesQuery[kSecAttrAccessGroup as String] = group }
            let status = write(data, query: attributesQuery)
            if status == errSecSuccess { successes += 1 }
            else { lastStatus = status }
        }
        if account == "snapshot-v1" { diagnostics.recordWrite(successes: successes, status: lastStatus) }
        return successes > 0
        #else
        return false
        #endif
    }

    private static func write(_ data: Data, query attributesQuery: [String: Any]) -> OSStatus {
        let changes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(attributesQuery as CFDictionary, changes as CFDictionary)
        if status == errSecSuccess { return status }
        guard status == errSecItemNotFound else { return status }
        var attributes = attributesQuery
        for (key, value) in changes { attributes[key] = value }
        return SecItemAdd(attributes as CFDictionary, nil)
    }
}

private final class KeychainDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedGroup: String?
    private var destinationCount: Int?
    private var failureStatus: OSStatus?

    var defaultGroup: String? {
        lock.lock(); defer { lock.unlock() }
        return cachedGroup
    }
    func rememberDefault(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        cachedGroup = value
    }
    func recordWrite(successes: Int, status: OSStatus) {
        lock.lock(); defer { lock.unlock() }
        destinationCount = successes
        failureStatus = successes == 0 ? status : nil
    }
    var summary: String {
        lock.lock(); defer { lock.unlock() }
        guard let destinationCount else { return "Trousseau : aucune publication tentée dans ce processus." }
        if destinationCount > 0 {
            return "Résumé écrit dans \(destinationCount) destination(s) autorisée(s) par iOS. Cela ne prouve pas encore l’accès de l’extension."
        }
        return "Écriture du résumé refusée par iOS (OSStatus \(failureStatus ?? errSecNotAvailable)). Les groupes privés ne sont jamais contournés."
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
