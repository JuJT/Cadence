import Foundation

/// A full successful timetable fetch and the local occurrence IDs resolved by SchoolReconciler.
/// Only dates covered by both fetches can establish an addition or removal.
public struct TimetableAlertBaseline: Codable, Sendable {
    public let account: String
    public let window: DateInterval
    fileprivate let lessons: [UUID: SchoolTimetableEvent]

    public init(account: String, window: DateInterval, occurrences: [CourseOccurrence], fetchedIDs: Set<String>, now: Date) {
        self.account = account
        self.window = window
        var lessons: [UUID: SchoolTimetableEvent] = [:]
        for course in occurrences where course.supersededByOccurrenceID == nil && !course.sourceMissing {
            guard let lesson = course.school, fetchedIDs.contains(lesson.id), lesson.endAt > now,
                  lesson.startAt < window.end, lesson.endAt > window.start else { continue }
            lessons[course.id] = lesson
        }
        self.lessons = lessons
    }

    public func changes(since previous: Self?, now: Date) -> [TimetableAlert] {
        guard let previous, previous.account == account else { return [] }
        var changes: [TimetableAlert] = []
        for (id, lesson) in lessons where lesson.endAt > now {
            let old = previous.lessons[id]
            guard old != nil || (lesson.startAt >= previous.window.start && lesson.startAt < previous.window.end) else { continue }
            if let kind = Self.change(from: old, to: lesson) {
                changes.append(TimetableAlert(kind: kind, lesson: lesson, previousStart: old?.startAt))
            }
        }
        for (id, lesson) in previous.lessons where lessons[id] == nil && lesson.endAt > now &&
            lesson.startAt >= window.start && lesson.startAt < window.end && !lesson.canceled && !lesson.exempted {
            changes.append(TimetableAlert(kind: .removed, lesson: lesson, previousStart: nil))
        }
        return changes.sorted { ($0.lesson.startAt, $0.lesson.id) < ($1.lesson.startAt, $1.lesson.id) }
    }

    private static func change(from old: SchoolTimetableEvent?, to new: SchoolTimetableEvent) -> TimetableAlert.Kind? {
        let label = normalized(new.statusLabel)
        let oldLabel = normalized(old?.statusLabel)
        if label != oldLabel, label.contains("absen"),
           ["prof", "enseignant", "intervenant"].contains(where: { label.contains($0) }) { return .teacherAbsent }
        if new.canceled && old?.canceled != true { return .cancelled }
        if old == nil || label != oldLabel {
            if label.contains("deplac") || label.contains("reporte") || label.contains("avance") { return .moved }
        }
        guard let old else { return .added }
        if old.startAt != new.startAt || old.endAt != new.endAt { return .moved }
        if old.canceled != new.canceled || old.exempted != new.exempted || old.isTest != new.isTest ||
            normalized(old.subjectName) != normalized(new.subjectName) || oldLabel != label ||
            labels(old.teacherNames) != labels(new.teacherNames) || labels(old.classrooms) != labels(new.classrooms) ||
            labels(old.groupNames) != labels(new.groupNames) { return .modified }
        return nil
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func labels(_ values: [String]) -> Set<String> { Set(values.map { normalized($0) }) }
}

public struct TimetableAlert: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case teacherAbsent, cancelled, moved, modified, added, removed
        public var title: String {
            switch self {
            case .teacherAbsent: return "Professeur absent"
            case .cancelled: return "Cours annulé"
            case .moved: return "Horaire modifié"
            case .modified: return "Cours modifié"
            case .added: return "Cours ajouté"
            case .removed: return "Cours retiré du planning"
            }
        }
    }
    public let kind: Kind
    public let lesson: SchoolTimetableEvent
    public let previousStart: Date?
}
