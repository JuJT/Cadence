import Foundation
import Security
import CadenceCore

enum PronoteServiceError: Error, LocalizedError {
    case failure(String), security(PronoteSecurityChallenge)
    var errorDescription: String? {
        switch self {
        case .security: return "PRONOTE demande une vérification de sécurité."
        case .failure(let name):
            switch name {
            case "BadCredentialsError", "AuthenticateError": return "Les identifiants ou le code de sécurité PRONOTE ne sont pas valides."
            case "AccountDisabledError": return "Ce compte est désactivé par l’établissement."
            case "AccessDeniedError", "UnsupportedSection": return "Cette rubrique n’est pas accessible avec ce compte PRONOTE."
            case "UnsupportedNewsFormat": return "Ces informations utilisent un format PRONOTE encore non pris en charge. Les données déjà enregistrées sont conservées."
            case "MissingResource": return "Cet élément ne figure plus parmi ceux partagés par votre établissement. Actualisez la liste."
            case "PageUnavailableError", "BusyPageError": return "L’établissement ne peut pas ouvrir cette rubrique pour le moment. Réessayez dans quelques instants."
            case "SuspendedIPError", "RateLimitedError": return "PRONOTE limite temporairement les connexions. Patientez avant de réessayer."
            case "NotConnected", "InvalidCredential", "SessionExpiredError": return "Reconnectez votre compte PRONOTE. Les données enregistrées restent disponibles."
            case "SecureStorageUnavailable": return "Le trousseau privé n’est pas disponible. Déverrouillez l’iPhone et réessayez."
            case "InvalidURL": return "Choisissez l’adresse HTTPS publique de votre portail PRONOTE."
            case "NetworkUnavailable", "UnreachableError": return "PRONOTE est inaccessible. Le cache hors connexion est conservé."
            case "Busy": return "Une opération PRONOTE est déjà en cours."
            default: return "PRONOTE n’a pas pu terminer cette opération. Réessayez plus tard."
            }
        }
    }
}

/// One rotating credential and one ordered session. Passwords are used only for
/// the initial command; only PRONOTE's device token is stored in private Keychain.
actor PronoteSchoolService {
    private let vault = PronoteCredentialVault()
    private var runtime: PawnoteRuntime?
    private var runtimeHost: String?
    private var profile: PronoteProfile?
    private var validUntil = Date.distantPast
    private var epoch = UUID()
    private var tail: Task<Data, Error>?
    private var operations: [UUID: Task<Data, Error>] = [:]

    var hasSession: Bool { (try? vault.read()) != nil }
    var email: String? { profile?.displayName ?? (try? vault.read())?.username }
    var currentProfile: PronoteProfile? { profile }

    func discover(latitude: Double, longitude: Double) async throws -> [PronoteSchool] {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw PronoteServiceError.failure("InvalidURL")
        }
        let data = try await enqueue("discover", body: ["latitude": latitude, "longitude": longitude], requiresSession: false)
        // Pawnote returns postal codes as numbers. Keep their public display as text.
        let value = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return value.prefix(200).compactMap { entry in
            guard let url = entry["url"] as? String, let name = entry["name"] as? String,
                  (try? Self.portalURL(url)) != nil else { return nil }
            return PronoteSchool(url: url, name: name, latitude: entry["latitude"] as? Double,
                longitude: entry["longitude"] as? Double, postalCode: entry["postalCode"].map { String(describing: $0) },
                distance: entry["distance"] as? Double)
        }
    }

    func connect(url: String, username: String, password: String, kind: Int) async throws -> PronoteProfile {
        let portal = try Self.portalURL(url)
        guard [6, 7].contains(kind), !username.isEmpty, username.utf8.count <= 256,
              !password.isEmpty, password.utf8.count <= 4096 else { throw PronoteServiceError.failure("BadCredentialsError") }
        let expected = try await reset(deleteCredential: false)
        guard expected == epoch else { throw CancellationError() }
        let deviceID = UUID().uuidString
        let body: [String: Any] = ["url": portal.absoluteString, "username": username, "password": password,
                                  "kind": kind, "deviceUUID": deviceID]
        let data = try await enqueue("login", body: body, host: portal.host, requiresSession: false)
        guard expected == epoch else { throw CancellationError() }
        let result = try Self.decode(PronoteProfile.self, data)
        profile = result; validUntil = Date().addingTimeInterval(240)
        return result
    }

    func completeSecurity(pin: String, password: String, source: String, mode: Int?) async throws -> PronoteProfile {
        let expected = epoch
        var body: [String: Any] = ["pin": pin, "password": password, "source": source]
        if let mode { body["mode"] = mode }
        let data = try await enqueue("security", body: body, host: runtimeHost, requiresSession: false)
        guard expected == epoch else { throw CancellationError() }
        let result = try Self.decode(PronoteProfile.self, data)
        profile = result; validUntil = Date().addingTimeInterval(240)
        return result
    }

    func selectResource(_ id: String) async throws -> PronoteProfile {
        let expected = epoch
        let data = try await enqueue("selectResource", body: ["id": id])
        guard expected == epoch else { throw CancellationError() }
        let result = try Self.decode(PronoteProfile.self, data)
        profile = result; return result
    }

    func fetchSnapshot() async throws -> SchoolSnapshot {
        let calendar = SchoolDateCodec.parisCalendar
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -30, to: today)!
        let end = calendar.date(byAdding: .day, value: 31, to: today)!
        let body: [String: Any] = ["start": Self.iso(start), "end": Self.iso(end),
                                  "startDay": Self.schoolDay(start), "endDay": Self.schoolDay(end)]
        return try SchoolSnapshot.decode(await enqueue("snapshot", body: body))
    }

    func fetchSection(_ section: String, periodID: String?) async throws -> SchoolJSON {
        let calendar = SchoolDateCodec.parisCalendar
        let start = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: Date()))!
        let end = calendar.date(byAdding: .day, value: 31, to: calendar.startOfDay(for: Date()))!
        var body: [String: Any] = ["section": section, "start": Self.iso(start), "end": Self.iso(end), "date": Self.iso(Date()),
                                  "startDay": Self.schoolDay(start), "endDay": Self.schoolDay(end), "dateDay": Self.schoolDay(Date())]
        if let periodID { body["periodID"] = periodID }
        return try Self.decode(SchoolJSON.self, await enqueue("section", body: body))
    }

    func fetchThread(_ id: String) async throws -> SchoolJSON { try Self.decode(SchoolJSON.self, await enqueue("discussion", body: ["id": id])) }
    func fetchNewsDetail(_ id: String) async throws -> SchoolJSON { try Self.decode(SchoolJSON.self, await enqueue("newsDetail", body: ["id": id])) }
    func fetchResource(_ id: String) async throws -> (SchoolJSON, [SchoolCourseContent]) {
        let data = try await enqueue("resource", body: ["id": id])
        struct ResourceReply: Decodable { let resource: SchoolJSON; let course_content: [SchoolCourseContent] }
        let reply = try Self.decode(ResourceReply.self, data)
        return (reply.resource, reply.course_content)
    }
    func reply(_ id: String, text: String) async throws { _ = try await enqueue("reply", body: ["id": id, "text": text]) }
    func fetchRecipients() async throws -> SchoolJSON {
        try Self.decode(SchoolJSON.self, await enqueue("recipients", body: ["kind": 3]))
    }
    func compose(recipientIDs: [String], subject: String, text: String) async throws {
        _ = try await enqueue("compose", body: ["kind": 3, "recipientIDs": recipientIDs, "subject": subject, "text": text])
    }
    func acknowledge(_ id: String) async throws { _ = try await enqueue("acknowledge", body: ["id": id]) }
    func signOut() async throws { _ = try await reset(deleteCredential: true) }

    private func enqueue(_ name: String, body: [String: Any], host: String? = nil, requiresSession: Bool = true) async throws -> Data {
        guard operations.count < 16 else { throw PronoteServiceError.failure("Busy") }
        let payload = try JSONSerialization.data(withJSONObject: body)
        let previous = tail, id = UUID(), expected = epoch
        let task = Task<Data, Error> {
            _ = await previous?.result
            try Task.checkCancellation()
            guard expected == self.epoch else { throw CancellationError() }
            if requiresSession { try await self.ensureSession() }
            let answer = try await self.execute(name, payload: payload, host: host ?? self.runtimeHost)
            guard expected == self.epoch else { throw CancellationError() }
            return answer
        }
        operations[id] = task; tail = task
        defer { operations.removeValue(forKey: id); if operations.isEmpty { tail = nil } }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func ensureSession() async throws {
        let expected = epoch
        if profile != nil, validUntil > Date(), runtime != nil { return }
        guard let credential = try vault.read() else { throw PronoteServiceError.failure("NotConnected") }
        let data = try Self.encoder().encode(credential)
        let answer = try await execute("resume", payload: data, host: try Self.portalURL(credential.url).host)
        guard expected == epoch else { throw CancellationError() }
        profile = try Self.decode(PronoteProfile.self, answer)
        validUntil = Date().addingTimeInterval(240)
    }

    private func execute(_ command: String, payload: Data, host: String?) async throws -> Data {
        let expected = epoch
        if runtime == nil || (command != "discover" && runtimeHost != host) {
            await runtime?.invalidate()
            guard expected == epoch else { throw CancellationError() }
            runtimeHost = host
            let generation = vault.generation
            let vault = vault
            runtime = PawnoteRuntime(onCredential: { data in vault.write(data, generation: generation, allowedHost: host) })
        }
        guard let runtime else { throw PronoteServiceError.failure("NotConnected") }
        let bytes = try await runtime.call(command, payload: payload, schoolHost: command == "discover" ? nil : host)
        guard expected == epoch else { throw CancellationError() }
        guard let envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw PronoteServiceError.failure("InvalidCredential") }
        if envelope["ok"] as? Bool != true {
            let error = envelope["error"] as? [String: Any] ?? [:]
            if let challenge = error["challenge"] {
                throw PronoteServiceError.security(try Self.decode(PronoteSecurityChallenge.self, JSONSerialization.data(withJSONObject: challenge)))
            }
            let name = error["name"] as? String ?? "PronoteError"
            if ["SessionExpiredError", "NotConnected"].contains(name) { validUntil = .distantPast; profile = nil }
            throw PronoteServiceError.failure(name)
        }
        return try JSONSerialization.data(withJSONObject: envelope["result"] ?? [:], options: [.fragmentsAllowed])
    }

    private func reset(deleteCredential: Bool) async throws -> UUID {
        epoch = UUID(); let expected = epoch
        var deletionError: Error?
        do { try vault.revoke(delete: deleteCredential) } catch { deletionError = error }
        for task in operations.values { task.cancel() }
        operations.removeAll(); tail = nil
        let previous = runtime; runtime = nil; runtimeHost = nil; profile = nil; validUntil = .distantPast
        await previous?.invalidate()
        if let deletionError { throw deletionError }
        return expected
    }

    static func portalURL(_ text: String) throws -> URL {
        guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme?.lowercased() == "https", c.user == nil, c.password == nil,
              c.port == nil || c.port == 443, let host = c.host?.lowercased(), host.contains("."),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), !host.contains(":"),
              host.range(of: "^[0-9.]+$", options: .regularExpression) == nil, let url = c.url else {
            throw PronoteServiceError.failure("InvalidURL")
        }
        return url
    }
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            guard let date = SchoolDateCodec.date(from: try c.decode(String.self)) else { throw CadenceError.invalidSchoolSnapshot }
            return date
        }
        return try decoder.decode(type, from: data)
    }
    static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    static func schoolDay(_ date: Date) -> String {
        let c = SchoolDateCodec.parisCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

private struct PronoteCredential: Codable {
    let url: String, username: String, token: String, deviceUUID: String
    let kind: Int
    let navigatorIdentifier: String?
    let resourceID: String?
    let tokenState: String?
}

/// A synchronous gate ensures a rotating token is durable before Pawnote sends
/// its next request. Revocation closes the gate before any late JS callback.
private final class PronoteCredentialVault: @unchecked Sendable {
    private let lock = NSLock()
    private var epoch = UUID()
    private var cachedGroup: String?
    private let service = "com.cadence.study.pronote-auth"
    var generation: UUID { lock.lock(); defer { lock.unlock() }; return epoch }
    func read() throws -> PronoteCredential? {
        lock.lock(); defer { lock.unlock() }
        var q = try query(); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 131_072 else { throw PronoteServiceError.failure("SecureStorageUnavailable") }
        let credential = try JSONDecoder().decode(PronoteCredential.self, from: data)
        // An interrupted consuming request must never replay a single-use token.
        return credential.tokenState == "consuming" ? nil : credential
    }
    func write(_ data: Data, generation: UUID, allowedHost: String?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation == epoch, data.count <= 131_072,
              let value = try? JSONDecoder().decode(PronoteCredential.self, from: data),
              let url = try? PronoteSchoolService.portalURL(value.url), url.host?.lowercased() == allowedHost?.lowercased(),
              !value.username.isEmpty, !value.token.isEmpty, UUID(uuidString: value.deviceUUID) != nil,
              [6, 7].contains(value.kind), let query = try? query() else { return false }
        let changes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var insert = query; changes.forEach { insert[$0.key] = $0.value }
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
    func revoke(delete: Bool) throws {
        lock.lock(); defer { lock.unlock() }; epoch = UUID()
        if delete {
            let status = SecItemDelete(try query() as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw PronoteServiceError.failure("SecureStorageUnavailable")
            }
        }
    }
    private func query() throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "device-token-v1", kSecAttrAccessGroup as String: try privateGroup(), kSecAttrSynchronizable as String: false]
    }
    private func privateGroup() throws -> String {
        if let cachedGroup { return cachedGroup }
        guard let bundle = Bundle.main.bundleIdentifier else { throw PronoteServiceError.failure("SecureStorageUnavailable") }
        let account = UUID().uuidString
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service + ".probe",
            kSecAttrAccount as String: account, kSecValueData as String: Data([0]), kSecReturnAttributes as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var result: CFTypeRef?
        guard SecItemAdd(probe as CFDictionary, &result) == errSecSuccess else { throw PronoteServiceError.failure("SecureStorageUnavailable") }
        _ = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service + ".probe", kSecAttrAccount as String: account] as CFDictionary)
        guard let attributes = result as? [String: Any], let current = attributes[kSecAttrAccessGroup as String] as? String,
              let prefix = current.split(separator: ".").first else { throw PronoteServiceError.failure("SecureStorageUnavailable") }
        let group = String(prefix) + "." + bundle
        guard !group.hasPrefix("UNSIGNED00."), !group.contains("*") else { throw PronoteServiceError.failure("SecureStorageUnavailable") }
        cachedGroup = group; return group
    }
}
