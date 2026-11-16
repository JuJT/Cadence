import Foundation

/// Pure transitions: persistence is the caller's responsibility. Apply to a copy before committing.
public enum CadenceEngine {
    @discardableResult
    public static func start(state: inout CadenceState, subjectID: UUID, kind: SessionKind, topic: String = "", origin: SessionOrigin = .timer, occurrenceID: UUID? = nil, homeworkID: String? = nil, at now: Date = Date()) throws -> UUID {
        guard state.activeSession == nil else { throw CadenceError.activeSessionExists }
        try requireSubject(subjectID, state: state)
        if let homeworkID { try requireHomework(homeworkID, state: state) }
        var occurrenceID = occurrenceID
        if occurrenceID == nil && kind == .course {
            let candidates = state.visibleOccurrences.filter {
                $0.subjectID == subjectID && $0.linkedSessionID == nil && !$0.sourceMissing
                    && $0.start <= now && $0.end > now && ![.absent, .cancelled, .ignored].contains($0.accountingStatus)
            }
            if candidates.count == 1 { occurrenceID = candidates[0].id }
        }
        if let occurrenceID { try requireLink(state: state, subjectID: subjectID, kind: kind, sessionID: nil, occurrenceID: occurrenceID) }
        let work = homeworkID.map { [HomeworkWorkSegment(homeworkID: $0, start: now)] }
        let session = StudySession(subjectID: subjectID, kind: kind, origin: origin, topic: topic, startedAt: now, activeSegments: [TimeSegment(start: now)], linkedOccurrenceID: occurrenceID, activeHomeworkID: homeworkID, homeworkWorkSegments: work)
        state.sessions.append(session)
        state.settings.defaultSubjectID = subjectID
        if let occurrenceID, let i = state.occurrences.firstIndex(where: { $0.id == occurrenceID }) {
            state.occurrences[i].linkedSessionID = session.id
            state.occurrences[i].status = .measured
            state.occurrences[i].previousStatus = nil
            state.occurrences[i].subjectID = subjectID
            state.occurrences[i].userEdited = true
            state.occurrences[i].identityUncertain = false
        }
        return session.id
    }

    @discardableResult
    public static func pause(state: inout CadenceState, at now: Date = Date()) throws -> Bool {
        guard let i = state.sessions.firstIndex(where: { $0.isActive }) else { return false }
        guard !state.sessions[i].isPaused else { return false }
        guard let j = state.sessions[i].activeSegments.indices.last else { throw CadenceError.invalidDates }
        guard now >= state.sessions[i].activeSegments[j].start else { throw CadenceError.clockMovedBackwards }
        if let work = state.sessions[i].homeworkWorkSegments?.last, now < (work.end ?? work.start) { throw CadenceError.clockMovedBackwards }
        state.sessions[i].activeSegments[j].end = now
        closeHomeworkSegment(session: &state.sessions[i], at: now)
        return true
    }

    @discardableResult
    public static func resume(state: inout CadenceState, at now: Date = Date()) throws -> Bool {
        guard let i = state.sessions.firstIndex(where: { $0.isActive }) else { return false }
        guard state.sessions[i].isPaused else { return false }
        guard now >= (state.sessions[i].activeSegments.last?.end ?? state.sessions[i].startedAt) else { throw CadenceError.clockMovedBackwards }
        state.sessions[i].activeSegments.append(TimeSegment(start: now))
        if let homeworkID = state.sessions[i].activeHomeworkID {
            var work = state.sessions[i].homeworkWorkSegments ?? []
            work.append(HomeworkWorkSegment(homeworkID: homeworkID, start: now))
            state.sessions[i].homeworkWorkSegments = work
        }
        return true
    }

    @discardableResult
    public static func finish(state: inout CadenceState, at now: Date = Date()) throws -> StudySession? {
        guard let i = state.sessions.firstIndex(where: { $0.isActive }) else { return nil }
        let session = state.sessions[i]
        let lastTransition = session.activeSegments.last.map { $0.end ?? $0.start } ?? session.startedAt
        guard now >= lastTransition else { throw CadenceError.clockMovedBackwards }
        if let work = session.homeworkWorkSegments?.last, now < (work.end ?? work.start) { throw CadenceError.clockMovedBackwards }
        if !session.isPaused, let j = session.activeSegments.indices.last { state.sessions[i].activeSegments[j].end = now }
        state.sessions[i].endedAt = now
        closeHomeworkSegment(session: &state.sessions[i], at: now)
        return state.sessions[i]
    }

    @discardableResult
    public static func addManual(state: inout CadenceState, subjectID: UUID, kind: SessionKind, start: Date, end: Date, topic: String = "", notes: String = "", origin: SessionOrigin = .manual, occurrenceID: UUID? = nil, allowOverlap: Bool = false) throws -> UUID {
        try requireSubject(subjectID, state: state)
        guard end > start else { throw CadenceError.invalidDates }
        if let occurrenceID { try requireLink(state: state, subjectID: subjectID, kind: kind, sessionID: nil, occurrenceID: occurrenceID) }
        if kind == .course && !allowOverlap {
            let conflictingSession = state.sessions.contains {
                $0.kind == .course && $0.subjectID == subjectID && $0.startedAt < end && ($0.endedAt ?? end) > start
            }
            let conflictingOccurrence = state.visibleOccurrences.contains {
                $0.id != occurrenceID && $0.subjectID == subjectID && $0.start < end && $0.end > start && ![.absent, .cancelled, .ignored].contains($0.accountingStatus)
            }
            if conflictingSession || conflictingOccurrence { throw CadenceError.courseOverlap }
        }
        let session = StudySession(subjectID: subjectID, kind: kind, origin: origin, topic: topic, notes: notes, startedAt: start, endedAt: end, activeSegments: [TimeSegment(start: start, end: end)], linkedOccurrenceID: occurrenceID, allowsDistinctCourseOverlap: allowOverlap)
        state.sessions.append(session)
        if let occurrenceID { try link(state: &state, sessionID: session.id, occurrenceID: occurrenceID) }
        return session.id
    }

    public static func link(state: inout CadenceState, sessionID: UUID, occurrenceID: UUID) throws {
        guard let si = state.sessions.firstIndex(where: { $0.id == sessionID }) else { throw CadenceError.sessionNotFound }
        let session = state.sessions[si]
        try requireLink(state: state, subjectID: session.subjectID, kind: session.kind, sessionID: sessionID, occurrenceID: occurrenceID)
        if let existing = session.linkedOccurrenceID, existing != occurrenceID { throw CadenceError.alreadyLinked }
        guard let oi = state.occurrences.firstIndex(where: { $0.id == occurrenceID }) else { throw CadenceError.occurrenceNotFound }
        state.sessions[si].linkedOccurrenceID = occurrenceID
        state.occurrences[oi].linkedSessionID = sessionID
        state.occurrences[oi].subjectID = session.subjectID
        state.occurrences[oi].status = state.occurrences[oi].sourceMissing ? .needsReview : .measured
        state.occurrences[oi].previousStatus = state.occurrences[oi].sourceMissing ? .measured : nil
        state.occurrences[oi].userEdited = true
        state.occurrences[oi].identityUncertain = false
    }

    public static func unlink(state: inout CadenceState, occurrenceID: UUID, at now: Date = Date()) throws {
        guard let oi = state.occurrences.firstIndex(where: { $0.id == occurrenceID }) else { throw CadenceError.occurrenceNotFound }
        // Detaching must not create a second credit; leave the occurrence ignored until explicitly restored.
        if let si = state.sessions.firstIndex(where: { $0.id == state.occurrences[oi].linkedSessionID }) { state.sessions[si].linkedOccurrenceID = nil }
        state.occurrences[oi].linkedSessionID = nil
        state.occurrences[oi].status = .ignored
        state.occurrences[oi].previousStatus = nil
    }

    public static func confirm(state: inout CadenceState, occurrenceID: UUID, seconds: TimeInterval? = nil) throws {
        guard let i = state.occurrences.firstIndex(where: { $0.id == occurrenceID }) else { throw CadenceError.occurrenceNotFound }
        guard state.occurrences[i].subjectID != nil else { throw CadenceError.subjectNotFound }
        guard state.occurrences[i].linkedSessionID == nil else { throw CadenceError.alreadyLinked }
        let duration = seconds ?? state.occurrences[i].end.timeIntervalSince(state.occurrences[i].start)
        guard duration.isFinite && duration > 0 else { throw CadenceError.invalidDuration }
        state.occurrences[i].confirmedSeconds = duration
        state.occurrences[i].status = .confirmed
        state.occurrences[i].previousStatus = nil
        state.occurrences[i].userEdited = true
        state.occurrences[i].identityUncertain = false
    }

    public static func setStatus(state: inout CadenceState, occurrenceID: UUID, status: CourseStatus) throws {
        guard let i = state.occurrences.firstIndex(where: { $0.id == occurrenceID }) else { throw CadenceError.occurrenceNotFound }
        guard state.occurrences[i].linkedSessionID == nil else { throw CadenceError.alreadyLinked }
        if status == .confirmed { try confirm(state: &state, occurrenceID: occurrenceID); return }
        guard status != .measured else { throw CadenceError.incompatibleLink }
        state.occurrences[i].status = status
        state.occurrences[i].previousStatus = nil
        state.occurrences[i].userEdited = true
        state.occurrences[i].identityUncertain = false
    }

    public static func assignSubject(state: inout CadenceState, occurrenceID: UUID, subjectID: UUID) throws {
        try requireSubject(subjectID, state: state)
        guard let i = state.occurrences.firstIndex(where: { $0.id == occurrenceID }) else { throw CadenceError.occurrenceNotFound }
        if let linked = state.occurrences[i].linkedSessionID, let session = state.sessions.first(where: { $0.id == linked }), session.subjectID != subjectID { throw CadenceError.incompatibleLink }
        state.occurrences[i].subjectID = subjectID
        state.occurrences[i].userEdited = true
        if state.occurrences[i].status == .needsReview && !state.occurrences[i].sourceMissing {
            state.occurrences[i].status = state.occurrences[i].previousStatus ?? CalendarReconciler.automaticStatus(for: state.occurrences[i], autoCredit: state.settings.autoCreditCourses, now: Date())
            state.occurrences[i].previousStatus = nil
        }
    }

    public static func updateSubject(state: inout CadenceState, subject: Subject) throws {
        var subject = subject
        subject.name = subject.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.name.isEmpty else { throw CadenceError.invalidSubject }
        subject.aliases = Array(Set(subject.aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        if let i = state.subjects.firstIndex(where: { $0.id == subject.id }) { state.subjects[i] = subject } else { state.subjects.append(subject) }
    }

    public static func deleteSubject(state: inout CadenceState, subjectID: UUID) throws {
        guard let i = state.subjects.firstIndex(where: { $0.id == subjectID }) else { throw CadenceError.subjectNotFound }
        if state.sessions.contains(where: { $0.subjectID == subjectID }) || state.occurrences.contains(where: { $0.subjectID == subjectID }) || state.homework.contains(where: { $0.subjectID == subjectID }) { state.subjects[i].isArchived = true }
        else { state.subjects.remove(at: i) }
        if state.settings.defaultSubjectID == subjectID { state.settings.defaultSubjectID = nil }
    }

    public static func updateSession(state: inout CadenceState, session: StudySession) throws {
        guard let i = state.sessions.firstIndex(where: { $0.id == session.id }) else { throw CadenceError.sessionNotFound }
        guard state.subjects.contains(where: { $0.id == session.subjectID }) else { throw CadenceError.subjectNotFound }
        guard state.sessions[i].linkedOccurrenceID == session.linkedOccurrenceID else { throw CadenceError.incompatibleLink }
        if let occurrenceID = session.linkedOccurrenceID {
            try requireLink(state: state, subjectID: session.subjectID, kind: session.kind, sessionID: session.id, occurrenceID: occurrenceID)
        }
        var candidate = state
        candidate.sessions[i] = session
        try BackupCodec.validate(candidate)
        state = candidate
    }

    public static func deleteSession(state: inout CadenceState, sessionID: UUID) throws {
        guard let i = state.sessions.firstIndex(where: { $0.id == sessionID }) else { throw CadenceError.sessionNotFound }
        if let oi = state.occurrences.firstIndex(where: { $0.linkedSessionID == sessionID }) {
            state.occurrences[oi].linkedSessionID = nil
            // Explicit deletion removes its credited course, without resurrecting an estimate.
            state.occurrences[oi].status = .ignored
            state.occurrences[oi].previousStatus = nil
            state.occurrences[oi].userEdited = true
        }
        state.sessions.remove(at: i)
    }

    public static func setAutoCredit(state: inout CadenceState, enabled: Bool, at now: Date = Date()) {
        state.settings.autoCreditCourses = enabled
        CalendarReconciler.refreshCredits(state: &state, now: now)
        SchoolReconciler.refreshCredits(state: &state, now: now)
    }

    public static func overlappingOccurrences(state: CadenceState, subjectID: UUID, start: Date, end: Date) -> [CourseOccurrence] {
        state.visibleOccurrences.filter { $0.subjectID == subjectID && $0.start < end && $0.end > start && $0.linkedSessionID == nil && ![.absent, .cancelled, .ignored].contains($0.accountingStatus) }
    }

    public static func setActiveHomework(state: inout CadenceState, homeworkID: String?, at now: Date = Date()) throws {
        guard let i = state.sessions.firstIndex(where: { $0.isActive }) else { throw CadenceError.sessionNotFound }
        if let homeworkID { try requireHomework(homeworkID, state: state) }
        let session = state.sessions[i]
        let transition = max(session.activeSegments.last.map { $0.end ?? $0.start } ?? session.startedAt,
                             session.homeworkWorkSegments?.last.map { $0.end ?? $0.start } ?? session.startedAt)
        guard now >= transition else { throw CadenceError.clockMovedBackwards }
        if session.activeHomeworkID == homeworkID { return }
        closeHomeworkSegment(session: &state.sessions[i], at: now)
        state.sessions[i].activeHomeworkID = homeworkID
        if let homeworkID, !session.isPaused {
            var work = state.sessions[i].homeworkWorkSegments ?? []
            work.append(HomeworkWorkSegment(homeworkID: homeworkID, start: now))
            state.sessions[i].homeworkWorkSegments = work
        }
    }

    public static func setHomeworkCompletion(state: inout CadenceState, homeworkID: String, isDone: Bool, at now: Date = Date()) throws {
        guard let i = state.homework.firstIndex(where: { $0.id == homeworkID }) else { throw CadenceError.homeworkNotFound }
        state.homework[i].localCompletionOverride = isDone
        state.homework[i].localUpdatedAt = now
    }

    public static func clearHomeworkCompletionOverride(state: inout CadenceState, homeworkID: String) throws {
        guard let i = state.homework.firstIndex(where: { $0.id == homeworkID }) else { throw CadenceError.homeworkNotFound }
        state.homework[i].localCompletionOverride = nil
        state.homework[i].localUpdatedAt = nil
    }

    public static func assignHomeworkSubject(state: inout CadenceState, homeworkID: String, subjectID: UUID) throws {
        try requireSubject(subjectID, state: state)
        guard let i = state.homework.firstIndex(where: { $0.id == homeworkID }) else { throw CadenceError.homeworkNotFound }
        state.homework[i].subjectID = subjectID
        state.homework[i].subjectOverridden = true
    }

    private static func requireHomework(_ id: String, state: CadenceState) throws {
        guard state.homework.contains(where: { $0.id == id }) else { throw CadenceError.homeworkNotFound }
    }

    private static func closeHomeworkSegment(session: inout StudySession, at now: Date) {
        guard var work = session.homeworkWorkSegments, let i = work.indices.last, work[i].end == nil else { return }
        work[i].end = max(work[i].start, now)
        session.homeworkWorkSegments = work
    }

    private static func requireSubject(_ id: UUID, state: CadenceState) throws {
        guard state.subjects.contains(where: { $0.id == id && !$0.isArchived }) else { throw CadenceError.subjectNotFound }
    }

    private static func requireLink(state: CadenceState, subjectID: UUID, kind: SessionKind, sessionID: UUID?, occurrenceID: UUID) throws {
        guard let occurrence = state.occurrences.first(where: { $0.id == occurrenceID }) else { throw CadenceError.occurrenceNotFound }
        guard occurrence.supersededByOccurrenceID == nil else { throw CadenceError.occurrenceNotFound }
        guard kind == .course && (occurrence.subjectID == nil || occurrence.subjectID == subjectID) else { throw CadenceError.incompatibleLink }
        if let linked = occurrence.linkedSessionID, linked != sessionID { throw CadenceError.alreadyLinked }
    }
}
