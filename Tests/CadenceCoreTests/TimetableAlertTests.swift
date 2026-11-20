import XCTest
@testable import CadenceCore

final class TimetableAlertTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let courseID = UUID()
    private func lesson(offset: TimeInterval = 3600) -> SchoolTimetableEvent {
        SchoolTimetableEvent(eventID: "lesson", startAt: now.addingTimeInterval(offset),
            endAt: now.addingTimeInterval(offset + 3600), subjectName: "Maths", teacherNames: ["A", "B"])
    }
    private func baseline(_ lessons: [SchoolTimetableEvent], account: String = "élève",
                          starts: TimeInterval = 0, ends: TimeInterval = 86400) -> TimetableAlertBaseline {
        let occurrences = lessons.map { lesson in
            CourseOccurrence(id: courseID, calendarIdentifier: "ecole", eventIdentifier: lesson.id,
                title: lesson.subjectName, start: lesson.startAt, end: lesson.endAt, school: lesson)
        }
        return TimetableAlertBaseline(account: account,
            window: DateInterval(start: now.addingTimeInterval(starts), end: now.addingTimeInterval(ends)),
            occurrences: occurrences, fetchedIDs: Set(lessons.map(\.id)), now: now)
    }

    func testFirstLoadAccountChangeAndWindowEdgesAreSilent() throws {
        let day = baseline([lesson()])
        XCTAssertTrue(day.changes(since: nil, now: now).isEmpty)
        XCTAssertTrue(day.changes(since: baseline([], account: "autre élève"), now: now).isEmpty)
        XCTAssertTrue(day.changes(since: baseline([], ends: 3600), now: now).isEmpty)
        XCTAssertTrue(baseline([], starts: 7200).changes(since: day, now: now).isEmpty)
        let restored = try JSONDecoder().decode(TimetableAlertBaseline.self, from: JSONEncoder().encode(day))
        XCTAssertTrue(day.changes(since: restored, now: now).isEmpty)
    }

    func testAddedRemovedCancelledAndExplicitAbsenceAreDistinct() {
        let original = lesson(), day = baseline([original]), empty = baseline([])
        XCTAssertEqual(day.changes(since: empty, now: now).map(\.kind), [.added])
        XCTAssertEqual(empty.changes(since: day, now: now).map(\.kind), [.removed])
        var cancelled = original
        cancelled.canceled = true
        cancelled.statusLabel = "Classe absente"
        XCTAssertEqual(baseline([cancelled]).changes(since: day, now: now).map(\.kind), [.cancelled])
        cancelled.statusLabel = "Professeur absent"
        XCTAssertEqual(baseline([cancelled]).changes(since: day, now: now).map(\.kind), [.teacherAbsent])
        XCTAssertEqual(empty.changes(since: baseline([cancelled]), now: now).count, 0)
        XCTAssertTrue(empty.changes(since: day, now: original.endAt).isEmpty)
    }

    func testMovedWithNewRemoteIdentityAndEditedRoom() {
        let original = lesson(), day = baseline([original])
        var moved = lesson(offset: 18_000)
        moved.eventID = "lesson|new-day"
        let changes = baseline([moved]).changes(since: day, now: now)
        XCTAssertEqual(changes.map(\.kind), [.moved])
        XCTAssertEqual(changes.first?.previousStart, original.startAt)
        var edited = original
        edited.teacherNames.reverse()
        XCTAssertTrue(baseline([edited]).changes(since: day, now: now).isEmpty)
        edited.classrooms = ["B22"]
        XCTAssertEqual(baseline([edited]).changes(since: day, now: now).map(\.kind), [.modified])
    }
}
