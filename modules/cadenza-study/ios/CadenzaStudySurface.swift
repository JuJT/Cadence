import ActivityKit
import Foundation

struct CadenzaStudySnapshot: Codable, Sendable {
    struct Session: Codable, Sendable {
        let id: String
        let title: String
        let kind: String
        let startedAt: Double
        let elapsedSeconds: Double
        let paused: Bool
        let effectiveStartedAt: Double
    }

    struct Day: Codable, Sendable {
        let date: Double
        let courseSeconds: Double
        let revisionSeconds: Double
        var total: Double { max(0, courseSeconds) + max(0, revisionSeconds) }
    }

    let activeSession: Session?
    let todaySeconds: Double
    let weekSeconds: Double
    let sessionCount: Int
    let topSubject: String?
    let weekDays: [Day]?
}

struct CadenzaRevisionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let kind: String
        let elapsedSeconds: Double
        let paused: Bool
        let start: Date
    }

    let id: String
}

enum CadenzaWidgetStore {
    static let todayKind = "CadenzaStudyToday"
    static let weekKind = "CadenzaStudyWeek"
    static let studyURL = URL(string: "cadence://study")!

    static var snapshotURL: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return container.appendingPathComponent("CadenzaStudySnapshot-v1.json")
    }

    static func snapshot() -> CadenzaStudySnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url), data.count <= 65536 else { return nil }
        return try? JSONDecoder().decode(CadenzaStudySnapshot.self, from: data)
    }
}
