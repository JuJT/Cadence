import XCTest
@testable import CadenceCore

final class SchoolCoreTests: XCTestCase {
    let base = SchoolDateCodec.date(from: "2026-11-16T07:10:00Z")!
    func makeState() -> CadenceState {
        CadenceState(subjects: [Subject(name: "Mathématiques", aliases: ["MATH"]),
            Subject(name: "Français", aliases: ["FRANCAIS", "VIE DE CLASSE", "ACCOMPAGNEMT. PERSO."])],
            settings: AppSettings(selectedCalendarIDs: ["legacy"], autoCreditCourses: false, calendarEnabled: true))
    }
    func event(_ id: String = "lesson-1", start: Date? = nil, canceled: Bool = false, exempted: Bool = false,
               subject: String = "MATH", resource: String? = nil) -> SchoolTimetableEvent {
        let start = start ?? base
        return SchoolTimetableEvent(eventID: id, startAt: start, endAt: start.addingTimeInterval(3600), subjectName: subject,
            teacherNames: ["Professeur fictif"], classrooms: ["A01"], canceled: canceled, exempted: exempted, lessonResourceID: resource)
    }
    func snapshot(_ events: [SchoolTimetableEvent] = [], homework: [SchoolHomework] = [], contents: [SchoolCourseContent] = []) -> SchoolSnapshot {
        SchoolSnapshot(generatedAt: base, timetable: events, homework: homework, courseContent: contents,
            windowStart: base.addingTimeInterval(-7 * 86400), windowEnd: base.addingTimeInterval(7 * 86400))
    }
    func homework(_ id: String = "hw-1", subject: String = "MATH", done: Bool = false) -> SchoolHomework {
        SchoolHomework(uid: id, subject: subject, deadline: base.addingTimeInterval(86400), description: "Exercice de démonstration", done: done)
    }
    func totals(_ state: CadenceState) -> StudyTotals {
        Statistics.totals(state: state, in: DateInterval(start: base.addingTimeInterval(-86400), duration: 3 * 86400), now: base.addingTimeInterval(2 * 86400))
    }

    func testSchoolFeedIsIdempotentAndPastCoursesAreAutomatic() throws {
        var state = makeState()
        for _ in 0..<20 { try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()]), now: base.addingTimeInterval(7200)) }
        XCTAssertEqual(state.visibleOccurrences.count, 1)
        XCTAssertEqual(state.occurrences.count, 1)
        XCTAssertEqual(state.occurrences[0].status, .estimated)
        XCTAssertTrue(state.settings.autoCreditCourses)
        XCTAssertFalse(state.settings.calendarEnabled)
        XCTAssertEqual(totals(state).courseEstimated, 3600)
        XCTAssertNotNil(state.schoolSync?.lastSuccessfulFetch)
    }

    func testFutureCourseCountsZeroThenBecomesAutomaticWithoutAnotherNetworkFetch() throws {
        var state = makeState()
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()]), now: base.addingTimeInterval(-60))
        let interval = DateInterval(start: base.addingTimeInterval(-60), duration: 7200)
        XCTAssertEqual(Statistics.totals(state: state, in: interval, now: base).total, 0)
        XCTAssertEqual(Statistics.totals(state: state, in: interval, now: base.addingTimeInterval(4000)).courseEstimated, 3600)
    }

    func testSourceScheduleRoomAndAssessmentChangesKeepOccurrenceUUID() throws {
        var state = makeState()
        var initial = event()
        initial.subjectID = "42"
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([initial]), now: base)
        let id = state.occurrences[0].id
        var moved = event(start: base.addingTimeInterval(900))
        moved.classrooms = ["B12"]; moved.isTest = true; moved.subjectID = "42"
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([moved]), now: base)
        XCTAssertEqual(state.visibleOccurrences.count, 1)
        XCTAssertEqual(state.occurrences[0].id, id)
        XCTAssertEqual(state.occurrences[0].start, moved.startAt)
        XCTAssertEqual(state.occurrences[0].school?.classrooms, ["B12"])
        XCTAssertEqual(state.occurrences[0].school?.isTest, true)
        var directProvider = moved
        directProvider.eventID = "0xA0|2026-11-16T08:25:00"
        directProvider.subjectID = "0x2A"
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([directProvider]), now: base)
        XCTAssertEqual(state.visibleOccurrences.count, 1)
        XCTAssertEqual(state.visibleOccurrences[0].id, id, "Exact source name and slot bridge an ID encoding change")
        XCTAssertEqual(state.visibleOccurrences[0].school?.subjectID, directProvider.subjectID)
    }

    func testCompositeUpstreamIdentifierCanMoveWhenBaseIsUnique() throws {
        var state = makeState()
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event("42|old")]), now: base)
        let id = state.occurrences[0].id
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event("42|new", start: base.addingTimeInterval(7200))]), now: base)
        XCTAssertEqual(state.visibleOccurrences.count, 1)
        XCTAssertEqual(state.occurrences[0].id, id)
        XCTAssertEqual(state.occurrences[0].eventIdentifier, "42|new")
    }

    func testPersonalSchoolScheduleSurvivesRefreshAndBackupWhileSourceMetadataUpdates() throws {
        var state = makeState()
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()]), now: base)
        let id = state.occurrences[0].id
        let personalStart = base.addingTimeInterval(3 * 3600)
        state.occurrences[0].start = personalStart
        state.occurrences[0].end = personalStart.addingTimeInterval(1800)
        state.occurrences[0].title = "Mon horaire corrigé"
        state.occurrences[0].schoolScheduleOverridden = true
        state.occurrences[0].userEdited = true
        var remote = event(start: base.addingTimeInterval(900))
        remote.classrooms = ["Nouvelle salle"]
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([remote]), now: base.addingTimeInterval(7200))
        XCTAssertEqual(state.occurrences[0].id, id)
        XCTAssertEqual(state.occurrences[0].start, personalStart)
        XCTAssertEqual(state.occurrences[0].end, personalStart.addingTimeInterval(1800))
        XCTAssertEqual(state.occurrences[0].title, "Mon horaire corrigé")
        XCTAssertEqual(state.occurrences[0].status, .scheduled)
        XCTAssertEqual(state.occurrences[0].school?.startAt, remote.startAt)
        XCTAssertEqual(state.occurrences[0].school?.classrooms, ["Nouvelle salle"])
        let restored = try BackupCodec.decode(BackupCodec.encode(state))
        XCTAssertEqual(restored.occurrences[0].schoolScheduleOverridden, true)
        XCTAssertEqual(restored.occurrences[0].start, personalStart)
        XCTAssertEqual(restored.occurrences[0].title, "Mon horaire corrigé")
    }

    func testResidualCompositeMoveReservesOtherDatesAndPreservesUUIDsExclusionAndPersonalSession() throws {
        var state = makeState()
        let monday = event("42|2026-11-16T08:10:00")
        let tuesday = event("42|2026-11-17T08:10:00", start: base.addingTimeInterval(86400))
        let now = base.addingTimeInterval(3 * 86400)
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([monday, tuesday]), now: now)
        let mondayID = state.occurrences[0].id
        let tuesdayID = state.occurrences[1].id
        try CadenceEngine.confirm(state: &state, occurrenceID: mondayID, seconds: 3600)
        try CadenceEngine.setStatus(state: &state, occurrenceID: tuesdayID, status: .absent)
        let revisionID = try CadenceEngine.addManual(state: &state, subjectID: state.subjects[0].id, kind: .revision,
            start: base.addingTimeInterval(7200), end: base.addingTimeInterval(8100), notes: "Séance personnelle indépendante")
        let moved = event("42|2026-11-16T08:15:00", start: base.addingTimeInterval(300))
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([moved, tuesday]), now: now)
        XCTAssertEqual(state.visibleOccurrences.count, 2)
        XCTAssertEqual(state.occurrences.first { $0.eventIdentifier == moved.eventID }?.id, mondayID)
        XCTAssertEqual(state.occurrences.first { $0.eventIdentifier == tuesday.eventID }?.id, tuesdayID)
        XCTAssertEqual(state.occurrences.first { $0.id == mondayID }?.start, moved.startAt)
        XCTAssertEqual(state.occurrences.first { $0.id == tuesdayID }?.status, .absent)
        XCTAssertFalse(state.occurrences.contains { $0.sourceMissing })
        XCTAssertEqual(state.sessions.first?.id, revisionID)
        XCTAssertEqual(state.sessions.first?.notes, "Séance personnelle indépendante")
        let total = Statistics.totals(state: state, in: DateInterval(start: base, duration: 4 * 86400), now: now)
        XCTAssertEqual(total.courseMeasured, 3600)
        XCTAssertEqual(total.courseEstimated, 0)
        XCTAssertEqual(total.revisions, 900)
        let stable = state.visibleOccurrences.map(\.id)
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([moved, tuesday]), now: now)
        XCTAssertEqual(state.visibleOccurrences.map(\.id), stable)
    }

    func testResidualMatchingNeverConsumesAnExactIdentityStillPresentInSnapshot() throws {
        var state = makeState()
        let retained = event("42|2026-11-16T08:10:00")
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([retained]), now: base)
        let retainedID = state.occurrences[0].id
        // These aliases resolve to the same local subject, but these are two
        // distinct source IDs present together. The earlier one is visited first.
        let added = event("42|2026-11-16T08:09:30", start: base.addingTimeInterval(-30), subject: "Mathématiques")
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([added, retained]), now: base)
        XCTAssertEqual(state.visibleOccurrences.count, 2)
        XCTAssertEqual(state.occurrences.first { $0.eventIdentifier == retained.eventID }?.id, retainedID)
        XCTAssertNotEqual(state.occurrences.first { $0.eventIdentifier == added.eventID }?.id, retainedID)
        XCTAssertFalse(state.occurrences.contains { $0.supersededByOccurrenceID != nil })
    }

    func testAmbiguousResidualMovesKeepDistinctRecordsAndDoNotAddAutomaticCredit() throws {
        var state = makeState()
        let original = event("42|2026-11-16T08:10:00")
        let unchanged = event("42|2026-11-17T08:10:00", start: base.addingTimeInterval(86400))
        let now = base.addingTimeInterval(3 * 86400)
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([original, unchanged]), now: now)
        let originalID = state.occurrences[0].id
        let unchangedID = state.occurrences[1].id
        try CadenceEngine.confirm(state: &state, occurrenceID: originalID)
        try CadenceEngine.setStatus(state: &state, occurrenceID: unchangedID, status: .absent)
        let a = event("42|2026-11-16T08:15:00", start: base.addingTimeInterval(300))
        let b = event("42|2026-11-16T10:10:00", start: base.addingTimeInterval(7200))
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([a, b, unchanged]), now: now)
        XCTAssertEqual(state.visibleOccurrences.count, 4)
        XCTAssertFalse(state.occurrences.contains { $0.supersededByOccurrenceID != nil })
        XCTAssertEqual(state.occurrences.first { $0.id == originalID }?.status, .confirmed)
        XCTAssertEqual(state.occurrences.first { $0.eventIdentifier == unchanged.eventID }?.id, unchangedID)
        for id in [a.eventID, b.eventID] {
            XCTAssertEqual(state.occurrences.first { $0.eventIdentifier == id }?.status, .needsReview)
            XCTAssertEqual(state.occurrences.first { $0.eventIdentifier == id }?.identityUncertain, true)
        }
        let identities = Set(state.visibleOccurrences.map(\.id))
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([a, b, unchanged]), now: now)
        XCTAssertEqual(Set(state.visibleOccurrences.map(\.id)), identities)
        XCTAssertTrue(state.visibleOccurrences.filter { $0.eventIdentifier == a.eventID || $0.eventIdentifier == b.eventID }.allSatisfy { $0.status == .needsReview })
        let total = Statistics.totals(state: state, in: DateInterval(start: base, duration: 4 * 86400), now: now)
        XCTAssertEqual(total.courseMeasured, 3600)
        XCTAssertEqual(total.courseEstimated, 0)
        try CadenceEngine.setStatus(state: &state, occurrenceID: originalID, status: .absent)
        for _ in 0..<2 { try SchoolReconciler.sync(state: &state, snapshot: snapshot([a, b, unchanged]), now: now) }
        XCTAssertEqual(state.occurrences.first { $0.id == originalID }?.status, .absent)
        XCTAssertTrue(state.visibleOccurrences.filter { $0.eventIdentifier == a.eventID || $0.eventIdentifier == b.eventID }.allSatisfy { $0.status == .needsReview })
        XCTAssertEqual(Statistics.totals(state: state, in: DateInterval(start: base, duration: 4 * 86400), now: now).total, 0)
        let corrected = try XCTUnwrap(state.occurrences.firstIndex { $0.id == originalID })
        state.occurrences[corrected].status = .estimated
        state.occurrences[corrected].schoolScheduleOverridden = true
        state.occurrences[corrected].start = base.addingTimeInterval(60)
        state.occurrences[corrected].end = base.addingTimeInterval(3660)
        for _ in 0..<2 { try SchoolReconciler.sync(state: &state, snapshot: snapshot([a, b, unchanged]), now: now) }
        XCTAssertTrue(state.visibleOccurrences.filter { $0.eventIdentifier == a.eventID || $0.eventIdentifier == b.eventID }.allSatisfy { $0.status == .needsReview })
        XCTAssertEqual(Statistics.totals(state: state, in: DateInterval(start: base, duration: 4 * 86400), now: now).courseEstimated, 3600)
    }

    func testResidualCompositeMatchingNeverAdoptsOldHistoryOutsideTheResponseWindow() throws {
        var state = makeState()
        let old = event("42|2026-11-16T08:10:00")
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([old]), now: base.addingTimeInterval(7200))
        let oldID = state.occurrences[0].id
        try CadenceEngine.confirm(state: &state, occurrenceID: oldID)
        let later = event("42|2026-12-06T08:10:00", start: base.addingTimeInterval(20 * 86400))
        let response = SchoolSnapshot(timetable: [later], windowStart: base.addingTimeInterval(10 * 86400), windowEnd: base.addingTimeInterval(30 * 86400))
        try SchoolReconciler.sync(state: &state, snapshot: response, now: base.addingTimeInterval(21 * 86400))
        XCTAssertEqual(state.visibleOccurrences.count, 2)
        XCTAssertEqual(state.occurrences.first { $0.id == oldID }?.start, old.startAt)
        XCTAssertEqual(state.occurrences.first { $0.id == oldID }?.status, .confirmed)
        XCTAssertFalse(state.occurrences.first { $0.id == oldID }?.sourceMissing ?? true)
        XCTAssertNotEqual(state.occurrences.first { $0.eventIdentifier == later.eventID }?.id, oldID)
    }

    func testCanceledAndExemptedCoursesNeverGenerateAutomaticCredit() throws {
        var state = makeState()
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([
            event("cancelled", canceled: true), event("exempted", start: base.addingTimeInterval(7200), exempted: true)]), now: base.addingTimeInterval(20_000))
        XCTAssertTrue(state.visibleOccurrences.allSatisfy { $0.status == .cancelled })
        XCTAssertEqual(totals(state).total, 0)
    }

    func testLocalAbsenceAndExclusionSurviveRemoteRefresh() throws {
        var state = makeState()
        let events = [event(), event("lesson-2", start: base.addingTimeInterval(7200))]
        try SchoolReconciler.sync(state: &state, snapshot: snapshot(events), now: base.addingTimeInterval(20_000))
        try CadenceEngine.setStatus(state: &state, occurrenceID: state.occurrences[0].id, status: .absent)
        try CadenceEngine.setStatus(state: &state, occurrenceID: state.occurrences[1].id, status: .ignored)
        for i in state.occurrences.indices {
            state.occurrences[i].previousStatus = state.occurrences[i].status
            state.occurrences[i].status = .needsReview
        }
        try SchoolReconciler.sync(state: &state, snapshot: snapshot(events), now: base.addingTimeInterval(20_001))
        XCTAssertEqual(state.occurrences.map(\.status), [.absent, .ignored])
        XCTAssertEqual(totals(state).total, 0)
    }

    func testPhotographedLegacyDuplicateMergesWithoutLosingConfirmationOrAliases() throws {
        var state = makeState()
        let french = state.subjects[1]
        let old = CourseOccurrence(calendarIdentifier: "legacy", eventIdentifier: "old-uid", calendarName: "Emploi du temps",
            title: "FRANCAIS - Ancien groupe", start: base, end: base.addingTimeInterval(3600), subjectID: french.id,
            status: .confirmed, confirmedSeconds: 3600, sourceMissing: true, userEdited: true)
        let duplicate = CourseOccurrence(calendarIdentifier: "legacy", eventIdentifier: "new-uid", calendarName: "Emploi du temps",
            title: "FRANCAIS - Nouveau groupe", start: base, end: base.addingTimeInterval(3600), subjectID: french.id, status: .estimated)
        state.occurrences = [old, duplicate]
        let result = try SchoolReconciler.sync(state: &state, snapshot: snapshot([event(subject: "FRANCAIS")]), now: base.addingTimeInterval(7200))
        XCTAssertEqual(result.mergedDuplicates, 1)
        XCTAssertEqual(state.occurrences.count, 2, "Historical records stay recoverable")
        XCTAssertEqual(state.visibleOccurrences.map(\.id), [old.id])
        XCTAssertEqual(totals(state).courseMeasured, 3600)
        XCTAssertEqual(totals(state).courseEstimated, 0)
        XCTAssertEqual(state.subjects[1].aliases, french.aliases)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(state)), state)
    }

    func testFrenchPersonalAliasesResolveSchoolCoursesWithoutNewSubjects() throws {
        var state = makeState()
        let frenchID = state.subjects[1].id
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([
            event("ap", subject: "ACCOMPAGNEMT. PERSO."),
            event("class", start: base.addingTimeInterval(7200), subject: "VIE DE CLASSE")]), now: base)
        XCTAssertEqual(state.subjects.count, 2)
        XCTAssertTrue(state.visibleOccurrences.allSatisfy { $0.subjectID == frenchID })
    }

    func testManualCourseAndIndependentRevisionSurviveAndDoNotDoubleCount() throws {
        var state = makeState()
        let subject = state.subjects[0].id
        let manualID = try CadenceEngine.addManual(state: &state, subjectID: subject, kind: .course, start: base,
            end: base.addingTimeInterval(1800), notes: "Note personnelle conservée")
        let revisionID = try CadenceEngine.addManual(state: &state, subjectID: subject, kind: .revision,
            start: base.addingTimeInterval(3600), end: base.addingTimeInterval(4200))
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()]), now: base.addingTimeInterval(7200))
        XCTAssertEqual(Set(state.sessions.map(\.id)), Set([manualID, revisionID]))
        XCTAssertEqual(state.sessions[0].notes, "Note personnelle conservée")
        XCTAssertEqual(state.sessions[0].linkedOccurrenceID, state.visibleOccurrences[0].id)
        XCTAssertEqual(totals(state).courseMeasured, 1800)
        XCTAssertEqual(totals(state).courseEstimated, 0)
        XCTAssertEqual(totals(state).revisions, 600)
    }

    func testDuplicateCardsAreArchivedWithoutMergingOrLosingTheirMeasuredSessions() throws {
        var state = makeState()
        let subject = state.subjects[0].id
        for id in ["one", "two"] {
            let occurrence = CourseOccurrence(calendarIdentifier: "legacy", eventIdentifier: id, title: "MATH", start: base,
                end: base.addingTimeInterval(3600), subjectID: subject)
            state.occurrences.append(occurrence)
            try CadenceEngine.addManual(state: &state, subjectID: subject, kind: .course, start: base,
                end: base.addingTimeInterval(1800), notes: id, occurrenceID: occurrence.id, allowOverlap: true)
        }
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()]), now: base.addingTimeInterval(7200))
        XCTAssertEqual(state.sessions.count, 2)
        XCTAssertEqual(state.visibleOccurrences.count, 1)
        XCTAssertEqual(state.occurrences.count, 2)
        XCTAssertEqual(Set(state.sessions.map(\.notes)), Set(["one", "two"]))
        let archived = try XCTUnwrap(state.occurrences.first { $0.supersededByOccurrenceID != nil })
        let archivedSession = try XCTUnwrap(state.sessions.first { $0.linkedOccurrenceID == archived.id })
        XCTAssertEqual(archived.linkedSessionID, archivedSession.id)
        var edited = archivedSession
        edited.notes = "Note toujours modifiable dans l’historique"
        try CadenceEngine.updateSession(state: &state, session: edited)
        XCTAssertEqual(state.sessions.first { $0.id == edited.id }?.notes, edited.notes)
        XCTAssertEqual(totals(state).courseEstimated, 0)
        XCTAssertEqual(totals(state).courses, 3600)
        try BackupCodec.validate(state)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(state)), state)
    }

    func testReligionOrphanVersionsAndRoomChangeProduceOneVisibleCourse() throws {
        var state = makeState()
        let religion = Subject(name: "Religion", aliases: [])
        let previousClassification = Subject(name: "Enseignement catholique", aliases: [])
        state.subjects += [religion, previousClassification]
        let name = "ENS.RELIG.CATHOLIQUE"
        var cancelledSource = event("religion-old", canceled: true, subject: name)
        cancelledSource.subjectID = "religion-source"
        cancelledSource.classrooms = ["Ancienne salle"]
        var activeSource = event("religion-live", subject: name)
        activeSource.subjectID = "religion-source"
        activeSource.classrooms = ["Nouvelle salle"]
        let oldCalendar = CourseOccurrence(calendarIdentifier: "legacy", eventIdentifier: "old-calendar-id",
            title: name + " - PROFESSEUR TEST - [GROUPE]", start: base, end: base.addingTimeInterval(3600),
            subjectID: religion.id, status: .cancelled, sourceMissing: true, userEdited: true)
        let oldSchool = CourseOccurrence(calendarIdentifier: SchoolReconciler.sourceIdentifier, eventIdentifier: cancelledSource.eventID,
            title: name, start: base, end: base.addingTimeInterval(3600), subjectID: previousClassification.id,
            status: .cancelled, sourceMissing: true, userEdited: true, school: cancelledSource)
        let current = CourseOccurrence(calendarIdentifier: SchoolReconciler.sourceIdentifier, eventIdentifier: activeSource.eventID,
            title: name, start: base, end: base.addingTimeInterval(3600), subjectID: previousClassification.id,
            status: .needsReview, identityUncertain: true, school: activeSource)
        state.occurrences = [oldCalendar, oldSchool, current]
        XCTAssertEqual(state.visibleOccurrences.count, 1, "Unlinked missing cancellations are archives, not extra lessons")
        for _ in 0..<3 { try SchoolReconciler.sync(state: &state, snapshot: snapshot([activeSource]), now: base.addingTimeInterval(7200)) }
        XCTAssertEqual(state.visibleOccurrences.count, 1)
        XCTAssertEqual(state.visibleOccurrences[0].id, current.id)
        XCTAssertEqual(state.visibleOccurrences[0].school?.classrooms, ["Nouvelle salle"])
        XCTAssertFalse(state.visibleOccurrences[0].identityUncertain)
        XCTAssertEqual(state.visibleOccurrences[0].status, .estimated)
        XCTAssertEqual(state.occurrences.count, 3, "Old records remain available for backup and recovery")
        XCTAssertEqual(state.occurrences.filter { $0.supersededByOccurrenceID == current.id }.count, 2)
        XCTAssertEqual(totals(state).courses, 3600)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(state)), state)
    }

    func testCompleteFeedUsesUniqueActiveVersionInsteadOfCancelledRoomTeacherVersions() throws {
        var state = makeState()
        var cancelled = event("room-v1", canceled: true)
        cancelled.classrooms = ["Salle A"]; cancelled.teacherNames = ["Ancien professeur"]
        var secondCancelled = event("room-v2", canceled: true)
        secondCancelled.classrooms = ["Salle B"]
        var active = event("room-v3")
        active.classrooms = ["Salle C"]; active.teacherNames = ["Professeur actuel"]
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([cancelled]), now: base.addingTimeInterval(7200))
        let originalID = state.visibleOccurrences[0].id
        state.occurrences[0].userEdited = true // historical subject edit, not a cancellation choice
        for _ in 0..<3 {
            try SchoolReconciler.sync(state: &state, snapshot: snapshot([cancelled, active, secondCancelled]), now: base.addingTimeInterval(7200))
        }
        XCTAssertEqual(state.visibleOccurrences.count, 1)
        XCTAssertEqual(state.visibleOccurrences[0].id, originalID)
        XCTAssertEqual(state.visibleOccurrences[0].eventIdentifier, active.eventID)
        XCTAssertEqual(state.visibleOccurrences[0].school?.teacherNames, active.teacherNames)
        XCTAssertEqual(state.visibleOccurrences[0].school?.classrooms, active.classrooms)
        XCTAssertEqual(state.visibleOccurrences[0].status, .estimated)
        XCTAssertEqual(totals(state).courses, 3600)
    }

    func testCachedReligionRepairWorksOfflineWithoutInventingASynchronizationOrChangingHomework() throws {
        var state = makeState()
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()], homework: [homework()]), now: base)
        let lastSync = state.schoolSync
        let settings = state.settings
        let current = state.visibleOccurrences[0]
        state.occurrences[0].status = .needsReview
        state.occurrences[0].identityUncertain = true
        let old = CourseOccurrence(calendarIdentifier: "legacy", eventIdentifier: "old-room", title: "MATH - PROFESSEUR - ANCIENNE SALLE",
            start: base, end: base.addingTimeInterval(3600), subjectID: state.subjects[0].id,
            status: .cancelled, sourceMissing: true, userEdited: true)
        state.occurrences.append(old)
        try CadenceEngine.setHomeworkCompletion(state: &state, homeworkID: "hw-1", isDone: true, at: base)
        let work = state.homework
        let result = try SchoolReconciler.repairCachedOccurrences(state: &state, now: base.addingTimeInterval(7200))
        XCTAssertEqual(result.mergedDuplicates, 1)
        XCTAssertEqual(state.visibleOccurrences.map(\.id), [current.id])
        XCTAssertEqual(state.visibleOccurrences[0].status, .estimated)
        XCTAssertEqual(state.visibleOccurrences[0].lastSeenAt, current.lastSeenAt)
        XCTAssertEqual(state.schoolSync, lastSync)
        XCTAssertEqual(state.settings, settings)
        XCTAssertEqual(state.homework, work)
        XCTAssertEqual(totals(state).courses, 3600)
        let stable = state
        try SchoolReconciler.repairCachedOccurrences(state: &state, now: base.addingTimeInterval(7200))
        XCTAssertEqual(state, stable)
    }

    func testRemoteCancellationCanBeUndoneWithoutTurningGenericEditsIntoExclusions() throws {
        var state = makeState()
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()]), now: base.addingTimeInterval(7200))
        let id = state.visibleOccurrences[0].id
        state.occurrences[0].userEdited = true
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event(canceled: true)]), now: base.addingTimeInterval(7200))
        XCTAssertEqual(state.visibleOccurrences[0].status, .cancelled)
        XCTAssertEqual(totals(state).courses, 0)
        for _ in 0..<2 { try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()]), now: base.addingTimeInterval(7200)) }
        XCTAssertEqual(state.visibleOccurrences[0].id, id)
        XCTAssertEqual(state.visibleOccurrences[0].status, .estimated)
        XCTAssertEqual(totals(state).courses, 3600)
        XCTAssertNil(state.visibleOccurrences[0].localStatusOverride)
    }

    func testExplicitLocalCancellationAndAbsencePersistUntilAutomaticTrackingIsRestored() throws {
        var state = makeState()
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()]), now: base.addingTimeInterval(7200))
        let id = state.visibleOccurrences[0].id
        for choice in [CourseStatus.absent, .cancelled, .ignored] {
            try CadenceEngine.setStatus(state: &state, occurrenceID: id, status: choice)
            for _ in 0..<2 { try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()]), now: base.addingTimeInterval(7200)) }
            XCTAssertEqual(state.visibleOccurrences[0].localStatusOverride, choice)
            XCTAssertEqual(state.visibleOccurrences[0].status, choice)
            XCTAssertEqual(totals(state).courses, 0)
            state = try BackupCodec.decode(BackupCodec.encode(state))
        }
        try CadenceEngine.setStatus(state: &state, occurrenceID: id, status: .scheduled)
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()]), now: base.addingTimeInterval(7200))
        XCTAssertNil(state.visibleOccurrences[0].localStatusOverride)
        XCTAssertEqual(totals(state).courses, 3600)
        try CadenceEngine.setStatus(state: &state, occurrenceID: id, status: .ignored)
        try CadenceEngine.confirm(state: &state, occurrenceID: id, seconds: 1800)
        XCTAssertNil(state.visibleOccurrences[0].localStatusOverride)
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event(canceled: true)]), now: base.addingTimeInterval(7200))
        XCTAssertEqual(totals(state).courses, 1800, "A personal actual duration is preserved independently of a later source cancellation")
    }

    func testTwoDistinctActiveSourceIDsAreNeverCollapsedBasedOnRoomMetadataAlone() throws {
        var state = makeState()
        var one = event("parallel-a"); one.classrooms = ["A"]
        var two = event("parallel-b"); two.classrooms = ["B"]
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([one, two]), now: base.addingTimeInterval(7200))
        XCTAssertEqual(state.visibleOccurrences.count, 2)
        XCTAssertEqual(Set(state.visibleOccurrences.map(\.eventIdentifier)), Set([one.eventID, two.eventID]))
        XCTAssertFalse(state.occurrences.contains { $0.supersededByOccurrenceID != nil })
        XCTAssertEqual(totals(state).courses, 0, "An ambiguous feed must not invent a second automatic duration")
    }

    func testUnifiedCoursesCategoryIncludesAutomaticAndActualTimeWithLegacyProvenancePreserved() throws {
        var state = makeState()
        try CadenceEngine.addManual(state: &state, subjectID: state.subjects[0].id, kind: .course,
            start: base.addingTimeInterval(7200), end: base.addingTimeInterval(8400))
        try CadenceEngine.addManual(state: &state, subjectID: state.subjects[0].id, kind: .revision,
            start: base.addingTimeInterval(9000), end: base.addingTimeInterval(9600))
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()]), now: base.addingTimeInterval(10_000))
        let total = totals(state)
        XCTAssertEqual(total.courses, 4800)
        XCTAssertEqual(total.revisions, 600)
        XCTAssertEqual(total.total, total.courses + total.revisions)
        XCTAssertEqual(total.courseMeasured, 1200)
        XCTAssertEqual(total.courseEstimated, 3600)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(state)), state)
    }

    func testWindowDoesNotRemoveOlderHistoryAndInvalidResponseIsAtomic() throws {
        var state = makeState()
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()]), now: base.addingTimeInterval(7200))
        let outside = SchoolSnapshot(windowStart: base.addingTimeInterval(10 * 86400), windowEnd: base.addingTimeInterval(20 * 86400))
        try SchoolReconciler.sync(state: &state, snapshot: outside, now: base.addingTimeInterval(7200))
        XCTAssertFalse(state.occurrences[0].sourceMissing)
        XCTAssertEqual(totals(state).courseEstimated, 3600)
        let previous = state
        XCTAssertThrowsError(try SchoolReconciler.sync(state: &state, snapshot: snapshot([event(), event()]), now: base))
        XCTAssertEqual(state, previous)
    }

    func testHomeworkSourceAndLocalCompletionAreReconciledExplicitly() throws {
        var state = makeState()
        try SchoolReconciler.sync(state: &state, snapshot: snapshot(homework: [homework(done: true)]), now: base)
        XCTAssertTrue(state.homework[0].isDone)
        try CadenceEngine.setHomeworkCompletion(state: &state, homeworkID: "hw-1", isDone: false, at: base)
        var remote = homework(done: true); remote.description = "Description actualisée"
        try SchoolReconciler.sync(state: &state, snapshot: snapshot(homework: [remote]), now: base.addingTimeInterval(10))
        XCTAssertFalse(state.homework[0].isDone)
        XCTAssertTrue(state.homework[0].sourceDone)
        XCTAssertEqual(state.homework[0].source.description, remote.description)
        try CadenceEngine.clearHomeworkCompletionOverride(state: &state, homeworkID: "hw-1")
        XCTAssertTrue(state.homework[0].isDone)
    }

    func testHomeworkSwitchingAndPausesAllocateExactTimeWithoutAdditionalStudyCredit() throws {
        var state = makeState()
        try SchoolReconciler.sync(state: &state, snapshot: snapshot(homework: [homework("a"), homework("b")]), now: base)
        try CadenceEngine.start(state: &state, subjectID: state.subjects[0].id, kind: .revision, homeworkID: "a", at: base)
        try CadenceEngine.pause(state: &state, at: base.addingTimeInterval(10))
        try CadenceEngine.resume(state: &state, at: base.addingTimeInterval(20))
        try CadenceEngine.setActiveHomework(state: &state, homeworkID: "b", at: base.addingTimeInterval(30))
        try CadenceEngine.setActiveHomework(state: &state, homeworkID: nil, at: base.addingTimeInterval(40))
        try CadenceEngine.finish(state: &state, at: base.addingTimeInterval(60))
        let interval = DateInterval(start: base, duration: 120)
        let work = Statistics.homeworkSeconds(state: state, in: interval, now: base.addingTimeInterval(120))
        XCTAssertEqual(work["a"], 20)
        XCTAssertEqual(work["b"], 10)
        XCTAssertEqual(Statistics.totals(state: state, in: interval, now: base.addingTimeInterval(120)).revisions, 50)
        XCTAssertFalse(state.homework[0].isDone)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(state)), state)
    }

    func testHomeworkCanAttachToExistingOtherSubjectWithoutReclassifyingTheSession() throws {
        var state = makeState()
        try SchoolReconciler.sync(state: &state, snapshot: snapshot(homework: [homework(subject: "FRANCAIS")]), now: base)
        let maths = state.subjects[0].id
        try CadenceEngine.start(state: &state, subjectID: maths, kind: .revision, at: base)
        try CadenceEngine.setActiveHomework(state: &state, homeworkID: "hw-1", at: base.addingTimeInterval(10))
        try CadenceEngine.finish(state: &state, at: base.addingTimeInterval(20))
        XCTAssertEqual(state.sessions[0].subjectID, maths)
        XCTAssertEqual(Statistics.homeworkSeconds(state: state, in: DateInterval(start: base, duration: 30), now: base.addingTimeInterval(30))["hw-1"], 10)
    }

    func testMissingHomeworkAndManualSubjectMappingRemainAvailableOffline() throws {
        var state = makeState()
        try SchoolReconciler.sync(state: &state, snapshot: snapshot(homework: [homework()]), now: base)
        try CadenceEngine.assignHomeworkSubject(state: &state, homeworkID: "hw-1", subjectID: state.subjects[1].id)
        try CadenceEngine.setHomeworkCompletion(state: &state, homeworkID: "hw-1", isDone: true)
        try SchoolReconciler.sync(state: &state, snapshot: snapshot(homework: [homework()]), now: base)
        XCTAssertEqual(state.homework[0].subjectID, state.subjects[1].id)
        try SchoolReconciler.sync(state: &state, snapshot: snapshot(), now: base)
        XCTAssertTrue(state.homework[0].sourceMissing)
        XCTAssertTrue(state.homework[0].isDone)
        let restored = try BackupCodec.decode(BackupCodec.encode(state))
        XCTAssertEqual(restored.homework[0].subjectID, state.subjects[1].id)
    }

    func testPedagogicalContentRequiresExactResourceRelation() throws {
        var state = makeState()
        let content = SchoolCourseContent(resourceID: "resource-a", contentID: "content-a", title: "Chapitre fictif")
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event(resource: "resource-b")], contents: [content]), now: base)
        XCTAssertTrue(SchoolReconciler.contents(for: state.visibleOccurrences[0], state: state).isEmpty)
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event(resource: "resource-a")], contents: [content]), now: base)
        XCTAssertEqual(SchoolReconciler.contents(for: state.visibleOccurrences[0], state: state), [content])
    }

    func testParisTimestampConversionIncludesWinterSummerAndRejectsDSTGap() {
        XCTAssertEqual(SchoolDateCodec.parisDate(from: "2026-01-12T08:10:00"), SchoolDateCodec.date(from: "2026-01-12T07:10:00Z"))
        XCTAssertEqual(SchoolDateCodec.parisDate(from: "2026-06-15T08:10:00"), SchoolDateCodec.date(from: "2026-06-15T06:10:00Z"))
        XCTAssertNil(SchoolDateCodec.parisDate(from: "2026-03-29T02:30:00"))
    }

    func testSchoolJSONContractAcceptsPreciseUTCAndFlexibleAttachments() throws {
        let json = """
        {"generated_at":"2026-11-16T10:00:00.123456Z","window_start":"2026-11-01T00:00:00Z","window_end":"2026-12-01T00:00:00Z",
         "timetable":[{"event_id":"fictional|2026-11-16","start_local":"2026-11-16T08:10:00","end_local":"2026-11-16T09:10:00","start_at":"2026-11-16T07:10:00+00:00","end_at":"2026-11-16T08:10:00+00:00","subject_id":42,"subject_name":"MATH","teacher_names":[],"classrooms":[],"group_names":[],"canceled":false,"exempted":false,"is_test":false,"lesson_resource_id":null}],
         "homework":[{"uid":"hw","subject":"MATH","deadline":"2026-11-17","description":"Description entière","done":false,"difficulty":2,"length_minutes":20,"attachment_names":["Feuille.pdf"],"external_links":[{"title":"Document","url":"https://example.com/fiche"}]}],
         "course_content":[],"sync_state":{"has_error":false}}
        """
        let snapshot = try SchoolSnapshot.decode(Data(json.utf8))
        XCTAssertEqual(snapshot.timetable[0].subjectID, "42")
        XCTAssertEqual(snapshot.timetable[0].startAt, base)
        XCTAssertEqual(snapshot.homework[0].attachmentLabels, ["Feuille.pdf"])
        XCTAssertEqual(snapshot.homework[0].resourceLinks[0].url.absoluteString, "https://example.com/fiche")
        XCTAssertTrue(SchoolJSON.array([.string("javascript:alert(1)"), .string("file:///private/file")]).links.isEmpty)
    }

    func testVersionTwoBackupMigratesWithoutChangingHistoricalIdentifiers() throws {
        var state = makeState()
        let id = try CadenceEngine.addManual(state: &state, subjectID: state.subjects[0].id, kind: .revision,
            start: base, end: base.addingTimeInterval(600), notes: "Ancienne note")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupCodec.encode(state)) as? [String: Any])
        object["schemaVersion"] = 2
        object.removeValue(forKey: "homework"); object.removeValue(forKey: "courseContents"); object.removeValue(forKey: "schoolSync")
        let restored = try BackupCodec.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.schemaVersion, 3)
        XCTAssertEqual(restored.sessions[0].id, id)
        XCTAssertEqual(restored.sessions[0].notes, "Ancienne note")
        XCTAssertEqual(restored.subjects, state.subjects)
        XCTAssertTrue(restored.settings.autoCreditCourses)
        XCTAssertTrue(restored.homework.isEmpty)
    }
}
