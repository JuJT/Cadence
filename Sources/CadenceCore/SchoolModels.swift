import Foundation

/// JSON attachments are deliberately preserved instead of assuming a PRONOTE file format.
public enum SchoolJSON: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([SchoolJSON]), object([String: SchoolJSON]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode([SchoolJSON].self) { self = .array(value) }
        else { self = .object(try c.decode([String: SchoolJSON].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var strings: [String] {
        switch self {
        case .string(let value): return [value]
        case .array(let values): return values.flatMap(\.strings)
        case .object(let values):
            for key in ["name", "filename", "title", "label"] {
                if let entry = values[key], case .string(let name) = entry, !name.isEmpty { return [name] }
            }
            return []
        default: return []
        }
    }
    public var displayText: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value ? String(format: "%.0f", value) : String(value)
        case .bool(let value): return value ? "Oui" : "Non"
        case .array: return strings.isEmpty ? nil : strings.joined(separator: ", ")
        case .object: return strings.first
        case .null: return nil
        }
    }
    public var links: [SchoolResourceLink] {
        func permitted(_ value: String) -> URL? {
            guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
                  ["https", "http"].contains(scheme), url.host != nil else { return nil }
            return url
        }
        switch self {
        case .string(let value):
            guard let url = permitted(value) else { return [] }
            return [SchoolResourceLink(title: url.host ?? "Document", url: url)]
        case .array(let values): return values.flatMap(\.links)
        case .object(let object):
            for key in ["url", "href", "link"] {
                if let entry = object[key], case .string(let value) = entry, let url = permitted(value) {
                    return [SchoolResourceLink(title: strings.first ?? url.host ?? "Document", url: url)]
                }
            }
            return []
        default: return []
        }
    }
}

public struct SchoolResourceLink: Equatable, Identifiable, Sendable {
    public var title: String
    public var url: URL
    public var id: String { url.absoluteString }
    public init(title: String, url: URL) { self.title = title; self.url = url }
}

public enum SchoolDateCodec {
    public static var parisCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.locale = Locale(identifier: "fr_FR")
        c.firstWeekday = 2
        return c
    }
    public static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let dot = value.firstIndex(of: "."), value[..<dot].contains("T") {
            let after = value.index(after: dot)
            let digits = value[after...].prefix(while: { $0.isNumber })
            if !digits.isEmpty, let fraction = Double("0." + digits) {
                let suffix = value.index(after, offsetBy: digits.count)
                let base = String(value[..<dot]) + value[suffix...]
                if let date = formatter.date(from: base) { return date.addingTimeInterval(fraction) }
            }
        }
        if let date = formatter.date(from: value) { return date }
        if value.count == 10 { return parisDate(from: value + "T00:00:00") }
        return nil
    }
    /// Only for local timestamps without an offset. The API normally provides start_at/end_at.
    public static func parisDate(from value: String) -> Date? {
        let clean = value.replacingOccurrences(of: " ", with: "T")
        let whole = String(clean.prefix(19))
        guard whole.count == 19 else { return nil }
        let f = DateFormatter()
        f.calendar = parisCalendar; f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = parisCalendar.timeZone; f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; f.isLenient = false
        guard let date = f.date(from: whole), f.string(from: date) == whole else { return nil }
        return date
    }
}

public struct SchoolTimetableEvent: Codable, Equatable, Sendable, Identifiable {
    public var eventID: String
    public var startLocal: String?
    public var endLocal: String?
    public var startAt: Date
    public var endAt: Date
    public var subjectID: String?
    public var subjectName: String
    public var teacherNames: [String]
    public var classrooms: [String]
    public var groupNames: [String]
    public var statusLabel: String?
    public var canceled: Bool
    public var exempted: Bool
    public var isTest: Bool
    public var lessonResourceID: String?
    public var id: String { eventID }
    public init(eventID: String, startAt: Date, endAt: Date, subjectName: String, startLocal: String? = nil,
                endLocal: String? = nil, subjectID: String? = nil, teacherNames: [String] = [],
                classrooms: [String] = [], groupNames: [String] = [], canceled: Bool = false,
                exempted: Bool = false, isTest: Bool = false, lessonResourceID: String? = nil, statusLabel: String? = nil) {
        self.eventID = eventID; self.startAt = startAt; self.endAt = endAt; self.subjectName = subjectName
        self.startLocal = startLocal; self.endLocal = endLocal; self.subjectID = subjectID
        self.teacherNames = teacherNames; self.classrooms = classrooms; self.groupNames = groupNames
        self.statusLabel = statusLabel
        self.canceled = canceled; self.exempted = exempted; self.isTest = isTest; self.lessonResourceID = lessonResourceID
    }
    enum CodingKeys: String, CodingKey {
        case eventID = "event_id", startLocal = "start_local", endLocal = "end_local", startAt = "start_at", endAt = "end_at"
        case subjectID = "subject_id", subjectName = "subject_name", teacherNames = "teacher_names", classrooms
        case groupNames = "group_names", canceled, exempted, isTest = "is_test", lessonResourceID = "lesson_resource_id", statusLabel = "status_label"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try c.identifier(forKey: .eventID)
        startLocal = try c.decodeIfPresent(String.self, forKey: .startLocal)
        endLocal = try c.decodeIfPresent(String.self, forKey: .endLocal)
        if let date = try c.decodeIfPresent(Date.self, forKey: .startAt) { startAt = date }
        else if let local = startLocal, let date = SchoolDateCodec.parisDate(from: local) { startAt = date }
        else { throw CadenceError.invalidSchoolSnapshot }
        if let date = try c.decodeIfPresent(Date.self, forKey: .endAt) { endAt = date }
        else if let local = endLocal, let date = SchoolDateCodec.parisDate(from: local) { endAt = date }
        else { throw CadenceError.invalidSchoolSnapshot }
        subjectID = try c.optionalIdentifier(forKey: .subjectID)
        subjectName = try c.decode(String.self, forKey: .subjectName)
        teacherNames = try c.decodeIfPresent([String].self, forKey: .teacherNames) ?? []
        classrooms = try c.decodeIfPresent([String].self, forKey: .classrooms) ?? []
        groupNames = try c.decodeIfPresent([String].self, forKey: .groupNames) ?? []
        statusLabel = try c.decodeIfPresent(String.self, forKey: .statusLabel)
        canceled = try c.decodeIfPresent(Bool.self, forKey: .canceled) ?? false
        exempted = try c.decodeIfPresent(Bool.self, forKey: .exempted) ?? false
        isTest = try c.decodeIfPresent(Bool.self, forKey: .isTest) ?? false
        lessonResourceID = try c.optionalIdentifier(forKey: .lessonResourceID)
    }
}

public typealias SchoolCourseMetadata = SchoolTimetableEvent

public struct SchoolHomework: Codable, Equatable, Sendable, Identifiable {
    public var uid: String
    public var pronoteID: String?
    public var subject: String
    public var deadline: Date
    public var description: String
    public var done: Bool
    public var difficulty: SchoolJSON?
    public var lengthMinutes: Double?
    public var attachmentNames: SchoolJSON
    public var externalLinks: SchoolJSON
    public var sourceUpdatedAt: Date?
    public var syncedAt: Date?
    public var id: String { uid }
    public var attachmentLabels: [String] { attachmentNames.strings }
    public var resourceLinks: [SchoolResourceLink] { attachmentNames.links + externalLinks.links }
    public init(uid: String, subject: String, deadline: Date, description: String, done: Bool = false,
                pronoteID: String? = nil, difficulty: SchoolJSON? = nil, lengthMinutes: Double? = nil,
                attachmentNames: SchoolJSON = .array([]), externalLinks: SchoolJSON = .array([]),
                sourceUpdatedAt: Date? = nil, syncedAt: Date? = nil) {
        self.uid = uid; self.subject = subject; self.deadline = deadline; self.description = description; self.done = done
        self.pronoteID = pronoteID; self.difficulty = difficulty; self.lengthMinutes = lengthMinutes
        self.attachmentNames = attachmentNames; self.externalLinks = externalLinks
        self.sourceUpdatedAt = sourceUpdatedAt; self.syncedAt = syncedAt
    }
    enum CodingKeys: String, CodingKey {
        case uid, pronoteID = "pronote_id", subject, deadline, description, done, difficulty
        case lengthMinutes = "length_minutes", attachmentNames = "attachment_names", externalLinks = "external_links"
        case sourceUpdatedAt = "source_updated_at", syncedAt = "synced_at"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.identifier(forKey: .uid); pronoteID = try c.optionalIdentifier(forKey: .pronoteID)
        subject = try c.decode(String.self, forKey: .subject); deadline = try c.decode(Date.self, forKey: .deadline)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        difficulty = try c.decodeIfPresent(SchoolJSON.self, forKey: .difficulty)
        lengthMinutes = try c.decodeIfPresent(Double.self, forKey: .lengthMinutes)
        attachmentNames = try c.decodeIfPresent(SchoolJSON.self, forKey: .attachmentNames) ?? .array([])
        externalLinks = try c.decodeIfPresent(SchoolJSON.self, forKey: .externalLinks) ?? .array([])
        sourceUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .sourceUpdatedAt)
        syncedAt = try c.decodeIfPresent(Date.self, forKey: .syncedAt)
    }
}

public struct HomeworkItem: Codable, Equatable, Identifiable, Sendable {
    public var source: SchoolHomework
    /// Local links survive a provider changing its remote UID representation.
    public var localID: String?
    public var sourceIdentityAliases: [String]?
    public var subjectID: UUID?
    public var localCompletionOverride: Bool?
    public var subjectOverridden: Bool?
    public var localUpdatedAt: Date?
    public var lastSeenAt: Date
    public var sourceMissing: Bool
    public var id: String { localID ?? source.uid }
    public var isDone: Bool { localCompletionOverride ?? source.done }
    public var sourceDone: Bool { source.done }
    public init(source: SchoolHomework, subjectID: UUID?, localCompletionOverride: Bool? = nil, subjectOverridden: Bool? = nil,
                localUpdatedAt: Date? = nil, lastSeenAt: Date = Date(), sourceMissing: Bool = false,
                localID: String? = nil, sourceIdentityAliases: [String]? = nil) {
        self.source = source; self.subjectID = subjectID; self.localCompletionOverride = localCompletionOverride
        self.subjectOverridden = subjectOverridden
        self.localUpdatedAt = localUpdatedAt; self.lastSeenAt = lastSeenAt; self.sourceMissing = sourceMissing
        self.localID = localID; self.sourceIdentityAliases = sourceIdentityAliases
    }
    public func isOverdue(at now: Date = Date(), calendar: Calendar = SchoolDateCodec.parisCalendar) -> Bool {
        !isDone && calendar.startOfDay(for: source.deadline) < calendar.startOfDay(for: now)
    }
}

public struct HomeworkWorkSegment: Codable, Equatable, Sendable {
    public var homeworkID: String
    public var start: Date
    public var end: Date?
    public init(homeworkID: String, start: Date, end: Date? = nil) { self.homeworkID = homeworkID; self.start = start; self.end = end }
    public func seconds(in interval: DateInterval, now: Date) -> TimeInterval {
        TimeSegment(start: start, end: end).seconds(in: interval, now: now)
    }
}

public struct SchoolCourseContent: Codable, Equatable, Identifiable, Sendable {
    public var resourceID: String
    public var contentID: String
    public var title: String
    public var description: String
    public var category: SchoolJSON?
    public var categoryText: String?
    public var files: SchoolJSON
    public var themes: SchoolJSON
    public var externalLinks: SchoolJSON
    public var sourceUpdatedAt: Date?
    public var syncedAt: Date?
    public var id: String { resourceID + "|" + contentID }
    public var resourceLinks: [SchoolResourceLink] { files.links + externalLinks.links }
    public init(resourceID: String, contentID: String, title: String, description: String = "", category: SchoolJSON? = nil,
                categoryText: String? = nil, files: SchoolJSON = .array([]), themes: SchoolJSON = .array([]),
                externalLinks: SchoolJSON = .array([]), sourceUpdatedAt: Date? = nil, syncedAt: Date? = nil) {
        self.resourceID = resourceID; self.contentID = contentID; self.title = title; self.description = description
        self.category = category; self.categoryText = categoryText; self.files = files; self.themes = themes
        self.externalLinks = externalLinks; self.sourceUpdatedAt = sourceUpdatedAt; self.syncedAt = syncedAt
    }
    enum CodingKeys: String, CodingKey {
        case resourceID = "resource_id", contentID = "content_id", title, description, category, categoryText = "category_text"
        case files, themes, externalLinks = "external_links", sourceUpdatedAt = "source_updated_at", syncedAt = "synced_at"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resourceID = try c.identifier(forKey: .resourceID); contentID = try c.identifier(forKey: .contentID)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        category = try c.decodeIfPresent(SchoolJSON.self, forKey: .category)
        categoryText = try c.decodeIfPresent(String.self, forKey: .categoryText)
        files = try c.decodeIfPresent(SchoolJSON.self, forKey: .files) ?? .array([])
        themes = try c.decodeIfPresent(SchoolJSON.self, forKey: .themes) ?? .array([])
        externalLinks = try c.decodeIfPresent(SchoolJSON.self, forKey: .externalLinks) ?? .array([])
        sourceUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .sourceUpdatedAt)
        syncedAt = try c.decodeIfPresent(Date.self, forKey: .syncedAt)
    }
}

public struct SchoolSyncState: Codable, Equatable, Sendable {
    public var lastTimetableSync: Date?
    public var lastHomeworkSync: Date?
    public var lastContentSync: Date?
    public var hasError: Bool
    public var lastSuccessfulFetch: Date?
    public var generatedAt: Date?
    public init(lastTimetableSync: Date? = nil, lastHomeworkSync: Date? = nil, lastContentSync: Date? = nil,
                hasError: Bool = false, lastSuccessfulFetch: Date? = nil, generatedAt: Date? = nil) {
        self.lastTimetableSync = lastTimetableSync; self.lastHomeworkSync = lastHomeworkSync
        self.lastContentSync = lastContentSync; self.hasError = hasError
        self.lastSuccessfulFetch = lastSuccessfulFetch; self.generatedAt = generatedAt
    }
    enum CodingKeys: String, CodingKey {
        case lastTimetableSync = "last_timetable_sync", lastHomeworkSync = "last_homework_sync", lastContentSync = "last_content_sync"
        case hasError = "has_error", lastSuccessfulFetch = "last_successful_fetch", generatedAt = "generated_at"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastTimetableSync = try c.decodeIfPresent(Date.self, forKey: .lastTimetableSync)
        lastHomeworkSync = try c.decodeIfPresent(Date.self, forKey: .lastHomeworkSync)
        lastContentSync = try c.decodeIfPresent(Date.self, forKey: .lastContentSync)
        hasError = try c.decodeIfPresent(Bool.self, forKey: .hasError) ?? false
        lastSuccessfulFetch = try c.decodeIfPresent(Date.self, forKey: .lastSuccessfulFetch)
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt)
    }
}

public struct SchoolSnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var timetable: [SchoolTimetableEvent]
    public var homework: [SchoolHomework]
    public var courseContent: [SchoolCourseContent]
    public var syncState: SchoolSyncState
    public var windowStart: Date
    public var windowEnd: Date
    public init(generatedAt: Date = Date(), timetable: [SchoolTimetableEvent] = [], homework: [SchoolHomework] = [],
                courseContent: [SchoolCourseContent] = [], syncState: SchoolSyncState = SchoolSyncState(),
                windowStart: Date, windowEnd: Date) {
        self.generatedAt = generatedAt; self.timetable = timetable; self.homework = homework
        self.courseContent = courseContent; self.syncState = syncState; self.windowStart = windowStart; self.windowEnd = windowEnd
    }
    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at", timetable, homework, courseContent = "course_content", syncState = "sync_state"
        case windowStart = "window_start", windowEnd = "window_end"
    }
    public static func decode(_ data: Data) throws -> SchoolSnapshot {
        guard data.count <= BackupCodec.maximumBytes else { throw CadenceError.invalidSchoolSnapshot }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            guard let date = SchoolDateCodec.date(from: try c.decode(String.self)) else { throw CadenceError.invalidSchoolSnapshot }
            return date
        }
        return try decoder.decode(SchoolSnapshot.self, from: data)
    }
}

private extension KeyedDecodingContainer {
    func identifier(forKey key: Key) throws -> String {
        guard let value = try optionalIdentifier(forKey: key), !value.isEmpty else { throw CadenceError.invalidSchoolSnapshot }
        return value
    }
    func optionalIdentifier(forKey key: Key) throws -> String? {
        if !contains(key) { return nil }
        if try decodeNil(forKey: key) { return nil }
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int64.self, forKey: key) { return String(value) }
        throw CadenceError.invalidSchoolSnapshot
    }
}
