import ActivityKit
import Foundation

/// Valeurs minimales transmises par ActivityKit; aucune note privée.
struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var subjectName: String
        var kindLabel: String
        var symbol: String
        var elapsedSeconds: Double
        /// Début virtuel = date de publication - temps actif cumulé.
        var runningSince: Date?
        var isPaused: Bool
    }
    let sessionID: UUID
}
