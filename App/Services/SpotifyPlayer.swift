import CadenceCore
import Foundation
import SwiftUI

enum SpotifyError: LocalizedError {
    case connection, timedOut, accessDenied, expired, device, restricted, rateLimited, unavailable
    var errorDescription: String? {
        switch self {
        case .connection: return "La connexion Spotify n’a pas pu s’ouvrir. Réessayez."
        case .timedOut: return "Le délai de connexion est écoulé. Recommencez la connexion."
        case .accessDenied: return "Spotify a refusé la connexion. Vérifiez les réglages de votre application Spotify."
        case .expired: return "Votre autorisation Spotify a expiré. Reconnectez votre compte."
        case .device: return "Lancez un morceau sur un appareil Spotify Connect, puis actualisez."
        case .restricted: return "Spotify a refusé la commande. Vérifiez l’accès Premium, le compte autorisé et l’appareil actif."
        case .rateLimited: return "Spotify demande de patienter avant la prochaine actualisation."
        case .unavailable: return "Spotify est indisponible. Réessayez dans un instant."
        }
    }
}

struct SpotifyPlayback: Decodable {
    struct Device: Decodable { let name: String?; let isRestricted: Bool? }
    struct Item: Decodable {
        struct Credit: Decodable { let name: String? }
        let name: String?
        let artists: [Credit]?
        let show: Credit?
        let externalUrls: [String: String]?
        var credit: String? { artists?.compactMap(\.name).joined(separator: ", ") ?? show?.name }
        var spotifyURL: URL? {
            guard let raw = externalUrls?["spotify"], let url = URL(string: raw),
                  url.scheme == "https", url.host == "open.spotify.com" else { return nil }
            return url
        }
    }
    let device: Device?
    let item: Item?
    let isPlaying: Bool
}

@MainActor
final class SpotifyPlayer: ObservableObject {
    static let shared = SpotifyPlayer()
    enum Command: String { case play, pause, previous, next }

    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var playback: SpotifyPlayback?
    @Published private(set) var message: String?
    @Published var clientID = UserDefaults.standard.string(forKey: "music.spotify.clientID") ?? ""

    private struct Account: Codable {
        let clientID: String
        let refreshToken: String
    }
    private struct Tokens: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
    }
    private let network = URLSession(configuration: .ephemeral)
    private var account: Account?
    private var token = ""
    private var expires = Date.distantPast
    private var retryAfter = Date.distantPast
    private var authorization: SpotifyAuthorization?
    private var didRestore = false

    private init() {}

    func restore() {
        guard !didRestore else { return }
        do {
            if let data = try PrivateCredentialStore.spotify.read() {
                let saved = try JSONDecoder().decode(Account.self, from: data)
                account = saved
                clientID = saved.clientID
                connected = true
            }
            didRestore = true
        } catch { message = "Le trousseau Spotify est indisponible. Déverrouillez l’iPhone, puis réessayez." }
    }

    func connect() async {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, SpotifyConnection.validClientID(id) else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }), let window = scene.keyWindow else {
            message = SpotifyError.connection.localizedDescription
            return
        }
        busy = true
        message = nil
        defer { busy = false; authorization = nil }
        let flow = SpotifyAuthorization(window: window)
        authorization = flow
        do {
            UserDefaults.standard.set(id, forKey: "music.spotify.clientID")
            let grant = try await flow.authorize(clientID: id)
            try await exchange(["grant_type": "authorization_code", "code": grant.code,
                                "redirect_uri": grant.redirect, "code_verifier": grant.verifier], clientID: id)
            try await readPlayback()
        } catch is CancellationError {} catch { message = error.localizedDescription }
    }

    func cancelAuthorization() { authorization?.cancel() }

    func disconnect() {
        guard !busy else { return }
        do { try clear(); message = nil }
        catch { message = "Le trousseau n’a pas pu supprimer la connexion Spotify. Réessayez." }
    }

    private func clear() throws {
        try PrivateCredentialStore.spotify.delete()
        account = nil
        token = ""
        expires = .distantPast
        playback = nil
        retryAfter = .distantPast
        connected = false
    }

    func refresh() async { await perform(nil) }
    func send(_ command: Command) async { await perform(command) }

    private func perform(_ command: Command?) async {
        guard connected, !busy, Date() >= retryAfter else { return }
        busy = true
        defer { busy = false }
        do {
            if let command {
                let method = (command == .play || command == .pause) ? "PUT" : "POST"
                _ = try await playerRequest(path: "/" + command.rawValue, method: method)
                // Spotify applies transport commands asynchronously.
                try await Task.sleep(for: .milliseconds(350))
            }
            try await readPlayback()
            message = nil
        } catch is CancellationError {} catch let error as URLError where error.code == .cancelled {
        } catch { message = error.localizedDescription }
    }

    private func readPlayback() async throws {
        let data = try await playerRequest(path: "?additional_types=track,episode", method: "GET")
        playback = data.isEmpty ? nil : try Self.decode(SpotifyPlayback.self, from: data)
    }

    private func playerRequest(path: String, method: String) async throws -> Data {
        guard let account else { throw SpotifyError.expired }
        for attempt in 0...1 {
            if Date() >= expires {
                try await exchange(["grant_type": "refresh_token", "refresh_token": self.account?.refreshToken ?? account.refreshToken], clientID: account.clientID)
            }
            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player" + path)!)
            request.httpMethod = method
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let (data, response) = try await network.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SpotifyError.unavailable }
            switch http.statusCode {
            case 200..<300: return data
            case 401 where attempt == 0: expires = .distantPast
            case 401: try clear(); throw SpotifyError.expired
            case 403: throw SpotifyError.restricted
            case 404: playback = nil; throw SpotifyError.device
            case 429:
                let delay = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
                retryAfter = Date().addingTimeInterval(max(1, delay))
                throw SpotifyError.rateLimited
            default: throw SpotifyError.unavailable
            }
        }
        throw SpotifyError.expired
    }

    private func exchange(_ fields: [String: String], clientID id: String) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpotifyConnection.form(fields.merging(["client_id": id]) { _, new in new })
        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyError.unavailable }
        if http.statusCode == 400 || http.statusCode == 401 {
            if fields["grant_type"] == "refresh_token" {
                try clear()
                throw SpotifyError.expired
            }
            throw SpotifyError.accessDenied
        }
        guard http.statusCode == 200 else { throw SpotifyError.unavailable }
        let tokens = try Self.decode(Tokens.self, from: data)
        guard !tokens.accessToken.isEmpty, let refresh = tokens.refreshToken ?? account?.refreshToken,
              !refresh.isEmpty else { throw SpotifyError.expired }
        let next = Account(clientID: id, refreshToken: refresh)
        if account?.refreshToken != refresh || account?.clientID != id {
            try PrivateCredentialStore.spotify.write(JSONEncoder().encode(next))
        }
        account = next
        token = tokens.accessToken
        expires = Date().addingTimeInterval(TimeInterval(max(0, tokens.expiresIn - 30)))
        connected = true
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}
