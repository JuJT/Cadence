import Combine
import Foundation
import UIKit

/// Leaves the other app's Now Playing session alone; this service only manages
/// the explicit, user-installed Concentration shortcut.
@MainActor
final class SessionCompanionService: NSObject, ObservableObject {
    static let shared = SessionCompanionService()
    // Keep the original imported name: this is an audited, unmodified signed
    // MIT artifact. Renaming or modifying its payload would need re-signing.
    static let preparedShortcutName = "HongMix Focus"

    @Published var focusEnabled = UserDefaults.standard.bool(forKey: "cadence.companion.focusEnabled") {
        didSet {
            UserDefaults.standard.set(focusEnabled, forKey: "cadence.companion.focusEnabled")
            if !focusEnabled, managedFocusSessionID != nil { enqueueFocus(.disable, sessionID: nil) }
        }
    }
    private let focusShortcutName = SessionCompanionService.preparedShortcutName
    @Published private(set) var preparedShortcutVerified = UserDefaults.standard.bool(forKey: "cadence.companion.preparedFocusVerified.v2")
    @Published private(set) var focusStatusText = "Ajoutez le raccourci prêt à l’emploi, puis testez-le une fois."
    @Published private(set) var activeSessionID: UUID?

    private enum FocusCommand: String {
        case enable = "on", disable = "off", probe = "probe", checkBeforeEnable = "status"
    }
    private struct FocusRequest {
        let token: UUID
        let command: FocusCommand
        let sessionID: UUID?
        let automatic: Bool
    }
    private var pendingFocusRequest: FocusRequest?
    private var launchedFocusRequest: FocusRequest?
    private var managedFocusSessionID = UserDefaults.standard.string(forKey: "cadence.companion.managedFocusSession").flatMap(UUID.init(uuidString:))
    private var notificationToken: NSObjectProtocol?

    var canEndManagedFocus: Bool { managedFocusSessionID != nil }

    /// Only the signed build artifact is offered. An unsigned source plist must
    /// never be presented as importable. Shortcuts verifies the actual signature.
    var preparedShortcutURL: URL? {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: Self.preparedShortcutName, withExtension: "shortcut", subdirectory: "Shortcuts")
                ?? bundle.url(forResource: Self.preparedShortcutName, withExtension: "shortcut"),
              let stream = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? stream.close() }
        guard let prefix = try? stream.read(upToCount: 4), prefix == Data("AEA1".utf8) else { return nil }
        return url
    }

    private override init() {
        super.init()
        notificationToken = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applicationBecameActive() }
        }
    }

    // Restore the baseline without opening another app at launch.
    func synchronizeExistingSession(activeSessionID: UUID?) {
        self.activeSessionID = activeSessionID
        if activeSessionID == nil, managedFocusSessionID != nil {
            focusStatusText = "La précédente séance est terminée. Vous pouvez désactiver son mode Concentration."
        }
    }

    // Call only after a persisted active-session identity change. A pause keeps
    // the same identity and leaves Concentration unchanged.
    func sessionDidChange(activeSessionID newID: UUID?) {
        guard activeSessionID != newID else { return }
        activeSessionID = newID
        if let newID, focusEnabled, preparedShortcutVerified {
            enqueueFocus(.checkBeforeEnable, sessionID: newID, automatic: true)
        }
        else if newID == nil {
            pendingFocusRequest = nil
            if managedFocusSessionID != nil { enqueueFocus(.disable, sessionID: nil) }
        }
    }

    func verifyPreparedFocusShortcut() {
        enqueueFocus(.probe, sessionID: nil)
    }

    func enableFocusForCurrentSession() {
        guard let activeSessionID else { return }
        guard preparedShortcutVerified else { return }
        enqueueFocus(.checkBeforeEnable, sessionID: activeSessionID)
    }

    func disableManagedFocus() {
        guard managedFocusSessionID != nil else {
            focusStatusText = "Aucun mode activé par Cadenza n’est enregistré. Un mode choisi ailleurs reste sous votre contrôle."
            return
        }
        enqueueFocus(.disable, sessionID: nil)
    }

    private func applicationBecameActive() {
        if let token = launchedFocusRequest?.token {
            // Give x-callback time to arrive. A manual return must not leave the
            // queue stuck forever when Shortcuts was closed or cancelled.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.launchedFocusRequest?.token == token else { return }
                self.launchedFocusRequest = nil
                self.focusStatusText = "Le résultat du raccourci n’a pas été reçu. Vérifiez Concentration dans le Centre de contrôle."
                self.launchPendingFocusRequest()
            }
        } else { launchPendingFocusRequest() }
    }

    private func enqueueFocus(_ command: FocusCommand, sessionID: UUID?, automatic: Bool = false) {
        guard !focusShortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            focusStatusText = "Le nom du raccourci Concentration est manquant."
            return
        }
        pendingFocusRequest = FocusRequest(token: UUID(), command: command, sessionID: sessionID, automatic: automatic)
        launchPendingFocusRequest()
    }

    private func launchPendingFocusRequest() {
        guard UIApplication.shared.applicationState == .active,
              launchedFocusRequest == nil, let request = pendingFocusRequest else { return }
        pendingFocusRequest = nil
        var components = URLComponents()
        components.scheme = "shortcuts"; components.host = "x-callback-url"; components.path = "/run-shortcut"
        func callback(_ status: String) -> String {
            var value = URLComponents()
            value.scheme = "cadence"; value.host = "companion-focus"
            value.queryItems = [URLQueryItem(name: "token", value: request.token.uuidString), URLQueryItem(name: "status", value: status)]
            return value.url?.absoluteString ?? "cadence://revision"
        }
        components.queryItems = [
            URLQueryItem(name: "name", value: focusShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "input", value: "text"), URLQueryItem(name: "text", value: request.command.rawValue),
            URLQueryItem(name: "x-success", value: callback("success")),
            URLQueryItem(name: "x-cancel", value: callback("cancel")), URLQueryItem(name: "x-error", value: callback("error"))
        ]
        guard let url = components.url else { return }
        launchedFocusRequest = request
        focusStatusText = request.command == .probe ? "Vérification du raccourci, sans changer Concentration…" : "Demande transmise à Raccourcis."
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            Task { @MainActor in
                guard let self, !opened, self.launchedFocusRequest?.token == request.token else { return }
                self.launchedFocusRequest = nil
                self.focusStatusText = "Raccourcis n’a pas pu être ouvert. Vérifiez son installation."
            }
        }
    }

    @discardableResult
    func handleCallback(_ url: URL) -> Bool {
        guard url.scheme == "cadence", url.host == "companion-focus" else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let request = launchedFocusRequest, value("token") == request.token.uuidString else { return true }
        launchedFocusRequest = nil
        if value("status") == "success" {
            // The audited helper returns the Focus *name*, or no value when no
            // Focus is active. It never returns our old enabled/kept markers.
            let result = value("result")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            switch request.command {
            case .probe:
                // A successful run of this exact installed name proves it is
                // callable. Empty output is a valid 'no current Focus' response.
                preparedShortcutVerified = true
                UserDefaults.standard.set(true, forKey: "cadence.companion.preparedFocusVerified.v2")
                focusStatusText = "Raccourci prêt. Vous pouvez activer l’appel automatique."
            case .checkBeforeEnable:
                guard activeSessionID == request.sessionID,
                      !request.automatic || focusEnabled else {
                    focusStatusText = "La demande Concentration n’est plus nécessaire."
                    launchPendingFocusRequest()
                    return true
                }
                if result.isEmpty {
                    enqueueFocus(.enable, sessionID: request.sessionID, automatic: request.automatic)
                } else {
                    if managedFocusSessionID != request.sessionID { managedFocusSessionID = nil }
                    focusStatusText = "Le mode Concentration déjà actif a été conservé."
                }
            case .enable:
                if !result.isEmpty {
                    managedFocusSessionID = request.sessionID
                    focusStatusText = "Le raccourci indique avoir activé Ne pas déranger pour cette séance."
                    if activeSessionID != request.sessionID || (request.automatic && !focusEnabled) {
                        enqueueFocus(.disable, sessionID: nil)
                    }
                } else { focusStatusText = "Le raccourci n’a pas confirmé un mode actif. Vérifiez Concentration dans le Centre de contrôle." }
            case .disable:
                managedFocusSessionID = nil
                focusStatusText = result.isEmpty ? "Le raccourci de fin indique qu’aucun mode Concentration n’est actif." : "Le raccourci de fin s’est terminé. Un autre mode Concentration reste sous votre contrôle."
            }
        } else {
            if request.command == .probe {
                preparedShortcutVerified = false
                UserDefaults.standard.set(false, forKey: "cadence.companion.preparedFocusVerified.v2")
            }
            focusStatusText = value("status") == "cancel" ? "Demande Concentration annulée dans Raccourcis." : "Le raccourci n’a pas abouti. Ajoutez-le, puis utilisez Tester le raccourci."
        }
        UserDefaults.standard.set(managedFocusSessionID?.uuidString, forKey: "cadence.companion.managedFocusSession")
        launchPendingFocusRequest()
        return true
    }
}
