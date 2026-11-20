import CadenceCore
import SafariServices
import UIKit

/// Keeps the callback local to this device while Spotify opens in Safari's system view.
@MainActor
final class SpotifyAuthorization: NSObject, SFSafariViewControllerDelegate {
    struct Grant {
        let code: String
        let redirect: String
        let verifier: String
    }

    private weak var window: UIWindow?
    private weak var browser: SFSafariViewController?
    private var listener: SpotifyCallbackListener?
    private var continuation: CheckedContinuation<Grant, Error>?
    private var timeout: Task<Void, Never>?

    init(window: UIWindow) { self.window = window }

    func authorize(clientID: String) async throws -> Grant {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Grant, Error>) in
                guard !Task.isCancelled, self.continuation == nil else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                begin(clientID: clientID)
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    func cancel() { complete(.failure(CancellationError())) }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        browser = nil
        cancel()
    }

    private func begin(clientID: String) {
        let attempt = SpotifyConnection()
        let listener = SpotifyCallbackListener(challenge: attempt)
        self.listener = listener
        do {
            try listener.start { [weak self] port in
                guard let self, self.continuation != nil else { return }
                var presenter = self.window?.rootViewController
                while let next = presenter?.presentedViewController { presenter = next }
                guard let presenter, !presenter.isBeingDismissed else {
                    self.complete(.failure(SpotifyError.connection))
                    return
                }
                self.callbackPort = port
                let redirect = SpotifyConnection.redirect(port: port)
                let browser = SFSafariViewController(url: attempt.authorizeURL(clientID: clientID, redirect: redirect))
                browser.delegate = self
                self.browser = browser
                presenter.present(browser, animated: true)
            } result: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(.authorized(let code)):
                    guard let port = self.callbackPort else {
                        self.complete(.failure(SpotifyError.connection))
                        return
                    }
                    self.complete(.success(Grant(code: code, redirect: SpotifyConnection.redirect(port: port), verifier: attempt.verifier)))
                case .success(.denied): self.complete(.failure(SpotifyError.accessDenied))
                case .failure: self.complete(.failure(SpotifyError.connection))
                }
            }
        } catch {
            complete(.failure(SpotifyError.connection))
            return
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(180)) } catch { return }
            self?.complete(.failure(SpotifyError.timedOut))
        }
    }

    private var callbackPort: UInt16?

    private func complete(_ result: Result<Grant, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        listener?.stop()
        listener = nil
        browser?.dismiss(animated: true)
        browser = nil
        continuation.resume(with: result)
    }
}
