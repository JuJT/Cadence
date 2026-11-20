import Foundation
import Network

/// One ephemeral IPv4 loopback socket for one Spotify authorization attempt.
@MainActor
public final class SpotifyCallbackListener {
    private let challenge: SpotifyConnection
    private var listener: NWListener?
    private var consumed = false

    public init(challenge: SpotifyConnection) { self.challenge = challenge }

    public func start(ready: @escaping (UInt16) -> Void,
                      result: @escaping (Result<SpotifyConnection.Callback, Error>) -> Void) throws {
        consumed = false
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = try NWListener(using: parameters)
        listener = server
        server.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self, let port = self.listener?.port?.rawValue else { connection.cancel(); return }
                connection.start(queue: .main)
                self.receive(connection, accumulated: Data(), port: port) { callback in result(.success(callback)) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { connection.cancel() }
            }
        }
        server.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.listener != nil else { return }
                switch state {
                case .ready:
                    if let port = self.listener?.port { ready(port.rawValue) }
                case .failed(let error): self.stop(); result(.failure(error))
                default: break
                }
            }
        }
        server.start(queue: .main)
    }

    public func stop() {
        listener?.newConnectionHandler = nil
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
    }

    private func receive(_ socket: NWConnection, accumulated: Data, port: UInt16,
                         result: @escaping (SpotifyConnection.Callback) -> Void) {
        socket.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] chunk, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, let chunk, error == nil, self.listener != nil, !self.consumed,
                      accumulated.count + chunk.count <= 16384 else { socket.cancel(); return }
                let bytes = accumulated + chunk
                guard let headerEnd = bytes.range(of: Data("\r\n\r\n".utf8)) else {
                    if complete { socket.cancel() } else { self.receive(socket, accumulated: bytes, port: port, result: result) }
                    return
                }
                guard let lines = String(data: bytes[..<headerEnd.lowerBound], encoding: .utf8)?.components(separatedBy: "\r\n"),
                      let line = lines.first else { socket.cancel(); return }
                let request = line.split(separator: " ")
                let host = "host: 127.0.0.1:\(port)"
                guard request.count == 3, request[0] == "GET", lines.contains(where: { $0.lowercased() == host }),
                      let callback = self.challenge.callback(requestTarget: String(request[1])) else {
                    self.reply("404 Not Found", on: socket) {}
                    return
                }
                self.consumed = true
                self.reply("200 OK", on: socket) {
                    self.stop()
                    result(callback)
                }
            }
        }
    }

    private func reply(_ status: String, on socket: NWConnection, finished: @escaping () -> Void) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        socket.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            MainActor.assumeIsolated { socket.cancel(); finished() }
        })
    }
}
