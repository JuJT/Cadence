import CadenceCore
import Foundation

enum SchoolServiceError: LocalizedError, Equatable {
    case invalidEmail, invalidLogin, authenticationRequired, notAuthorized, rateLimited
    case networkUnavailable, serviceUnavailable, secureStorageUnavailable, invalidSchoolData
    case signedOutLocally, cancelled

    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Indiquez une adresse e-mail valide pour la connexion scolaire."
        case .invalidLogin: return "Le code ou le lien n’est pas valide, a déjà été utilisé ou a expiré. Demandez un nouveau message."
        case .authenticationRequired: return "Reconnectez votre compte scolaire. Votre cache et vos séances locales sont conservés."
        case .notAuthorized: return "Ce compte n’est pas autorisé à lire ces données scolaires. Utilisez le compte prévu pour Cadenza."
        case .rateLimited: return "Patientez au moins une minute avant une nouvelle demande de connexion, puis réessayez."
        case .networkUnavailable: return "Connexion réseau indisponible. Les cours et devoirs déjà enregistrés restent accessibles."
        case .serviceUnavailable: return "La connexion scolaire est momentanément indisponible. Réessayez plus tard."
        case .secureStorageUnavailable: return "Le trousseau privé de l’app n’est pas accessible. Déverrouillez l’iPhone et réessayez."
        case .invalidSchoolData: return "Les données scolaires reçues ne sont pas valides. Le cache précédent est conservé."
        case .signedOutLocally: return "La connexion a été effacée de cet iPhone. La révocation distante n’a pas pu être confirmée."
        case .cancelled: return "Cette opération de connexion a été annulée."
        }
    }
}

/// Only authenticated reads of the school's fixed Edge Function. Credentials
/// stay in a private application-identifier keychain group, never widget storage.
actor SupabaseSchoolService {
    private struct Session: Codable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let email: String
        let userID: String
    }
    private struct AuthUser: Decodable, Sendable {
        let id: String
        let email: String?
        let isAnonymous: Bool?
        enum CodingKeys: String, CodingKey { case id, email, isAnonymous = "is_anonymous" }
    }
    private struct AuthResponse: Decodable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double?
        let expiresAt: Double?
        let user: AuthUser
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token"
            case expiresIn = "expires_in", expiresAt = "expires_at", user
        }
    }
    private struct RefreshWork {
        let id: UUID
        let task: Task<Session, Error>
    }

    private let network: URLSession
    private var session: Session?
    private var generation = UUID()
    private var refreshWork: RefreshWork?
    private var nextLoginRequestAt: Date?

    init(urlSession: URLSession? = nil) {
        network = urlSession ?? Self.privateURLSession()
        if let data = try? PrivateCredentialStore.school.read(), let stored = try? JSONDecoder().decode(Session.self, from: data),
           !stored.accessToken.isEmpty, !stored.refreshToken.isEmpty, stored.expiresAt.timeIntervalSince1970.isFinite {
            session = stored
        }
    }

    var hasSession: Bool { session != nil }
    var email: String? { session?.email }

    func requestLogin(email: String) async throws {
        let normalized = try Self.normalizedEmail(email)
        if let nextLoginRequestAt, nextLoginRequestAt > Date() { throw SchoolServiceError.rateLimited }
        // Check private storage before consuming an email quota or one-time token.
        _ = try PrivateCredentialStore.school.privateAccessGroup()
        let response = try await send(path: "auth/v1/otp", method: "POST", body: ["email": normalized, "create_user": true], maximumBytes: 262_144)
        if response.status == 429 {
            nextLoginRequestAt = Date().addingTimeInterval(60)
            throw SchoolServiceError.rateLimited
        }
        guard (200..<300).contains(response.status) else { throw Self.authError(response.status, verifying: false) }
        nextLoginRequestAt = Date().addingTimeInterval(60)
    }

    func verifyLogin(email: String, codeOrLink: String) async throws {
        let normalized = try Self.normalizedEmail(email)
        let verification = try SchoolLoginLink.parse(codeOrLink, projectURL: SchoolAPIConfiguration.projectURL)
        let body: [String: Any]
        switch verification {
        case .code(let code): body = ["email": normalized, "token": code, "type": "email"]
        case .tokenHash(let hash, let type): body = ["token_hash": hash, "type": type]
        }
        _ = try PrivateCredentialStore.school.privateAccessGroup()
        let expectedGeneration = generation
        let response = try await send(path: "auth/v1/verify", method: "POST", body: body, maximumBytes: 262_144)
        guard (200..<300).contains(response.status) else { throw Self.authError(response.status, verifying: true) }
        let fresh = try Self.decodeSession(response.data, expectedEmail: normalized)
        guard generation == expectedGeneration else { throw SchoolServiceError.cancelled }
        try PrivateCredentialStore.school.write(JSONEncoder().encode(fresh))
        generation = UUID()
        refreshWork?.task.cancel(); refreshWork = nil
        session = fresh
    }

    func fetchSnapshot() async throws -> SchoolSnapshot {
        let expectedGeneration = generation
        var credential = try await validSession()
        var response = try await send(path: "functions/v1/cadenza-school", method: "GET", accessToken: credential.accessToken,
                                      maximumBytes: BackupCodec.maximumBytes)
        guard generation == expectedGeneration else { throw SchoolServiceError.cancelled }
        if response.status == 401 {
            credential = try await refreshSession(rejecting: credential.accessToken)
            guard generation == expectedGeneration else { throw SchoolServiceError.cancelled }
            response = try await send(path: "functions/v1/cadenza-school", method: "GET", accessToken: credential.accessToken,
                                      maximumBytes: BackupCodec.maximumBytes)
            guard generation == expectedGeneration else { throw SchoolServiceError.cancelled }
        }
        switch response.status {
        case 200..<300:
            do { return try SchoolSnapshot.decode(response.data) }
            catch { throw SchoolServiceError.invalidSchoolData }
        case 401:
            try? clearSession()
            throw SchoolServiceError.authenticationRequired
        case 403: throw SchoolServiceError.notAuthorized
        case 429: throw SchoolServiceError.rateLimited
        default: throw SchoolServiceError.serviceUnavailable
        }
    }

    /// The local credential is removed first. Failure to confirm server logout is
    /// reported separately, instead of pretending revocation worked offline.
    func signOut() async throws {
        let previous = session
        try clearSession()
        guard let previous else { return }
        do {
            let response = try await send(path: "auth/v1/logout", query: [URLQueryItem(name: "scope", value: "local")],
                                          method: "POST", accessToken: previous.accessToken, maximumBytes: 262_144)
            guard (200..<300).contains(response.status) else { throw SchoolServiceError.signedOutLocally }
        } catch { throw SchoolServiceError.signedOutLocally }
    }

    private func validSession() async throws -> Session {
        guard let session else { throw SchoolServiceError.authenticationRequired }
        if session.expiresAt > Date().addingTimeInterval(60) { return session }
        return try await refreshSession(rejecting: nil)
    }

    private func refreshSession(rejecting rejectedToken: String?) async throws -> Session {
        guard let current = session else { throw SchoolServiceError.authenticationRequired }
        if let rejectedToken, current.accessToken != rejectedToken, current.expiresAt > Date().addingTimeInterval(60) { return current }
        if let refreshWork { return try await refreshWork.task.value }
        let id = UUID()
        let expectedGeneration = generation
        let task = Task { try await self.refreshAndPersist(current, expectedGeneration: expectedGeneration) }
        refreshWork = RefreshWork(id: id, task: task)
        defer { if refreshWork?.id == id { refreshWork = nil } }
        return try await task.value
    }

    private func refreshAndPersist(_ previous: Session, expectedGeneration: UUID) async throws -> Session {
        guard generation == expectedGeneration else { throw SchoolServiceError.cancelled }
        let response = try await send(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                      method: "POST", body: ["refresh_token": previous.refreshToken], maximumBytes: 262_144)
        guard generation == expectedGeneration else { throw SchoolServiceError.cancelled }
        guard (200..<300).contains(response.status) else {
            if [400, 401, 403, 422].contains(response.status) {
                try? clearSession()
                throw SchoolServiceError.authenticationRequired
            }
            throw Self.authError(response.status, verifying: false)
        }
        let fresh = try Self.decodeSession(response.data, expectedEmail: previous.email)
        guard fresh.userID == previous.userID else {
            try? clearSession()
            throw SchoolServiceError.authenticationRequired
        }
        try PrivateCredentialStore.school.write(JSONEncoder().encode(fresh))
        session = fresh
        return fresh
    }

    private func clearSession() throws {
        generation = UUID()
        refreshWork?.task.cancel(); refreshWork = nil
        try PrivateCredentialStore.school.delete()
        session = nil
    }

    private static func decodeSession(_ data: Data, expectedEmail: String) throws -> Session {
        guard let value = try? JSONDecoder().decode(AuthResponse.self, from: data),
              !value.accessToken.isEmpty, value.accessToken.utf8.count <= 131_072,
              !value.refreshToken.isEmpty, value.refreshToken.utf8.count <= 16_384,
              value.user.isAnonymous != true, UUID(uuidString: value.user.id) != nil,
              let email = value.user.email, (try? normalizedEmail(email)) == expectedEmail else {
            throw SchoolServiceError.invalidLogin
        }
        let expiration = value.expiresAt ?? value.expiresIn.map { Date().timeIntervalSince1970 + $0 }
        guard let expiration, expiration.isFinite, expiration > Date().timeIntervalSince1970 else { throw SchoolServiceError.invalidLogin }
        return Session(accessToken: value.accessToken, refreshToken: value.refreshToken,
                       expiresAt: Date(timeIntervalSince1970: expiration), email: expectedEmail, userID: value.user.id)
    }

    private static func normalizedEmail(_ value: String) throws -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = clean.split(separator: "@", omittingEmptySubsequences: false)
        guard clean.utf8.count <= 320, parts.count == 2, parts.allSatisfy({ !$0.isEmpty }),
              !clean.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else {
            throw SchoolServiceError.invalidEmail
        }
        return clean
    }

    private static func authError(_ status: Int, verifying: Bool) -> SchoolServiceError {
        if status == 429 { return .rateLimited }
        if verifying, [400, 401, 403, 422].contains(status) { return .invalidLogin }
        return .serviceUnavailable
    }

    private func send(path: String, query: [URLQueryItem] = [], method: String, body: [String: Any]? = nil,
                      accessToken: String? = nil, maximumBytes: Int) async throws -> (data: Data, status: Int) {
        let url = SchoolAPIConfiguration.projectURL.appendingPathComponent(path)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let requestURL = components?.url, requestURL.scheme == "https",
              requestURL.host == SchoolAPIConfiguration.projectURL.host else { throw SchoolServiceError.serviceUnavailable }
        var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(SchoolAPIConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken { request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, response) = try await network.data(for: request)
            guard let http = response as? HTTPURLResponse, data.count <= maximumBytes else { throw SchoolServiceError.serviceUnavailable }
            return (data, http.statusCode)
        } catch is CancellationError { throw SchoolServiceError.cancelled }
        catch let error as SchoolServiceError { throw error }
        catch { throw SchoolServiceError.networkUnavailable }
    }

    private static func privateURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration, delegate: SchoolNoRedirectDelegate(), delegateQueue: nil)
    }
}

private final class SchoolNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
