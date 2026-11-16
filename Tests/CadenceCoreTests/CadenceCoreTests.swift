import XCTest
@testable import CadenceCore

final class CadenceCoreTests: XCTestCase {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func subject(_ name: String = "Mathématiques", aliases: [String] = ["MATH"]) -> Subject { Subject(name: name, aliases: aliases) }
    func state(auto: Bool = false) -> CadenceState { CadenceState(subjects: [subject()], settings: AppSettings(autoCreditCourses: auto)) }
    func event(_ state: CadenceState, id: String = "event-1", start: Date? = nil, end: Date? = nil, anchor: Date? = nil, recurring: Bool = false, external: String? = "external-1", title: String = "MATH groupe 2", calendar: String = "calendar-1", allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(calendarIdentifier: calendar, eventIdentifier: id, externalIdentifier: external, occurrenceAnchor: anchor, calendarName: "Cours", title: title, start: start ?? base, end: end ?? base.addingTimeInterval(3600), isAllDay: allDay, isRecurring: recurring)
    }
    func sync(_ state: inout CadenceState, _ events: [CalendarEvent], now: Date? = nil, calendars: Set<String> = ["calendar-1"]) {
        _ = CalendarReconciler.sync(state: &state, events: events, calendarIDs: calendars, window: DateInterval(start: base.addingTimeInterval(-86400), duration: 86400 * 10), now: now ?? base.addingTimeInterval(7200))
    }
    func totals(_ state: CadenceState, now: Date? = nil) -> StudyTotals {
        Statistics.totals(state: state, in: DateInterval(start: base.addingTimeInterval(-86400), duration: 86400 * 10), now: now ?? base.addingTimeInterval(86400 * 9))
    }

    func testCourseDisplayUsesAssignedSubjectAndKeepsSourceTitle() {
        var english = subject("Anglais", aliases: ["ANGLAIS"])
        let rawTitle = "ANGLAIS - PROF. TEST - [1-AGL-G7] - <14> 14AGLG7"
        var course = CourseOccurrence(calendarIdentifier: "calendar-1", eventIdentifier: "english", title: rawTitle, start: base, end: base.addingTimeInterval(3600), subjectID: english.id)
        XCTAssertEqual(course.displayTitle(in: [english]), "Anglais")
        english.name = "Anglais approfondi"
        english.isArchived = true
        XCTAssertEqual(course.displayTitle(in: [english]), "Anglais approfondi")
        XCTAssertEqual(course.title, rawTitle)

        english.name = " \n "
        XCTAssertEqual(course.displayTitle(in: [english]), rawTitle)
        XCTAssertEqual(course.displayTitle(in: []), rawTitle)
        course.subjectID = nil
        XCTAssertEqual(course.displayTitle(in: [english]), rawTitle)
    }

    func testFrenchAliasesDisplayFrenchWithoutRewritingCalendarEvents() throws {
        let french = subject("Français", aliases: ["FRANCAIS", "ACCOMPAGNEMT. PERSO.", "VIE DE CLASSE"])
        var value = CadenceState(subjects: [french])
        let titles = ["ACCOMPAGNEMT. PERSO. - PROF. TEST", "VIE DE CLASSE - PROF. TEST"]
        let inputs = titles.enumerated().map { index, title in
            event(value, id: "french-\(index)", external: "french-\(index)", title: title)
        }
        sync(&value, inputs)
        XCTAssertEqual(value.occurrences.count, 2)
        for course in value.occurrences {
            XCTAssertEqual(course.subjectID, french.id)
            XCTAssertEqual(course.displayTitle(in: value.subjects), "Français")
            XCTAssertTrue(titles.contains(course.title))
        }
        let restored = try BackupCodec.decode(BackupCodec.encode(value))
        XCTAssertEqual(Set(restored.occurrences.map(\.title)), Set(titles))
        XCTAssertEqual(restored.subjects[0].aliases, french.aliases)
    }

    func testOnlyOneActiveSessionAndRepeatedTransitionsAreIdempotent() throws {
        var value = state()
        let subjectID = value.subjects[0].id
        try CadenceEngine.start(state: &value, subjectID: subjectID, kind: .revision, at: base)
        XCTAssertThrowsError(try CadenceEngine.start(state: &value, subjectID: subjectID, kind: .course, at: base))
        XCTAssertTrue(try CadenceEngine.pause(state: &value, at: base.addingTimeInterval(900)))
        XCTAssertFalse(try CadenceEngine.pause(state: &value, at: base.addingTimeInterval(1000)))
        XCTAssertTrue(try CadenceEngine.resume(state: &value, at: base.addingTimeInterval(1200)))
        XCTAssertFalse(try CadenceEngine.resume(state: &value, at: base.addingTimeInterval(1300)))
        let finished = try XCTUnwrap(CadenceEngine.finish(state: &value, at: base.addingTimeInterval(2700)))
        XCTAssertEqual(finished.elapsed(at: base), 2400)
        XCTAssertNil(try CadenceEngine.finish(state: &value, at: base.addingTimeInterval(2800)))
        XCTAssertEqual(value.sessions.count, 1)
        try BackupCodec.validate(value)
    }

    func testPausedSessionSurvivesJSONAndDoesNotAccumulateBackgroundTime() throws {
        var value = state()
        try CadenceEngine.start(state: &value, subjectID: value.subjects[0].id, kind: .course, at: base)
        try CadenceEngine.pause(state: &value, at: base.addingTimeInterval(100))
        let recovered = try BackupCodec.decode(BackupCodec.encode(value))
        XCTAssertEqual(value, recovered)
        XCTAssertTrue(try XCTUnwrap(recovered.activeSession).isPaused)
        XCTAssertEqual(recovered.activeSession?.elapsed(at: base.addingTimeInterval(100_000)), 100)
    }

    func testRunningSessionRecoversElapsedFromTimestamps() throws {
        var value = state()
        try CadenceEngine.start(state: &value, subjectID: value.subjects[0].id, kind: .revision, at: base)
        let recovered = try BackupCodec.decode(BackupCodec.encode(value))
        XCTAssertEqual(recovered.activeSession?.elapsed(at: base.addingTimeInterval(5000)), 5000)
    }

    func testClockMovingBackwardsRejectsTransitionWithoutChangingState() throws {
        var value = state()
        try CadenceEngine.start(state: &value, subjectID: value.subjects[0].id, kind: .revision, at: base)
        let before = value
        XCTAssertThrowsError(try CadenceEngine.pause(state: &value, at: base.addingTimeInterval(-1)))
        XCTAssertEqual(value, before)
    }

    func testMidnightSplitsTenMinutesOnEachDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: "2026-11-13T22:50:00Z"))
        let end = start.addingTimeInterval(1200)
        var value = state()
        try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .revision, start: start, end: end)
        let day1 = try XCTUnwrap(calendar.dateInterval(of: .day, for: start))
        let day2 = try XCTUnwrap(calendar.dateInterval(of: .day, for: end))
        XCTAssertEqual(Statistics.totals(state: value, in: day1, now: end).revisions, 600)
        XCTAssertEqual(Statistics.totals(state: value, in: day2, now: end).revisions, 600)
    }

    func testDSTUsesActualElapsedSecondsAndLocalDayBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: "2026-10-25T00:30:00Z"))
        let end = try XCTUnwrap(formatter.date(from: "2026-10-25T02:30:00Z"))
        var value = state()
        try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .course, start: start, end: end)
        let day = try XCTUnwrap(calendar.dateInterval(of: .day, for: start))
        XCTAssertEqual(day.duration, 25 * 3600)
        XCTAssertEqual(Statistics.totals(state: value, in: day, now: end).courseMeasured, 7200)
    }

    func testTwentyImportsAreIdempotentAndFutureClassesCountZero() throws {
        var value = state(auto: true)
        let input = event(value)
        for _ in 0..<20 { sync(&value, [input], now: base.addingTimeInterval(-3600)) }
        XCTAssertEqual(value.occurrences.count, 1)
        XCTAssertEqual(value.occurrences[0].status, .scheduled)
        XCTAssertEqual(totals(value, now: base.addingTimeInterval(-1)).total, 0)
        try BackupCodec.validate(value)
    }

    func testAutoCreditNeedsExplicitConsentAndLaterRefreshWorks() {
        var value = state()
        let input = event(value)
        sync(&value, [input])
        XCTAssertEqual(totals(value).total, 0)
        CadenceEngine.setAutoCredit(state: &value, enabled: true, at: base.addingTimeInterval(7200))
        XCTAssertEqual(totals(value).courseEstimated, 3600)
        XCTAssertEqual(totals(value).courseMeasured, 0)
        CadenceEngine.setAutoCredit(state: &value, enabled: false, at: base.addingTimeInterval(7200))
        XCTAssertEqual(totals(value).total, 0)
    }

    func testMeasurementReplacesEstimateAndRevisionRemainsSeparate() throws {
        var value = state(auto: true)
        sync(&value, [event(value)])
        let occurrenceID = value.occurrences[0].id
        XCTAssertEqual(totals(value).courseEstimated, 3600)
        try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .course, start: base, end: base.addingTimeInterval(2700), occurrenceID: occurrenceID)
        try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .revision, start: base.addingTimeInterval(7200), end: base.addingTimeInterval(9000))
        let actual = totals(value)
        XCTAssertEqual(actual.courseEstimated, 0)
        XCTAssertEqual(actual.courseMeasured, 2700)
        XCTAssertEqual(actual.revisions, 1800)
        XCTAssertEqual(actual.total, 4500)
        try BackupCodec.validate(value)
    }

    func testMarkAbsentOrIgnoredRemovesEstimate() throws {
        var value = state(auto: true)
        sync(&value, [event(value)])
        try CadenceEngine.setStatus(state: &value, occurrenceID: value.occurrences[0].id, status: .absent)
        XCTAssertEqual(totals(value).total, 0)
        sync(&value, [event(value)])
        XCTAssertEqual(value.occurrences[0].status, .absent)
        XCTAssertEqual(totals(value).total, 0)
    }

    func testRecurringOccurrencesUseAnchorAndMovedExceptionRemainsOne() {
        var value = state(auto: true)
        let first = event(value, anchor: base, recurring: true)
        let secondStart = base.addingTimeInterval(86400)
        let second = event(value, start: secondStart, end: secondStart.addingTimeInterval(3600), anchor: secondStart, recurring: true)
        sync(&value, [first, second], now: base.addingTimeInterval(-1))
        let firstID = value.occurrences[0].id
        var moved = first
        moved.start = moved.start.addingTimeInterval(3600)
        moved.end = moved.end.addingTimeInterval(3600)
        sync(&value, [moved, second], now: base.addingTimeInterval(-1))
        XCTAssertEqual(value.occurrences.count, 2)
        XCTAssertEqual(value.occurrences[0].id, firstID)
        XCTAssertEqual(value.occurrences[0].start, moved.start)
    }

    func testMeasuredSessionPreservedWhenEventChangesAndAcceptSurvivesResync() throws {
        var value = state(auto: true)
        var input = event(value)
        sync(&value, [input])
        let occurrenceID = value.occurrences[0].id
        try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .course, start: base, end: base.addingTimeInterval(2700), notes: "Conserver mes notes", occurrenceID: occurrenceID)
        let session = value.sessions[0]
        input.start = input.start.addingTimeInterval(3600); input.end = input.end.addingTimeInterval(3600)
        sync(&value, [input])
        XCTAssertEqual(value.occurrences[0].status, .needsReview)
        XCTAssertEqual(value.occurrences[0].previousStatus, .measured)
        XCTAssertEqual(value.sessions[0], session)
        XCTAssertEqual(totals(value).total, 2700)
        try CalendarReconciler.acceptChanges(state: &value, occurrenceID: occurrenceID)
        sync(&value, [input])
        XCTAssertEqual(value.occurrences[0].status, .measured)
        XCTAssertEqual(value.occurrences[0].start, input.start)
        XCTAssertEqual(value.sessions[0], session)
    }

    func testKeepPersonalOverrideSurvivesIdenticalSourceSnapshot() throws {
        var value = state(auto: true)
        var input = event(value)
        sync(&value, [input])
        try CadenceEngine.confirm(state: &value, occurrenceID: value.occurrences[0].id)
        input.start = input.start.addingTimeInterval(3600); input.end = input.end.addingTimeInterval(3600)
        sync(&value, [input])
        XCTAssertEqual(value.occurrences[0].status, .needsReview)
        try CalendarReconciler.keepPersonalChanges(state: &value, occurrenceID: value.occurrences[0].id)
        sync(&value, [input])
        XCTAssertEqual(value.occurrences[0].status, .confirmed)
        XCTAssertEqual(value.occurrences[0].start, base)
        XCTAssertEqual(totals(value).courseMeasured, 3600)
    }

    func testDeletedEventKeepsConfirmedCreditAndMeasuredNotes() throws {
        var value = state(auto: true)
        sync(&value, [event(value)])
        let occurrenceID = value.occurrences[0].id
        try CadenceEngine.confirm(state: &value, occurrenceID: occurrenceID, seconds: 2500)
        sync(&value, [])
        XCTAssertTrue(value.occurrences[0].sourceMissing)
        XCTAssertEqual(value.occurrences[0].status, .needsReview)
        XCTAssertEqual(totals(value).courseMeasured, 2500)
        try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .course, start: base, end: base.addingTimeInterval(2000), notes: "Notes à conserver", occurrenceID: occurrenceID)
        sync(&value, [])
        XCTAssertEqual(value.sessions[0].notes, "Notes à conserver")
        XCTAssertEqual(totals(value).courseMeasured, 2000)
        try BackupCodec.validate(value)
    }

    func testDeletedUnconfirmedEstimateIsCancelledAndDisabledCalendarPreservesHistory() {
        var value = state(auto: true)
        sync(&value, [event(value)])
        sync(&value, [], calendars: ["another-calendar"])
        XCTAssertFalse(value.occurrences[0].sourceMissing)
        XCTAssertEqual(value.occurrences[0].status, .estimated)
        sync(&value, [])
        XCTAssertEqual(value.occurrences[0].status, .cancelled)
        XCTAssertEqual(totals(value).total, 0)
    }

    func testAcknowledgedMissingSourceDoesNotReopenReview() throws {
        var value = state(auto: true)
        sync(&value, [event(value)])
        let id = value.occurrences[0].id
        try CadenceEngine.confirm(state: &value, occurrenceID: id, seconds: 1800)
        sync(&value, [])
        try CalendarReconciler.keepPersonalChanges(state: &value, occurrenceID: id)
        sync(&value, [])
        XCTAssertTrue(value.occurrences[0].sourceMissing)
        XCTAssertEqual(value.occurrences[0].status, .confirmed)
        XCTAssertEqual(totals(value).courseMeasured, 1800)
    }

    func testPersonalScheduleOverrideDoesNotConflictWithUnchangedSource() {
        var value = state(auto: true)
        let input = event(value)
        sync(&value, [input])
        value.occurrences[0].start = base.addingTimeInterval(300)
        value.occurrences[0].title = "Mon titre personnel"
        value.occurrences[0].userEdited = true
        sync(&value, [input])
        XCTAssertEqual(value.occurrences[0].status, .estimated)
        XCTAssertEqual(value.occurrences[0].title, "Mon titre personnel")
        XCTAssertEqual(value.occurrences[0].start, base.addingTimeInterval(300))
    }

    func testSecondSessionCannotLinkToSameOccurrenceOrLinkRevision() throws {
        var value = state(auto: true)
        sync(&value, [event(value)])
        let occurrenceID = value.occurrences[0].id
        let revisionID = try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .revision, start: base, end: base.addingTimeInterval(1800))
        XCTAssertThrowsError(try CadenceEngine.link(state: &value, sessionID: revisionID, occurrenceID: occurrenceID))
        try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .course, start: base, end: base.addingTimeInterval(1800), occurrenceID: occurrenceID)
        XCTAssertThrowsError(try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .course, start: base, end: base.addingTimeInterval(1800), occurrenceID: occurrenceID, allowOverlap: true))
        XCTAssertEqual(value.sessions.count, 2)
        try BackupCodec.validate(value)
    }

    func testResyncIdentifierChangesReconcileViaExternalIDOrConservativeFingerprint() {
        var value = state(auto: true)
        var input = event(value)
        sync(&value, [input])
        let id = value.occurrences[0].id
        input.eventIdentifier = "new-apple-id"
        sync(&value, [input])
        XCTAssertEqual(value.occurrences.count, 1)
        XCTAssertEqual(value.occurrences[0].id, id)
        input.externalIdentifier = nil; input.eventIdentifier = "newest-apple-id"
        input.start = input.start.addingTimeInterval(60); input.end = input.end.addingTimeInterval(60)
        sync(&value, [input])
        XCTAssertEqual(value.occurrences.count, 1)
        XCTAssertEqual(value.occurrences[0].id, id)
    }

    func testDistinctIdenticalTimeEventsAreNeverSilentlyMerged() {
        var value = state(auto: true)
        let one = event(value, id: "one", external: nil)
        let two = event(value, id: "two", external: nil)
        sync(&value, [one, two])
        sync(&value, [one, two])
        XCTAssertEqual(value.occurrences.count, 2)
    }

    func testCollidingExternalIdentifiersDoNotMergeEventsPresentTogether() {
        var value = state(auto: true)
        let one = event(value, id: "one", external: "shared-external-id")
        let two = event(value, id: "two", external: "shared-external-id")
        for _ in 0..<20 { sync(&value, [one, two]) }
        XCTAssertEqual(value.occurrences.count, 2)
        XCTAssertEqual(Set(value.occurrences.map(\.eventIdentifier)), ["one", "two"])
    }

    func testAmbiguousFallbackNeedsReviewAndDoesNotAddNewCredit() {
        var value = state(auto: true)
        let one = event(value, id: "one", external: nil)
        let two = event(value, id: "two", external: nil)
        sync(&value, [one, two])
        let resynced = event(value, id: "changed", external: nil)
        sync(&value, [resynced])
        sync(&value, [resynced])
        XCTAssertEqual(value.occurrences.count, 3)
        XCTAssertEqual(value.occurrences.filter { $0.status == .needsReview }.count, 3)
        // Existing credits are retained for review; the ambiguous new item gets zero.
        XCTAssertEqual(totals(value).courseEstimated, 7200)
    }

    func testUnknownAndAmbiguousSubjectsAreNotGuessed() {
        var value = state(auto: true)
        value.subjects.append(subject("Autre", aliases: ["MATH"]))
        sync(&value, [event(value)])
        XCTAssertNil(value.occurrences[0].subjectID)
        XCTAssertEqual(value.occurrences[0].status, .needsReview)
        XCTAssertEqual(totals(value).total, 0)
    }

    func testAliasBoundariesPrecedenceAndDiacritics() {
        let one = Subject(name: "Français", aliases: ["FR"])
        let two = Subject(name: "Physique-Chimie", aliases: ["PC"])
        XCTAssertEqual(SubjectAliasResolver.subjectID(for: "FR — commentaire", subjects: [one, two]), one.id)
        XCTAssertNil(SubjectAliasResolver.subjectID(for: "PCSI cours", subjects: [two]))
        XCTAssertEqual(SubjectAliasResolver.subjectID(for: "Francais", subjects: [one]), one.id)
        let exception = Subject(name: "Soutien", aliases: ["Français"])
        XCTAssertEqual(SubjectAliasResolver.subjectID(for: "Français", subjects: [one, exception]), exception.id)
    }

    func testRevisionAllDayExcludedAndUnselectedCalendarsDoNotImportAsCourses() {
        var value = state(auto: true)
        value.settings.excludedKeywords = ["sport"]
        let inputs = [event(value, id: "a", title: "Révision MATH"), event(value, id: "b", title: "MATH", allDay: true), event(value, id: "c", title: "MATH sport"), event(value, id: "d", title: "MATH", calendar: "unselected")]
        sync(&value, inputs)
        XCTAssertTrue(value.occurrences.isEmpty)
        XCTAssertEqual(totals(value).total, 0)
    }

    func testManualOverlapRequiresLinkOrExplicitDistinctConfirmation() throws {
        var value = state(auto: true)
        sync(&value, [event(value)])
        XCTAssertThrowsError(try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .course, start: base, end: base.addingTimeInterval(1800)))
        XCTAssertTrue(value.sessions.isEmpty)
        try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .course, start: base, end: base.addingTimeInterval(1800), allowOverlap: true)
        XCTAssertEqual(value.sessions.count, 1)
        XCTAssertEqual(totals(value).total, 5400)
    }

    func testDeleteLinkedSessionDoesNotResurrectEstimate() throws {
        var value = state(auto: true)
        sync(&value, [event(value)])
        let id = try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .course, start: base, end: base.addingTimeInterval(1800), occurrenceID: value.occurrences[0].id)
        try CadenceEngine.deleteSession(state: &value, sessionID: id)
        sync(&value, [event(value)])
        XCTAssertEqual(totals(value).total, 0)
        XCTAssertEqual(value.occurrences[0].status, .ignored)
    }

    func testSubjectDeletionArchivesReferencedSubjectAndPreventsNewTimer() throws {
        var value = state()
        let subjectID = value.subjects[0].id
        try CadenceEngine.addManual(state: &value, subjectID: subjectID, kind: .revision, start: base, end: base.addingTimeInterval(10))
        try CadenceEngine.deleteSubject(state: &value, subjectID: subjectID)
        XCTAssertTrue(value.subjects[0].isArchived)
        XCTAssertEqual(totals(value).revisions, 10)
        XCTAssertThrowsError(try CadenceEngine.start(state: &value, subjectID: subjectID, kind: .revision, at: base))
    }

    func testJSONRoundTripPreservesSubmillisecondDurationsAndNotes() throws {
        var value = state()
        let start = Date(timeIntervalSince1970: 1234567890.123456)
        let end = start.addingTimeInterval(30.987654)
        try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .revision, start: start, end: end, notes: "Énergie, \"travail\"\nDeuxième ligne")
        let restored = try BackupCodec.decode(BackupCodec.encode(value))
        XCTAssertEqual(restored.sessions[0].startedAt.timeIntervalSince(start), 0, accuracy: 0.000001)
        XCTAssertEqual(restored.sessions[0].elapsed(at: end), value.sessions[0].elapsed(at: end), accuracy: 0.000001)
        XCTAssertEqual(restored.sessions[0].notes, value.sessions[0].notes)
        XCTAssertEqual(restored.sessions[0].id, value.sessions[0].id)
    }

    func testWriterRejectsOversizedBackupAndLargeAcceptedBackupRemainsReadable() throws {
        var value = state()
        let notes = String(repeating: "x", count: BackupCodec.maximumBytes / 2)
        try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .revision, start: base, end: base.addingTimeInterval(30), notes: notes)
        try BackupCodec.validate(value)
        let payload = try BackupCodec.encode(value)
        XCTAssertLessThanOrEqual(payload.count, BackupCodec.maximumBytes)
        let restored = try BackupCodec.decode(payload)
        XCTAssertEqual(restored.sessions[0].notes, notes)
        XCTAssertEqual(restored.sessions[0].id, value.sessions[0].id)

        value.sessions[0].notes = String(repeating: "x", count: BackupCodec.maximumBytes)
        try BackupCodec.validate(value)
        XCTAssertThrowsError(try BackupCodec.encode(value)) { error in
            guard let cadenceError = error as? CadenceError, case .invalidBackup = cadenceError else {
                return XCTFail("Une sauvegarde trop grande doit être refusée avant l’écriture.")
            }
        }
    }

    func testMalformedBackupCannotIntroduceDanglingLinksOverlappingSegmentsOrMultipleTimers() throws {
        var value = state()
        let subjectID = value.subjects[0].id
        try CadenceEngine.start(state: &value, subjectID: subjectID, kind: .revision, at: base)
        var invalid = value
        invalid.sessions[0].linkedOccurrenceID = UUID()
        XCTAssertThrowsError(try BackupCodec.validate(invalid))
        invalid = value
        invalid.sessions.append(StudySession(subjectID: subjectID, kind: .course, startedAt: base, activeSegments: [TimeSegment(start: base)]))
        XCTAssertThrowsError(try BackupCodec.validate(invalid))
        invalid = value
        invalid.sessions[0].activeSegments = [TimeSegment(start: base, end: base.addingTimeInterval(100)), TimeSegment(start: base.addingTimeInterval(99))]
        XCTAssertThrowsError(try BackupCodec.validate(invalid))
        invalid = value
        invalid.subjects.append(invalid.subjects[0])
        XCTAssertThrowsError(try BackupCodec.validate(invalid))
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"schemaVersion\":999}".utf8)))
    }

    func testLegacyV1MigrationKeepsUUIDNotesAndSeconds() throws {
        let subjectID = UUID()
        let sessionID = UUID()
        let json = """
        {"schemaVersion":1,"subjects":[{"id":"\(subjectID)","name":"Mathématiques","colorHex":"#2776F8","symbol":"book","position":0,"isArchived":false}],"sessions":[{"id":"\(sessionID)","subjectId":"\(subjectID)","kind":"revision","topic":"Révision","notes":"Ancienne note","startedAt":"2026-11-13T09:00:00Z","endedAt":"2026-11-13T09:30:00Z","activeSegments":[{"start":"2026-11-13T09:00:00Z","end":"2026-11-13T09:30:00Z"}],"origin":"app"}],"activeSession":null,"settings":{}}
        """
        let restored = try BackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(restored.schemaVersion, 3)
        XCTAssertEqual(restored.subjects[0].id, subjectID)
        XCTAssertEqual(restored.sessions[0].id, sessionID)
        XCTAssertEqual(restored.sessions[0].elapsed(), 1800)
        XCTAssertEqual(restored.sessions[0].notes, "Ancienne note")
    }

    func testCSVQuotesAccentsNewlinesAndFormulaPrefixes() throws {
        var value = state()
        try CadenceEngine.addManual(state: &value, subjectID: value.subjects[0].id, kind: .revision, start: base, end: base.addingTimeInterval(30), topic: "=1+1", notes: "Énergie, \"travail\"\r\nLigne 2")
        let output = BackupCodec.csv(value)
        XCTAssertTrue(output.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(output.contains("\"'=1+1\""))
        XCTAssertTrue(output.contains("\"Énergie, \"\"travail\"\"\r\nLigne 2\""))
        XCTAssertTrue(output.hasSuffix("\r\n"))
    }

    func testSubjectTotalsSumToOverallTotalWithConfirmedTimeAcrossMidnight() throws {
        var value = state(auto: true)
        value.subjects.append(subject("Physique", aliases: ["PC"]))
        sync(&value, [event(value)])
        try CadenceEngine.confirm(state: &value, occurrenceID: value.occurrences[0].id, seconds: 1800)
        try CadenceEngine.addManual(state: &value, subjectID: value.subjects[1].id, kind: .revision, start: base.addingTimeInterval(7200), end: base.addingTimeInterval(8400))
        let interval = DateInterval(start: base, duration: 86400)
        let bySubject = Statistics.bySubject(state: value, in: interval, now: interval.end)
        XCTAssertEqual(bySubject.values.reduce(0) { $0 + $1.total }, 3000)
        XCTAssertEqual(Statistics.totals(state: value, in: interval, now: interval.end).total, 3000)
    }
}
