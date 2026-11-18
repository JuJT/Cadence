import XCTest
@testable import CadenceCore

final class HomeworkIdentityMigrationTests: XCTestCase {
    let base = SchoolDateCodec.date(from: "2026-11-16T07:00:00Z")!
    func state() -> CadenceState { CadenceState(subjects: [Subject(name: "Mathématiques", aliases: ["MATH"]), Subject(name: "Français")]) }
    func task(_ uid: String, pronoteID: String? = nil, description: String = "Calculer 2 + 3") -> SchoolHomework {
        SchoolHomework(uid: uid, subject: "MATH", deadline: base.addingTimeInterval(86400), description: description, pronoteID: pronoteID)
    }
    func snapshot(_ tasks: [SchoolHomework]) -> SchoolSnapshot {
        SchoolSnapshot(generatedAt: base, homework: tasks, windowStart: base.addingTimeInterval(-86400), windowEnd: base.addingTimeInterval(7 * 86400))
    }

    func testProviderUIDChangePreservesCompletionClassificationAndMeasuredHomeworkLinks() throws {
        var value = state()
        let old = task("old-provider-uid", pronoteID: "assignment-1")
        try SchoolReconciler.sync(state: &value, snapshot: snapshot([old]), now: base)
        try CadenceEngine.start(state: &value, subjectID: value.subjects[0].id, kind: .revision, homeworkID: old.uid, at: base)
        try CadenceEngine.finish(state: &value, at: base.addingTimeInterval(600))
        try CadenceEngine.setHomeworkCompletion(state: &value, homeworkID: old.uid, isDone: true, at: base)
        try CadenceEngine.assignHomeworkSubject(state: &value, homeworkID: old.uid, subjectID: value.subjects[1].id)
        let localUpdate = value.homework[0].localUpdatedAt
        let replacement = task("direct-provider-uid", pronoteID: "assignment-1", description: "Énoncé actualisé et plus complet")
        for _ in 0..<2 { try SchoolReconciler.sync(state: &value, snapshot: snapshot([replacement]), now: base.addingTimeInterval(1200)) }
        XCTAssertEqual(value.homework.count, 1)
        XCTAssertEqual(value.homework[0].id, old.uid)
        XCTAssertEqual(value.homework[0].source.uid, replacement.uid)
        XCTAssertEqual(value.homework[0].source.description, replacement.description)
        XCTAssertTrue(value.homework[0].isDone)
        XCTAssertFalse(value.homework[0].sourceDone)
        XCTAssertEqual(value.homework[0].localUpdatedAt, localUpdate)
        XCTAssertEqual(value.homework[0].subjectID, value.subjects[1].id)
        XCTAssertEqual(value.sessions[0].activeHomeworkID, old.uid)
        XCTAssertEqual(value.sessions[0].homeworkWorkSegments?.first?.homeworkID, old.uid)
        XCTAssertEqual(Statistics.homeworkSeconds(state: value, in: DateInterval(start: base, duration: 1800), now: base.addingTimeInterval(1800))[old.uid], 600)
        value = try BackupCodec.decode(BackupCodec.encode(value))
        try SchoolReconciler.sync(state: &value, snapshot: snapshot([old]), now: base.addingTimeInterval(1800))
        XCTAssertEqual(value.homework.count, 1)
        XCTAssertEqual(value.homework[0].id, old.uid)
        XCTAssertTrue(value.homework[0].isDone)
        XCTAssertTrue(value.homework[0].sourceIdentityAliases?.contains(replacement.uid) ?? false)
    }

    func testStrictReadableDescriptionFallbackBridgesIDEncodingWithoutIgnoringMathOperators() throws {
        var value = state()
        var old = task("legacy", pronoteID: "42", description: "<p>Calculer&nbsp;<b>2 + 3</b></p>")
        old.done = true
        try SchoolReconciler.sync(state: &value, snapshot: snapshot([old]), now: base)
        try CadenceEngine.setHomeworkCompletion(state: &value, homeworkID: old.uid, isDone: false, at: base)
        var replacement = task("native", pronoteID: "0x2A", description: "CALCULER 2 + 3")
        replacement.deadline = old.deadline.addingTimeInterval(3600)
        try SchoolReconciler.sync(state: &value, snapshot: snapshot([replacement]), now: base)
        XCTAssertEqual(value.homework.count, 1)
        XCTAssertEqual(value.homework[0].id, old.uid)
        XCTAssertFalse(value.homework[0].isDone)
        let different = task("another-task", pronoteID: "0x2B", description: "Calculer 2 - 3")
        try SchoolReconciler.sync(state: &value, snapshot: snapshot([different]), now: base)
        XCTAssertEqual(value.homework.count, 2, "Plus and minus must not normalize to the same exercise")
        XCTAssertEqual(value.homework.first { $0.id == old.uid }?.localCompletionOverride, false)
    }

    func testAmbiguousHomeworkDescriptionsAndExactUIDsAreNeverConsumedByAnotherAssignment() throws {
        var value = state()
        let one = task("one"), two = task("two")
        try SchoolReconciler.sync(state: &value, snapshot: snapshot([one, two]), now: base)
        try CadenceEngine.setHomeworkCompletion(state: &value, homeworkID: one.uid, isDone: true, at: base)
        let incoming = task("new-id")
        try SchoolReconciler.sync(state: &value, snapshot: snapshot([incoming]), now: base)
        XCTAssertEqual(value.homework.count, 3)
        XCTAssertEqual(value.homework.first { $0.id == one.uid }?.isDone, true)
        XCTAssertEqual(value.homework.first { $0.id == incoming.uid }?.localCompletionOverride, nil)

        var exactReserved = state()
        try SchoolReconciler.sync(state: &exactReserved, snapshot: snapshot([one]), now: base)
        try CadenceEngine.setHomeworkCompletion(state: &exactReserved, homeworkID: one.uid, isDone: true, at: base)
        try SchoolReconciler.sync(state: &exactReserved, snapshot: snapshot([incoming, one]), now: base)
        XCTAssertEqual(exactReserved.homework.count, 2)
        XCTAssertEqual(exactReserved.homework.first { $0.id == one.uid }?.isDone, true)
        XCTAssertEqual(exactReserved.homework.first { $0.id == incoming.uid }?.isDone, false)
    }
}
