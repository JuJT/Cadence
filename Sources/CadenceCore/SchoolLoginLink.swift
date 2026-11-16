import Foundation

public enum SchoolLoginLink {
    public enum Verification: Equatable, Sendable {
        case code(String)
        case tokenHash(String, type: String)
    }

    public enum ValidationError: LocalizedError, Equatable {
        case invalidInput
        public var errorDescription: String? {
            "Code ou lien de connexion invalide. Copiez le code reçu ou le lien complet du message Supabase."
        }
    }

    /// Validate a pasted email link without opening it. The caller posts the
    /// extracted token hash to its own fixed project endpoint, never to this URL.
    public static func parse(_ input: String, projectURL: URL) throws -> Verification {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 12_288 else { throw ValidationError.invalidInput }
        if (6...10).contains(text.utf8.count), text.utf8.allSatisfy({ (48...57).contains($0) }) {
            return .code(text)
        }
        guard projectURL.scheme?.lowercased() == "https", let expectedHost = projectURL.host?.lowercased(),
              projectURL.user == nil, projectURL.password == nil,
              projectURL.port == nil || projectURL.port == 443,
              let parts = URLComponents(string: text), parts.scheme?.lowercased() == "https",
              parts.host?.lowercased() == expectedHost,
              parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              parts.percentEncodedPath == "/auth/v1/verify", parts.fragment == nil else {
            throw ValidationError.invalidInput
        }
        let items = parts.queryItems ?? []
        let hashes = items.filter { $0.name == "token" || $0.name == "token_hash" }
        let types = items.filter { $0.name == "type" }
        guard hashes.count == 1, let hash = hashes.first?.value, !hash.isEmpty, hash.utf8.count <= 4_096,
              !hash.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              types.count == 1, let type = types.first?.value,
              ["email", "magiclink", "signup"].contains(type) else {
            throw ValidationError.invalidInput
        }
        return .tokenHash(hash, type: type)
    }
}
