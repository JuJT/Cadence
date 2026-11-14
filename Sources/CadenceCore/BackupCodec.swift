import Foundation

public enum BackupCodec {
    public static let currentVersion = 2
    public static let maximumBytes = 20 * 1024 * 1024

    public static func encode(_ state: CadenceState, exportedAt: Date = Date()) throws -> Data {
        try validate(state)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(preciseISO8601(date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(state)
        var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        object["exportedAt"] = ISO8601DateFormatter().string(from: exportedAt)
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        guard payload.count <= maximumBytes else {
            throw CadenceError.invalidBackup("La sauvegarde dépasse 20 Mo. Réduisez les notes avant d’enregistrer ; les données précédentes sont conservées.")
        }
        return payload
    }

    public static func decode(_ data: Data) throws -> CadenceState {
        guard data.count <= maximumBytes else { throw CadenceError.invalidBackup("Le fichier dépasse 20 Mo.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = parseISO8601(value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date ISO 8601 invalide")
        }
        do {
            let header = try decoder.decode(VersionHeader.self, from: data)
            let state: CadenceState
            switch header.schemaVersion {
            case 1: state = try decoder.decode(LegacyBackup.self, from: data).migrated()
            case currentVersion: state = try decoder.decode(CadenceState.self, from: data)
            default: throw CadenceError.invalidBackup("Version \(header.schemaVersion) non prise en charge. Aucune donnée n’a été remplacée.")
            }
            try validate(state)
            return state
        } catch let error as CadenceError { throw error }
        catch { throw CadenceError.invalidBackup("Le contenu JSON, les identifiants ou les dates sont incorrects.") }
    }

    public static func validate(_ state: CadenceState) throws {
        guard state.schemaVersion == currentVersion else { throw CadenceError.invalidBackup("Version de données non prise en charge.") }
        guard state.subjects.count <= 1000, state.sessions.count <= 100_000, state.occurrences.count <= 100_000 else { throw CadenceError.invalidBackup("Trop d’enregistrements.") }
        func unique<T: Hashable>(_ values: [T]) -> Bool { Set(values).count == values.count }
        func validDate(_ date: Date) -> Bool {
            let value = date.timeIntervalSince1970
            return value.isFinite && value >= -62_135_596_800 && value <= 253_402_300_799
        }
        guard unique(state.subjects.map(\.id)), unique(state.sessions.map(\.id)), unique(state.occurrences.map(\.id)) else { throw CadenceError.invalidBackup("Des identifiants sont dupliqués.") }
        let subjectIDs = Set(state.subjects.map(\.id))
        let sessions = Dictionary(uniqueKeysWithValues: state.sessions.map { ($0.id, $0) })
        let occurrences = Dictionary(uniqueKeysWithValues: state.occurrences.map { ($0.id, $0) })
        guard state.subjects.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 200 && $0.aliases.count <= 1000 }) else { throw CadenceError.invalidBackup("Une matière est vide ou trop longue.") }
        guard state.sessions.filter(\.isActive).count <= 1 else { throw CadenceError.invalidBackup("Plusieurs séances actives.") }
        for session in state.sessions {
            guard subjectIDs.contains(session.subjectID) else { throw CadenceError.invalidBackup("Une séance fait référence à une matière absente.") }
            guard validDate(session.startedAt), session.endedAt.map({ $0 >= session.startedAt && validDate($0) }) ?? true, !session.activeSegments.isEmpty else { throw CadenceError.invalidDates }
            var previousEnd = session.startedAt
            for (index, segment) in session.activeSegments.enumerated() {
                guard validDate(segment.start), segment.start >= previousEnd else { throw CadenceError.invalidDates }
                if let end = segment.end {
                    guard end >= segment.start, validDate(end), session.endedAt.map({ end <= $0 }) ?? true else { throw CadenceError.invalidDates }
                    previousEnd = end
                } else {
                    guard session.endedAt == nil && index == session.activeSegments.count - 1 else { throw CadenceError.invalidDates }
                }
            }
            if let linkedID = session.linkedOccurrenceID {
                guard let occurrence = occurrences[linkedID], occurrence.linkedSessionID == session.id, occurrence.subjectID == session.subjectID, session.kind == .course else { throw CadenceError.invalidBackup("Une association cours/séance est incohérente.") }
            }
        }
        for occurrence in state.occurrences {
            guard occurrence.end > occurrence.start, validDate(occurrence.start), validDate(occurrence.end), validDate(occurrence.lastSeenAt) else { throw CadenceError.invalidDates }
            if let subjectID = occurrence.subjectID, !subjectIDs.contains(subjectID) { throw CadenceError.invalidBackup("Un cours fait référence à une matière absente.") }
            if let seconds = occurrence.confirmedSeconds, !seconds.isFinite || seconds <= 0 { throw CadenceError.invalidDuration }
            if occurrence.accountingStatus == .confirmed && occurrence.subjectID == nil { throw CadenceError.subjectNotFound }
            if let linkedID = occurrence.linkedSessionID {
                guard let session = sessions[linkedID], session.linkedOccurrenceID == occurrence.id, session.kind == .course, session.subjectID == occurrence.subjectID else { throw CadenceError.invalidBackup("Une association séance/cours est incohérente.") }
            }
            if occurrence.accountingStatus == .measured && occurrence.linkedSessionID == nil { throw CadenceError.invalidBackup("Un cours mesuré n’a pas de séance associée.") }
            if let start = occurrence.pendingStart, let end = occurrence.pendingEnd, end <= start { throw CadenceError.invalidDates }
        }
        if let defaultID = state.settings.defaultSubjectID, !subjectIDs.contains(defaultID) { throw CadenceError.subjectNotFound }
    }

    /// RFC 4180 CSV, UTF-8 with BOM. Spreadsheet formula prefixes are neutralized on text cells.
    public static func csv(_ state: CadenceState, now: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        func text(_ raw: String) -> String {
            let first = raw.drop(while: { $0.isWhitespace }).first
            let safe = first.map { "=+-@".contains($0) } == true ? "'" + raw : raw
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        func row(_ cells: [String]) -> String { cells.map(text).joined(separator: ",") }
        let subjects = Dictionary(state.subjects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var rows = [row(["Identifiant", "Type", "Matière", "Début UTC", "Fin UTC", "Secondes actives", "Origine", "Statut", "Chapitre", "Notes", "Cours associé"])]
        for session in state.sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            rows.append(row([session.id.uuidString, session.kind.label, subjects[session.subjectID] ?? "Matière inconnue", formatter.string(from: session.startedAt), session.endedAt.map(formatter.string(from:)) ?? "", String(session.elapsed(at: now)), session.origin.label, session.isActive ? (session.isPaused ? "En pause" : "En cours") : "Terminée", session.topic, session.notes, session.linkedOccurrenceID?.uuidString ?? ""]))
        }
        for occurrence in state.occurrences where occurrence.linkedSessionID == nil {
            let status = occurrence.accountingStatus
            let seconds: TimeInterval = status == .confirmed ? occurrence.confirmedSeconds ?? occurrence.end.timeIntervalSince(occurrence.start) : status == .estimated && occurrence.end <= now ? occurrence.end.timeIntervalSince(occurrence.start) : 0
            rows.append(row([occurrence.id.uuidString, SessionKind.course.label, occurrence.subjectID.flatMap { subjects[$0] } ?? "À classer", formatter.string(from: occurrence.start), formatter.string(from: occurrence.end), String(seconds), "Calendrier", occurrence.status.label, occurrence.title, occurrence.sourceMissing ? "N’apparaît plus au calendrier" : "", ""]))
        }
        return "\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n"
    }

    private struct VersionHeader: Decodable { var schemaVersion: Int }
    private static func preciseISO8601(_ date: Date) -> String {
        let wholeSeconds = floor(date.timeIntervalSinceReferenceDate)
        let base = Date(timeIntervalSinceReferenceDate: wholeSeconds)
        let fraction = date.timeIntervalSinceReferenceDate - wholeSeconds
        let whole = ISO8601DateFormatter().string(from: base)
        let digits = String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), fraction).dropFirst(2)
        return String(whole.dropLast()) + "." + digits + "Z"
    }
    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        // Parse fractions ourselves: platform formatters may truncate sub-millisecond precision.
        if let dot = value.firstIndex(of: "."), value[..<dot].contains("T") {
            let after = value.index(after: dot)
            let digits = value[after...].prefix(while: { $0.isNumber })
            guard !digits.isEmpty, let fraction = Double("0." + digits) else { return nil }
            let suffixIndex = value.index(after, offsetBy: digits.count)
            let base = String(value[..<dot]) + value[suffixIndex...]
            return formatter.date(from: base)?.addingTimeInterval(fraction)
        }
        return formatter.date(from: value)
    }
    private struct LegacyBackup: Decodable {
        struct LegacySubject: Decodable {
            var id: UUID; var name: String; var colorHex: String; var symbol: String; var position: Int; var isArchived: Bool
        }
        struct LegacySession: Decodable {
            var id: UUID; var subjectId: UUID; var kind: SessionKind; var topic: String?; var notes: String?
            var startedAt: Date; var endedAt: Date; var activeSegments: [TimeSegment]; var origin: String?
        }
        struct LegacyActive: Decodable {
            var id: UUID; var subjectId: UUID; var kind: SessionKind; var topic: String?; var startedAt: Date
            var completedSegments: [TimeSegment]; var currentSegmentStart: Date?; var isPaused: Bool
        }
        var subjects: [LegacySubject]
        var sessions: [LegacySession]
        var activeSession: LegacyActive?
        func migrated() -> CadenceState {
            var migrated = CadenceState(subjects: subjects.map { Subject(id: $0.id, name: $0.name, colorHex: $0.colorHex, symbol: $0.symbol, isArchived: $0.isArchived, position: $0.position) }, sessions: sessions.map { StudySession(id: $0.id, subjectID: $0.subjectId, kind: $0.kind, origin: SessionOrigin(rawValue: $0.origin ?? "manual") ?? .manual, topic: $0.topic ?? "", notes: $0.notes ?? "", startedAt: $0.startedAt, endedAt: $0.endedAt, activeSegments: $0.activeSegments) })
            if let active = activeSession {
                var segments = active.completedSegments
                if let start = active.currentSegmentStart, !active.isPaused { segments.append(TimeSegment(start: start)) }
                if segments.isEmpty { segments = [TimeSegment(start: active.startedAt, end: active.isPaused ? active.startedAt : nil)] }
                migrated.sessions.append(StudySession(id: active.id, subjectID: active.subjectId, kind: active.kind, topic: active.topic ?? "", startedAt: active.startedAt, activeSegments: segments))
            }
            return migrated
        }
    }
}
