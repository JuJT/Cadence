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
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([event()]), now: base)
        let id = state.occurrences[0].id
        var moved = event(start: base.addingTimeInterval(900))
        moved.classrooms = ["B12"]; moved.isTest = true
        try SchoolReconciler.sync(state: &state, snapshot: snapshot([moved]), now: base)
        XCTAssertEqual(state.visibleOccurrences.count, 1)
        XCTAssertEqual(state.occurrences[0].id, id)
        XCTAssertEqual(state.occurrences[0].start, moved.startAt)
        XCTAssertEqual(state.occurrences[0].school?.classrooms, ["B12"])
        XCTAssertEqual(state.occurrences[0].school?.isTest, true)
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

    func testTwoMeasuredLegacyCoursesAreNotSilentlyMerged() throws {
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
        XCTAssertEqual(state.visibleOccurrences.count, 2)
        XCTAssertEqual(Set(state.sessions.map(\.notes)), Set(["one", "two"]))
        XCTAssertTrue(state.visibleOccurrences.contains { $0.identityUncertain })
        XCTAssertEqual(totals(state).courseEstimated, 0)
        try BackupCodec.validate(state)
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
