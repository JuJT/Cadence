import Foundation

public enum SessionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case course, revision
    public var id: String { rawValue }
    public var label: String { self == .course ? "Cours" : "Révision" }
    public var symbol: String { self == .course ? "book.closed" : "pencil.and.outline" }
}

public enum SessionOrigin: String, Codable, CaseIterable, Sendable {
    case manual, timer, calendar, shortcut, watch
    public var label: String {
        switch self {
        case .manual: return "Manuel"
        case .timer: return "Chronomètre"
        case .calendar: return "Calendrier"
        case .shortcut: return "Raccourci"
        case .watch: return "Apple Watch"
        }
    }
}

public struct Subject: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var symbol: String
    public var aliases: [String]
    public var isArchived: Bool
    public var position: Int
    public init(id: UUID = UUID(), name: String, colorHex: String = "#2776F8", symbol: String = "book", aliases: [String] = [], isArchived: Bool = false, position: Int = 0) {
        self.id = id; self.name = name; self.colorHex = colorHex; self.symbol = symbol
        self.aliases = aliases; self.isArchived = isArchived; self.position = position
    }
}

public struct TimeSegment: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date?
    public init(start: Date, end: Date? = nil) { self.start = start; self.end = end }
    public func duration(at now: Date) -> TimeInterval { max(0, (end ?? now).timeIntervalSince(start)) }
    public func seconds(in interval: DateInterval, now: Date) -> TimeInterval {
        max(0, min(end ?? now, interval.end).timeIntervalSince(max(start, interval.start)))
    }
}

public struct StudySession: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var subjectID: UUID
    public var kind: SessionKind
    public var origin: SessionOrigin
    public var topic: String
    public var notes: String
    public var startedAt: Date
    public var endedAt: Date?
    public var activeSegments: [TimeSegment]
    public var linkedOccurrenceID: UUID?
    public var isPaused: Bool { endedAt == nil && activeSegments.last?.end != nil }
    public var isActive: Bool { endedAt == nil }
    public init(id: UUID = UUID(), subjectID: UUID, kind: SessionKind, origin: SessionOrigin = .timer, topic: String = "", notes: String = "", startedAt: Date, endedAt: Date? = nil, activeSegments: [TimeSegment], linkedOccurrenceID: UUID? = nil) {
        self.id = id; self.subjectID = subjectID; self.kind = kind; self.origin = origin
        self.topic = topic; self.notes = notes; self.startedAt = startedAt; self.endedAt = endedAt
        self.activeSegments = activeSegments; self.linkedOccurrenceID = linkedOccurrenceID
    }
    public func elapsed(at now: Date = Date()) -> TimeInterval {
        activeSegments.reduce(0) { $0 + $1.duration(at: endedAt ?? now) }
    }
    public func seconds(in interval: DateInterval, now: Date) -> TimeInterval {
        activeSegments.reduce(0) { $0 + $1.seconds(in: interval, now: endedAt ?? now) }
    }
}

public enum CourseStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case scheduled, inProgressScheduled, estimated, confirmed, measured, absent, cancelled, ignored, needsReview
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .scheduled: return "À venir"
        case .inProgressScheduled: return "Horaire en cours"
        case .estimated: return "Estimé"
        case .confirmed: return "Confirmé"
        case .measured: return "Mesuré"
        case .absent: return "Absent"
        case .cancelled: return "Annulé"
        case .ignored: return "Ignoré"
        case .needsReview: return "À vérifier"
        }
    }
}

public struct CalendarEvent: Codable, Equatable, Sendable {
    public var calendarIdentifier: String
    public var eventIdentifier: String
    public var externalIdentifier: String?
    /// Original occurrence date for a recurring event; survives a moved exception.
    public var occurrenceAnchor: Date?
    public var calendarName: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var isRecurring: Bool
    public init(calendarIdentifier: String, eventIdentifier: String, externalIdentifier: String? = nil, occurrenceAnchor: Date? = nil, calendarName: String = "", title: String, start: Date, end: Date, isAllDay: Bool = false, isRecurring: Bool = false) {
        self.calendarIdentifier = calendarIdentifier; self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier; self.occurrenceAnchor = occurrenceAnchor
        self.calendarName = calendarName; self.title = title; self.start = start; self.end = end
        self.isAllDay = isAllDay; self.isRecurring = isRecurring
    }
}

public struct CourseOccurrence: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var calendarIdentifier: String
    public var eventIdentifier: String
    public var externalIdentifier: String?
    public var occurrenceAnchor: Date?
    public var isRecurring: Bool
    public var calendarName: String
    public var title: String
    public var start: Date
    public var end: Date
    public var subjectID: UUID?
    public var status: CourseStatus
    /// Previous accounting decision retained while an external change is reviewed.
    public var previousStatus: CourseStatus?
    public var confirmedSeconds: TimeInterval?
    public var linkedSessionID: UUID?
    public var sourceMissing: Bool
    public var userEdited: Bool
    public var lastSeenAt: Date
    public var sourceFingerprint: String
    public var pendingStart: Date?
    public var pendingEnd: Date?
    public var pendingTitle: String?
    public var identityUncertain: Bool
    public init(id: UUID = UUID(), calendarIdentifier: String, eventIdentifier: String, externalIdentifier: String? = nil, occurrenceAnchor: Date? = nil, isRecurring: Bool = false, calendarName: String = "", title: String, start: Date, end: Date, subjectID: UUID? = nil, status: CourseStatus = .scheduled, previousStatus: CourseStatus? = nil, confirmedSeconds: TimeInterval? = nil, linkedSessionID: UUID? = nil, sourceMissing: Bool = false, userEdited: Bool = false, lastSeenAt: Date = Date(), sourceFingerprint: String = "", pendingStart: Date? = nil, pendingEnd: Date? = nil, pendingTitle: String? = nil, identityUncertain: Bool = false) {
        self.id = id; self.calendarIdentifier = calendarIdentifier; self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier; self.occurrenceAnchor = occurrenceAnchor; self.isRecurring = isRecurring
        self.calendarName = calendarName; self.title = title; self.start = start; self.end = end
        self.subjectID = subjectID; self.status = status; self.previousStatus = previousStatus
        self.confirmedSeconds = confirmedSeconds; self.linkedSessionID = linkedSessionID
        self.sourceMissing = sourceMissing; self.userEdited = userEdited; self.lastSeenAt = lastSeenAt
        self.sourceFingerprint = sourceFingerprint
        self.pendingStart = pendingStart; self.pendingEnd = pendingEnd; self.pendingTitle = pendingTitle
        self.identityUncertain = identityUncertain
    }
    public var accountingStatus: CourseStatus { status == .needsReview ? previousStatus ?? .needsReview : status }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var selectedCalendarIDs: [String]
    public var excludedKeywords: [String]
    public var autoCreditCourses: Bool
    public var calendarEnabled: Bool
    public var liveActivityEnabled: Bool
    public var onboardingCompleted: Bool
    public var defaultSubjectID: UUID?
    public var lastCalendarSync: Date?
    public init(selectedCalendarIDs: [String] = [], excludedKeywords: [String] = [], autoCreditCourses: Bool = false, calendarEnabled: Bool = false, liveActivityEnabled: Bool = true, onboardingCompleted: Bool = false, defaultSubjectID: UUID? = nil, lastCalendarSync: Date? = nil) {
        self.selectedCalendarIDs = selectedCalendarIDs; self.excludedKeywords = excludedKeywords
        self.autoCreditCourses = autoCreditCourses; self.calendarEnabled = calendarEnabled
        self.liveActivityEnabled = liveActivityEnabled; self.onboardingCompleted = onboardingCompleted
        self.defaultSubjectID = defaultSubjectID; self.lastCalendarSync = lastCalendarSync
    }
}

public struct CadenceState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var subjects: [Subject]
    public var sessions: [StudySession]
    public var occurrences: [CourseOccurrence]
    public var settings: AppSettings
    public var activeSession: StudySession? { sessions.first { $0.endedAt == nil } }
    public init(schemaVersion: Int = 2, subjects: [Subject] = [], sessions: [StudySession] = [], occurrences: [CourseOccurrence] = [], settings: AppSettings = AppSettings()) {
        self.schemaVersion = schemaVersion; self.subjects = subjects; self.sessions = sessions
        self.occurrences = occurrences; self.settings = settings
    }
    public static func initial() -> CadenceState {
        CadenceState(subjects: [
            Subject(name: "Mathématiques", colorHex: "#258BFF", symbol: "function", aliases: ["MATH", "Maths"], position: 0),
            Subject(name: "Physique-Chimie", colorHex: "#7668F6", symbol: "atom", aliases: ["PC", "Physique", "Chimie"], position: 1),
            Subject(name: "SVT", colorHex: "#27835D", symbol: "leaf", aliases: ["Sciences de la vie"], position: 2),
            Subject(name: "Histoire-Géographie", colorHex: "#B46B26", symbol: "globe.europe.africa", aliases: ["H-G", "Histoire", "Géographie"], position: 3),
            Subject(name: "Français", colorHex: "#BC426C", symbol: "text.book.closed", aliases: ["FR"], position: 4),
            Subject(name: "Anglais", colorHex: "#347D93", symbol: "character.bubble", aliases: ["ANG", "English"], position: 5)
        ])
    }
}

public enum CadenceError: Error, LocalizedError, Equatable {
    case activeSessionExists, subjectNotFound, sessionNotFound, occurrenceNotFound
    case invalidDates, invalidDuration, invalidSubject, invalidBackup(String)
    case incompatibleLink, alreadyLinked, courseOverlap, clockMovedBackwards
    public var errorDescription: String? {
        switch self {
        case .activeSessionExists: return "Une séance est déjà en cours. Terminez-la avant d’en démarrer une autre."
        case .subjectNotFound: return "Cette matière est introuvable ou archivée."
        case .sessionNotFound: return "Cette séance est introuvable."
        case .occurrenceNotFound: return "Ce cours est introuvable."
        case .invalidDates: return "La fin doit suivre le début et les segments ne doivent pas se chevaucher."
        case .invalidDuration: return "La durée doit être positive et finie."
        case .invalidSubject: return "Donnez un nom à cette matière."
        case .invalidBackup(let reason): return "Sauvegarde invalide : \(reason)"
        case .incompatibleLink: return "Seul un cours de la même matière peut être associé à cette occurrence."
        case .alreadyLinked: return "Ce cours ou cette séance est déjà associé. Détachez d’abord son association actuelle."
        case .courseOverlap: return "Un cours de cette matière chevauche ce créneau. Associez-le ou confirmez une séance distincte."
        case .clockMovedBackwards: return "L’heure de l’appareil précède la dernière transition de la séance. Vérifiez la date avant de continuer."
        }
    }
}
