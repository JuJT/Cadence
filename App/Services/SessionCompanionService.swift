import Combine
import Foundation

/// Session lifecycle compatibility for older installations. Concentration is
/// managed by iOS; starting, pausing or finishing a session never opens another app.
@MainActor
final class SessionCompanionService: ObservableObject {
    static let shared = SessionCompanionService()
    @Published private(set) var activeSessionID: UUID?

    private init() {
        // Retire the old automation without invoking its shortcut, including on
        // upgrade while a session or a previously managed Focus is still active.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "cadence.companion.focusEnabled")
        defaults.removeObject(forKey: "cadence.companion.preparedFocusVerified.v2")
        defaults.removeObject(forKey: "cadence.companion.managedFocusSession")
    }

    func synchronizeExistingSession(activeSessionID: UUID?) {
        self.activeSessionID = activeSessionID
    }

    func sessionDidChange(activeSessionID: UUID?) {
        self.activeSessionID = activeSessionID
    }

    /// Consume delayed callbacks from the retired integration without changing
    /// navigation, settings or the user's current Focus.
    @discardableResult
    func handleCallback(_ url: URL) -> Bool {
        url.scheme == "cadence" && url.host == "companion-focus"
    }
}
