import Foundation
import Security

struct PrivateCredentialStore {
    static let school = Self(service: "com.cadence.study.supabase-auth")
    static let spotify = Self(service: "com.cadence.study.spotify-auth")
    private let service: String
    private let account = "session-v1"

    // The default group may be shared with widgets. Derive the app's private
    // application-identifier group using the actual signing prefix and bundle ID.
    // No credential is ever put in the temporary probe or in the default group.
    func privateAccessGroup() throws -> String {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else { throw SchoolServiceError.secureStorageUnavailable }
        let probeAccount = UUID().uuidString
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + ".group-probe", kSecAttrAccount as String: probeAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data([0]), kSecReturnAttributes as String: true]
        var result: CFTypeRef?
        guard SecItemAdd(probe as CFDictionary, &result) == errSecSuccess else { throw SchoolServiceError.secureStorageUnavailable }
        _ = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + ".group-probe", kSecAttrAccount as String: probeAccount] as CFDictionary)
        guard let values = result as? [String: Any], let group = values[kSecAttrAccessGroup as String] as? String,
              let prefix = group.split(separator: ".").first, !prefix.isEmpty else { throw SchoolServiceError.secureStorageUnavailable }
        let privateGroup = String(prefix) + "." + bundleID
        let check: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + ".private-probe", kSecAttrAccount as String: probeAccount,
            kSecAttrAccessGroup as String: privateGroup,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data([0])]
        guard SecItemAdd(check as CFDictionary, nil) == errSecSuccess else { throw SchoolServiceError.secureStorageUnavailable }
        _ = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + ".private-probe", kSecAttrAccount as String: probeAccount,
            kSecAttrAccessGroup as String: privateGroup] as CFDictionary)
        return privateGroup
    }

    private func query() throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrAccessGroup as String: try privateAccessGroup(),
         kSecAttrSynchronizable as String: false]
    }

    func read() throws -> Data? {
        var query = try query()
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 262_144 else { throw SchoolServiceError.secureStorageUnavailable }
        return data
    }

    func write(_ data: Data) throws {
        guard data.count <= 262_144 else { throw SchoolServiceError.secureStorageUnavailable }
        let query = try query()
        let changes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw SchoolServiceError.secureStorageUnavailable }
        var attributes = query
        for (key, value) in changes { attributes[key] = value }
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw SchoolServiceError.secureStorageUnavailable }
    }

    func delete() throws {
        let status = SecItemDelete(try query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SchoolServiceError.secureStorageUnavailable }
    }
}
