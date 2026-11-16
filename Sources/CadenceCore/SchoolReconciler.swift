import Foundation

public struct SchoolSyncReport: Equatable, Sendable {
    public var inserted = 0
    public var updated = 0
    public var mergedDuplicates = 0
    public var missing = 0
    public var homeworkCount = 0
    public init() {}
}

public enum SchoolReconciler {
    public static let sourceIdentifier = "supabase-pronote"

    /// Apply a complete authenticated response to a copy. A malformed response never clears the cache.
    @discardableResult
    public static func sync(state: inout CadenceState, snapshot: SchoolSnapshot, now: Date = Date()) throws -> SchoolSyncReport {
        try validate(snapshot)
        var updated = state
        let report = apply(state: &updated, snapshot: snapshot, now: now)
        try BackupCodec.validate(updated)
        state = updated
        return report
    }

    public static func contents(for occurrence: CourseOccurrence, state: CadenceState) -> [SchoolCourseContent] {
        guard let resource = occurrence.school?.lessonResourceID, !resource.isEmpty else { return [] }
        // A shared subject or date is not a pedagogical-content relation.
        return state.courseContents.filter { $0.resourceID == resource }
    }

    private static func apply(state: inout CadenceState, snapshot: SchoolSnapshot, now: Date) -> SchoolSyncReport {
        var report = SchoolSyncReport()
        let oldIDs = Set(state.visibleOccurrences.filter { $0.school != nil }.map(\.id))
        let incomingEventIDs = Set(snapshot.timetable.map(\.eventID))
        let existingEventIDs = Set(state.visibleOccurrences.compactMap { $0.school?.eventID })
        let legacyCalendarIDs = Set(state.settings.selectedCalendarIDs)
        var seen = Set<UUID>()
        state.settings.autoCreditCourses = true
        // School data no longer triggers EventKit imports. Personal calendar linking is a separate opt-in.
        state.settings.calendarEnabled = false
        for event in snapshot.timetable.sorted(by: { $0.startAt < $1.startAt }) {
            let subjectID = resolveSubject(name: event.subjectName, remoteID: event.subjectID, state: &state)
            let eligible = state.occurrences.indices.filter {
                let old = state.occurrences[$0]
                guard old.supersededByOccurrenceID == nil, !seen.contains(old.id) else { return false }
                // Reserve every exact incoming identity before processing sorted lessons.
                // A renamed/moved lesson must not consume another lesson still present.
                if let source = old.school, incomingEventIDs.contains(source.eventID) {
                    return source.eventID == event.eventID
                }
                let start = old.school?.startAt ?? old.start
                let end = old.school?.endAt ?? old.end
                return start < snapshot.windowEnd && end > snapshot.windowStart
            }
            let exact = eligible.filter { state.occurrences[$0].school?.eventID == event.eventID }
            var match = exact.count == 1 ? exact.first : nil
            if match == nil {
                let base = baseID(event.eventID)
                let upstreamCount = snapshot.timetable.filter { baseID($0.eventID) == base }.count
                let sameBase = eligible.filter {
                    guard let old = state.occurrences[$0].school else { return false }
                    return baseID(old.eventID) == base
                }
                if event.eventID.contains("|"), upstreamCount == 1, sameBase.count == 1 { match = sameBase.first }
            }
            var ambiguousResidual = false
            if match == nil, event.eventID.contains("|"), !existingEventIDs.contains(event.eventID) {
                let calendar = SchoolDateCodec.parisCalendar
                let day = calendar.startOfDay(for: event.startAt)
                let base = baseID(event.eventID)
                let newResiduals = snapshot.timetable.filter {
                    !existingEventIDs.contains($0.eventID) && baseID($0.eventID) == base
                        && calendar.startOfDay(for: $0.startAt) == day
                        && ($0.eventID == event.eventID || SubjectAliasResolver.subjectID(for: $0.subjectName, subjects: state.subjects) == subjectID
                            || (event.subjectID != nil && $0.subjectID == event.subjectID))
                }
                let oldResiduals = eligible.filter {
                    let old = state.occurrences[$0]
                    guard let source = old.school else { return false }
                    return !incomingEventIDs.contains(source.eventID) && baseID(source.eventID) == base
                        && calendar.startOfDay(for: source.startAt) == day && old.subjectID == subjectID
                }
                if newResiduals.count == 1, oldResiduals.count == 1 { match = oldResiduals.first }
                else { ambiguousResidual = !oldResiduals.isEmpty }
            }
            // Only a unique incoming lesson may adopt an old calendar fingerprint.
            let incomingMatches = snapshot.timetable.filter {
                SubjectAliasResolver.normalize($0.subjectName) == SubjectAliasResolver.normalize(event.subjectName)
                    && sameSchedule($0.startAt, $0.endAt, event.startAt, event.endAt)
            }.count
            var duplicates: [Int] = []
            if incomingMatches == 1 {
                duplicates = eligible.filter {
                    let old = state.occurrences[$0]
                    let legacy = old.school == nil && (legacyCalendarIDs.contains(old.calendarIdentifier) || old.sourceMissing)
                    let school = old.school != nil
                    return (legacy || school) && old.subjectID == subjectID
                        && sameSchedule(old.school?.startAt ?? old.start, old.school?.endAt ?? old.end, event.startAt, event.endAt)
                }
                if match == nil {
                    match = preferred(duplicates, occurrences: state.occurrences)
                }
            }
            // An exact time fingerprint remains stronger evidence than an ambiguous base.
            if match != nil { ambiguousResidual = false }
            let i: Int
            if let match {
                i = match; report.updated += 1
            } else {
                let occurrence = CourseOccurrence(calendarIdentifier: sourceIdentifier, eventIdentifier: event.eventID,
                    calendarName: "PRONOTE", title: event.subjectName, start: event.startAt, end: event.endAt,
                    subjectID: subjectID, lastSeenAt: now, school: event)
                state.occurrences.append(occurrence); i = state.occurrences.count - 1; report.inserted += 1
            }

            let pool = Array(Set(duplicates + [i]))
            let linked = Set(pool.compactMap { state.occurrences[$0].linkedSessionID })
            if linked.count <= 1, let decision = preferred(pool, occurrences: state.occurrences) {
                if decision != i {
                    let old = state.occurrences[decision]
                    state.occurrences[i].status = old.status
                    state.occurrences[i].previousStatus = old.previousStatus
                    state.occurrences[i].confirmedSeconds = old.confirmedSeconds
                    state.occurrences[i].userEdited = old.userEdited
                    if old.schoolScheduleOverridden == true {
                        state.occurrences[i].schoolScheduleOverridden = true
                        state.occurrences[i].start = old.start; state.occurrences[i].end = old.end
                        state.occurrences[i].title = old.title
                    }
                    state.occurrences[i].subjectID = old.subjectID ?? subjectID
                    if let sessionID = old.linkedSessionID {
                        state.occurrences[i].linkedSessionID = sessionID
                        if let si = state.sessions.firstIndex(where: { $0.id == sessionID }) {
                            state.sessions[si].linkedOccurrenceID = state.occurrences[i].id
                        }
                    }
                }
                for duplicate in pool where duplicate != i {
                    let retiredID = state.occurrences[duplicate].id
                    let canonicalID = state.occurrences[i].id
                    for previous in state.occurrences.indices where state.occurrences[previous].supersededByOccurrenceID == retiredID {
                        state.occurrences[previous].supersededByOccurrenceID = canonicalID
                    }
                    state.occurrences[duplicate].supersededByOccurrenceID = state.occurrences[i].id
                    state.occurrences[duplicate].linkedSessionID = nil
                    state.occurrences[duplicate].status = .ignored
                    state.occurrences[duplicate].previousStatus = nil
                    report.mergedDuplicates += 1
                }
            } else if linked.count > 1 {
                // Multiple independent measurements are personal history, not safe merge candidates.
                for duplicate in pool where duplicate != i {
                    if state.occurrences[duplicate].status != .needsReview {
                        state.occurrences[duplicate].previousStatus = state.occurrences[duplicate].status
                    }
                    state.occurrences[duplicate].status = .needsReview
                    state.occurrences[duplicate].identityUncertain = true
                }
            }
            var occurrence = state.occurrences[i]
            let unresolvedResidual = occurrence.identityUncertain && occurrence.status == .needsReview && eligible.contains {
                let old = state.occurrences[$0]
                guard old.id != occurrence.id, let source = old.school, !incomingEventIDs.contains(source.eventID),
                      old.subjectID == subjectID,
                      old.userEdited || [.confirmed, .measured].contains(old.accountingStatus) else { return false }
                return baseID(source.eventID) == baseID(event.eventID)
                    && SchoolDateCodec.parisCalendar.isDate(source.startAt, inSameDayAs: event.startAt)
            }
            let localStatus = occurrence.accountingStatus
            let localExclusion = occurrence.userEdited && [.absent, .ignored, .cancelled].contains(localStatus)
            let localConfirmation = occurrence.userEdited && occurrence.accountingStatus == .confirmed
            occurrence.calendarIdentifier = sourceIdentifier; occurrence.eventIdentifier = event.eventID
            occurrence.externalIdentifier = event.eventID; occurrence.occurrenceAnchor = nil; occurrence.isRecurring = false
            occurrence.calendarName = "PRONOTE"; occurrence.school = event; occurrence.lastSeenAt = now
            occurrence.sourceMissing = false; occurrence.identityUncertain = incomingMatches > 1 || ambiguousResidual || unresolvedResidual
            occurrence.sourceFingerprint = event.eventID
            occurrence.pendingStart = nil; occurrence.pendingEnd = nil; occurrence.pendingTitle = nil
            occurrence.previousStatus = nil
            if occurrence.schoolScheduleOverridden != true {
                occurrence.start = event.startAt; occurrence.end = event.endAt
                occurrence.title = event.subjectName
            }
            if occurrence.subjectID == nil || !occurrence.userEdited { occurrence.subjectID = subjectID }
            if occurrence.linkedSessionID != nil { occurrence.status = .measured }
            else if localExclusion { occurrence.status = localStatus }
            else if event.canceled || event.exempted { occurrence.status = .cancelled }
            else if localConfirmation { occurrence.status = .confirmed }
            else if incomingMatches > 1 || ambiguousResidual || unresolvedResidual { occurrence.status = .needsReview }
            else { occurrence.status = automaticStatus(event, start: occurrence.start, end: occurrence.end, now: now) }
            state.occurrences[i] = occurrence
            seen.insert(occurrence.id)
        }
        for i in state.occurrences.indices {
            var occurrence = state.occurrences[i]
            guard oldIDs.contains(occurrence.id), occurrence.supersededByOccurrenceID == nil,
                  occurrence.start < snapshot.windowEnd, occurrence.end > snapshot.windowStart,
                  !seen.contains(occurrence.id) else { continue }
            occurrence.sourceMissing = true
            if occurrence.linkedSessionID == nil && !occurrence.userEdited { occurrence.status = .cancelled }
            state.occurrences[i] = occurrence; report.missing += 1
        }
        // Recover the association when a manual course existed before the school feed was first connected.
        for si in state.sessions.indices {
            let session = state.sessions[si]
            guard session.kind == .course, session.linkedOccurrenceID == nil,
                  session.allowsDistinctCourseOverlap != true else { continue }
            let end = session.endedAt ?? now
            let candidates = state.occurrences.filter {
                $0.school != nil && $0.supersededByOccurrenceID == nil && !$0.sourceMissing
                    && $0.linkedSessionID == nil && $0.subjectID == session.subjectID
                    && ![.absent, .cancelled, .ignored].contains($0.accountingStatus)
                    && $0.start < end && $0.end > session.startedAt
            }
            if candidates.count == 1 {
                let course = candidates[0]
                let competing = state.sessions.filter {
                    $0.kind == .course && $0.linkedOccurrenceID == nil && $0.allowsDistinctCourseOverlap != true
                        && $0.subjectID == session.subjectID && $0.startedAt < course.end && ($0.endedAt ?? now) > course.start
                }
                if competing.count == 1 { try? CadenceEngine.link(state: &state, sessionID: session.id, occurrenceID: course.id) }
            }
        }
        let homeworkIDs = Set(snapshot.homework.map(\.uid))
        for i in state.homework.indices { state.homework[i].sourceMissing = !homeworkIDs.contains(state.homework[i].id) }
        for remote in snapshot.homework {
            let oldIndex = state.homework.firstIndex(where: { $0.id == remote.uid })
            let subject: UUID
            if let i = oldIndex, state.homework[i].subjectOverridden == true, let id = state.homework[i].subjectID {
                subject = id
            } else { subject = resolveSubject(name: remote.subject, remoteID: nil, state: &state) }
            if let i = oldIndex {
                state.homework[i].source = remote; state.homework[i].subjectID = subject
                state.homework[i].lastSeenAt = now; state.homework[i].sourceMissing = false
            } else { state.homework.append(HomeworkItem(source: remote, subjectID: subject, lastSeenAt: now)) }
        }
        for remote in snapshot.courseContent {
            if let i = state.courseContents.firstIndex(where: { $0.id == remote.id }) { state.courseContents[i] = remote }
            else { state.courseContents.append(remote) }
        }
        var sync = snapshot.syncState
        sync.lastSuccessfulFetch = now; sync.generatedAt = snapshot.generatedAt
        state.schoolSync = sync
        report.homeworkCount = snapshot.homework.count
        return report
    }

    public static func refreshCredits(state: inout CadenceState, now: Date = Date()) {
        for i in state.occurrences.indices {
            let occurrence = state.occurrences[i]
            guard let event = occurrence.school, occurrence.supersededByOccurrenceID == nil,
                  !occurrence.sourceMissing, occurrence.linkedSessionID == nil,
                  [.scheduled, .inProgressScheduled, .estimated].contains(occurrence.status) else { continue }
            state.occurrences[i].status = automaticStatus(event, start: occurrence.start, end: occurrence.end, now: now)
        }
    }

    private static func automaticStatus(_ event: SchoolTimetableEvent, start: Date, end: Date, now: Date) -> CourseStatus {
        if event.canceled || event.exempted { return .cancelled }
        if end <= now { return .estimated }
        return start <= now ? .inProgressScheduled : .scheduled
    }
    private static func sameSchedule(_ a: Date, _ b: Date, _ c: Date, _ d: Date) -> Bool {
        abs(a.timeIntervalSince(c)) <= 60 && abs(b.timeIntervalSince(d)) <= 60
    }
    private static func baseID(_ id: String) -> String { id.components(separatedBy: "|").first ?? id }
    private static func preferred(_ indices: [Int], occurrences: [CourseOccurrence]) -> Int? {
        func rank(_ occurrence: CourseOccurrence) -> Int {
            if occurrence.linkedSessionID != nil { return 50 }
            if occurrence.userEdited && [.absent, .ignored, .cancelled].contains(occurrence.accountingStatus) { return 40 }
            if occurrence.accountingStatus == .confirmed { return 30 }
            if occurrence.userEdited { return 20 }
            return occurrence.sourceMissing ? 0 : 10
        }
        return indices.sorted {
            let a = occurrences[$0], b = occurrences[$1]
            if rank(a) != rank(b) { return rank(a) > rank(b) }
            if a.lastSeenAt != b.lastSeenAt { return a.lastSeenAt > b.lastSeenAt }
            return a.id.uuidString < b.id.uuidString
        }.first
    }
    private static func resolveSubject(name: String, remoteID: String?, state: inout CadenceState) -> UUID {
        if let match = SubjectAliasResolver.subjectID(for: name, subjects: state.subjects) { return match }
        if let remoteID {
            let previous = Set(state.occurrences.compactMap { occurrence -> UUID? in
                guard occurrence.school?.subjectID == remoteID else { return nil }
                return occurrence.subjectID
            })
            if previous.count == 1, let id = previous.first, state.subjects.contains(where: { $0.id == id && !$0.isArchived }) { return id }
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = trimmed == trimmed.uppercased() ? trimmed.lowercased().capitalized(with: Locale(identifier: "fr_FR")) : trimmed
        let subject = Subject(name: display, position: (state.subjects.map(\.position).max() ?? -1) + 1)
        state.subjects.append(subject)
        return subject.id
    }
    private static func validate(_ snapshot: SchoolSnapshot) throws {
        func valid(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite && date.timeIntervalSince1970 >= 0 && date.timeIntervalSince1970 <= 253_402_300_799 }
        guard valid(snapshot.generatedAt), valid(snapshot.windowStart), valid(snapshot.windowEnd), snapshot.windowEnd > snapshot.windowStart,
              snapshot.timetable.count <= 100_000, snapshot.homework.count <= 100_000, snapshot.courseContent.count <= 100_000,
              Set(snapshot.timetable.map(\.eventID)).count == snapshot.timetable.count,
              Set(snapshot.homework.map(\.uid)).count == snapshot.homework.count,
              Set(snapshot.courseContent.map(\.id)).count == snapshot.courseContent.count else { throw CadenceError.invalidSchoolSnapshot }
        for event in snapshot.timetable {
            guard !event.eventID.isEmpty, !event.subjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  valid(event.startAt), valid(event.endAt), event.endAt > event.startAt,
                  event.startAt < snapshot.windowEnd, event.endAt > snapshot.windowStart else { throw CadenceError.invalidSchoolSnapshot }
        }
        for homework in snapshot.homework {
            guard !homework.uid.isEmpty, !homework.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  valid(homework.deadline), homework.lengthMinutes.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw CadenceError.invalidSchoolSnapshot }
        }
    }
}
