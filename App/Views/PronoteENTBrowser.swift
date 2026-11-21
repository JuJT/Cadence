import CadenceCore
import SwiftUI
import WebKit

struct PronoteENTRequest: Identifiable {
    let id = UUID()
    let address: PronoteLoginAddress
}

struct PronoteENTBrowser: View {
    let request: PronoteENTRequest
    let onSignIn: (PronoteSignIn) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var currentHost: String?
    @State private var loading = true
    @State private var error: String?
    @State private var attemptID = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Label(currentHost ?? request.address.base.host ?? "Votre établissement", systemImage: "lock")
                    .font(.footnote.weight(.medium)).lineLimit(2)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(.regularMaterial)
                    .accessibilityLabel("Site : \(currentHost ?? request.address.base.host ?? "Votre établissement")")
                if let error {
                    AtelierPage {
                        EmptyCard(title: "Connexion ENT indisponible", symbol: "exclamationmark.shield", description: error)
                        ProminentAction(title: "Réessayer", symbol: "arrow.clockwise") {
                            currentHost = nil; loading = true; self.error = nil; attemptID = UUID()
                        }
                    }
                } else {
                    PronoteENTWebView(request: request, onNavigation: { host, isLoading in
                        currentHost = host; loading = isLoading
                    }, onSignIn: { signIn in
                        onSignIn(signIn)
                    }, onError: { error = $0 })
                        .id(attemptID)
                        .overlay(alignment: .top) {
                            if loading { ProgressView().controlSize(.small).padding(10).allowsHitTesting(false) }
                        }
                }
            }
            .navigationTitle("Connexion ENT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
        }
    }
}

private struct PronoteENTWebView: UIViewRepresentable {
    let request: PronoteENTRequest
    let onNavigation: (String?, Bool) -> Void
    let onSignIn: (PronoteSignIn) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(browser: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: context.coordinator.mobilePageSetup, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: request.address.mobileInfo, cachePolicy: .reloadIgnoringLocalCacheData))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        webView.navigationDelegate = nil
        webView.stopLoading()
        webView.configuration.userContentController.removeAllUserScripts()
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        private let browser: PronoteENTWebView
        private let deviceID = UUID()
        private var pageTask: Task<Void, Never>?
        private var delivered = false
        private var visitedCAS = false

        init(browser: PronoteENTWebView) { self.browser = browser }

        private var address: PronoteLoginAddress { browser.request.address }

        var mobilePageSetup: String {
            let page = address.mobileStudent
            // Only the confirmed PRONOTE origin may receive the native attempt identifier.
            let origin = Self.jsString(page.host ?? "")
            let path = Self.jsString(URLComponents(url: page, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? "")
            return """
            if (location.protocol === 'https:' && location.port === '' && location.hostname === \(origin) && location.pathname === \(path)) {
                window.hookAccesDepuisAppli = function() {
                    this.passerEnModeValidationAppliMobile('', '\(deviceID.uuidString)');
                };
            }
            """
        }

        private static func jsString(_ value: String) -> String {
            let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
            return String(decoding: data, as: UTF8.self)
        }

        func stop() {
            pageTask?.cancel()
            pageTask = nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if navigationAction.targetFrame?.isMainFrame == false, url.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }
            guard PronoteLoginAddress.publicHTTPS(url.absoluteString) != nil else { decisionHandler(.cancel); return }
            if navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                webView.load(navigationAction.request)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
            guard navigationResponse.canShowMIMEType,
                  let url = navigationResponse.response.url,
                  PronoteLoginAddress.publicHTTPS(url.absoluteString) != nil else { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            stop()
            browser.onNavigation(webView.url?.host, true)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            browser.onNavigation(webView.url?.host, true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            browser.onNavigation(webView.url?.host, false)
            stop()
            guard !delivered else { return }
            if address.recognizes(webView.url, as: address.mobileInfo) {
                pageTask = Task { [weak self, weak webView] in
                    if let self, let webView { await self.continueFromMobileInfo(webView) }
                }
            } else if address.recognizes(webView.url, as: address.mobileStudent) {
                pageTask = Task { [weak self, weak webView] in
                    if let self, let webView { await self.waitForSignIn(webView) }
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            navigationFailed(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            navigationFailed(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            browser.onError("La page de connexion s’est arrêtée. Réessayez ou utilisez un QR code PRONOTE.")
        }

        private func navigationFailed(_ error: any Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            browser.onError("La page n’a pas pu être ouverte. Vérifiez votre connexion ou utilisez un QR code PRONOTE.")
        }

        private func continueFromMobileInfo(_ webView: WKWebView) async {
            let value = try? await evaluate(webView, on: address.mobileInfo, "return (document.body?.innerText || '').slice(0, 131072);")
            guard !Task.isCancelled, address.recognizes(webView.url, as: address.mobileInfo) else { return }
            guard let text = value as? String, let info = try? JSONDecoder().decode(MobileInfo.self, from: Data(text.utf8)) else {
                browser.onError("La réponse de l’établissement ne permet pas de poursuivre la connexion ENT. Ouvrez PRONOTE dans votre navigateur habituel pour générer un QR code.")
                return
            }
            guard let cas = info.CAS, cas.actif == true || cas.jetonCAS?.isEmpty == false else {
                browser.onError("Cet établissement ne propose pas d’ENT dans son espace mobile PRONOTE. Choisissez les identifiants PRONOTE ou utilisez un QR code.")
                return
            }
            if let ticket = cas.jetonCAS, !ticket.isEmpty,
               ticket.utf8.count <= 4_096, let encodedTicket = Self.cookieValue(ticket), let host = address.base.host {
                let cookies = webView.configuration.websiteDataStore.httpCookieStore
                let values = ["validationAppliMobile": encodedTicket, "uuidAppliMobile": deviceID.uuidString]
                for (name, value) in values {
                    guard let cookie = HTTPCookie(properties: [.originURL: address.base, .domain: host,
                          .path: address.base.path.isEmpty ? "/" : address.base.path + "/", .name: name, .value: value,
                          .secure: "TRUE", .expires: Date().addingTimeInterval(300)]) else { return }
                    await cookies.setCookie(cookie)
                }
                guard !Task.isCancelled, address.recognizes(webView.url, as: address.mobileInfo) else { return }
                webView.load(URLRequest(url: address.mobileStudent))
            } else if !visitedCAS, let casURL = cas.casURL, let url = PronoteLoginAddress.publicHTTPS(casURL)?.url {
                visitedCAS = true
                webView.load(URLRequest(url: url))
            } else {
                browser.onError("L’établissement n’a pas renvoyé de validation mobile. Connectez-vous à PRONOTE dans votre navigateur habituel pour générer un QR code.")
            }
        }

        private static func cookieValue(_ value: String) -> String? {
            let allowed = CharacterSet(charactersIn: "!#$%&'()*+-./:<>?@[]^_`{|}~=0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
            return value.addingPercentEncoding(withAllowedCharacters: allowed)
        }

        private func waitForSignIn(_ webView: WKWebView) async {
            let setup = """
            if (window.loginState?.status !== 0) {
                window.GInterface?.passerEnModeValidationAppliMobile('', device, '', '', JSON.stringify({model: 'Cadenza iPhone', platform: 'ios'}));
            }
            """
            _ = try? await evaluate(webView, on: address.mobileStudent, setup, arguments: ["device": deviceID.uuidString])
            let readResult = """
            const result = window.loginState;
            if (!result || result.status !== 0 || typeof result.login !== 'string' || typeof result.mdp !== 'string') return null;
            if (result.login.length > 256 || result.mdp.length > 4096) return null;
            return { username: result.login, token: result.mdp };
            """
            for _ in 0..<180 {
                guard !Task.isCancelled, !delivered, address.recognizes(webView.url, as: address.mobileStudent) else { return }
                let value = try? await evaluate(webView, on: address.mobileStudent, readResult)
                guard !Task.isCancelled, !delivered, address.recognizes(webView.url, as: address.mobileStudent) else { return }
                if let result = value as? [String: String], let username = result["username"], !username.isEmpty,
                   let token = result["token"], !token.isEmpty {
                    delivered = true
                    browser.onSignIn(.ent(address: address, device: deviceID, username: username, token: token))
                    return
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
            browser.onError("La validation n’a pas abouti. Vous pouvez recommencer ou scanner un QR code généré depuis votre espace PRONOTE.")
        }

        private func evaluate(_ webView: WKWebView, on page: URL, _ script: String, arguments: [String: Any] = [:]) async throws -> Any? {
            guard let host = page.host, let path = URLComponents(url: page, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return NSNull() }
            var values = arguments
            values["expectedHost"] = host
            values["expectedPath"] = path
            let guardScript = "if (location.protocol !== 'https:' || location.port !== '' || location.hostname !== expectedHost || location.pathname !== expectedPath) return null;"
            return try await webView.callAsyncJavaScript(guardScript + "\n" + script, arguments: values, in: nil, contentWorld: .page)
        }
    }

    private struct MobileInfo: Decodable {
        struct CASInfo: Decodable { let actif: Bool?; let casURL: String?; let jetonCAS: String? }
        let CAS: CASInfo?
    }
}
