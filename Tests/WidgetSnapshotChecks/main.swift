import Foundation

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
}

// A snapshot from the original shipping version, before weekly/course summaries.
let legacy = Data("""
{"updatedAt":800000000,"courseMeasured":3600,"courseEstimated":900,"revisions":1800,"isPaused":false}
""".utf8)
let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: legacy)
expect(decoded.weekDays == nil && decoded.upcomingCourses == nil, "Legacy snapshots must remain readable")
expect(decoded.courseMeasured == 3600 && decoded.revisions == 1800, "Legacy real durations must be preserved")

let now = Date(timeIntervalSinceReferenceDate: 800000000)
let days = (0..<7).map { offset in
    WidgetDaySummary(date: now.addingTimeInterval(Double(offset) * 86400), courses: 3600, revisions: 1200, estimated: 600)
}
let courses = (0..<12).map { offset in
    WidgetCourseSummary(title: String(repeating: "é", count: 120),
        start: now.addingTimeInterval(Double(offset) * 3600), end: now.addingTimeInterval(Double(offset + 1) * 3600))
}
let snapshot = WidgetSnapshot(updatedAt: now, courseMeasured: 3600, courseEstimated: 900, revisions: 1800,
    activeSubject: "Français", activeKind: "Révision", isPaused: true,
    nextCourseTitle: "Anglais", nextCourseStart: now.addingTimeInterval(3600),
    weekDays: days, topSubjectName: "Français", upcomingCourses: courses)
let data = try JSONEncoder().encode(snapshot)
expect(data.count < 16_384, "The bounded widget aggregate must fit its transport limit")
let roundTrip = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
expect(roundTrip.weekDays?.count == 7 && roundTrip.upcomingCourses?.count == 12, "Full summaries must survive serialization")
expect(roundTrip.weekDays?.reduce(0, { $0 + $1.measured }) == 33_600, "Measured totals exclude estimated time")
expect(CompactDuration.text(.infinity) == "0 min" && CompactDuration.clock(.nan) == "00:00:00", "Invalid duration input must never crash a widget")
print("WidgetSnapshot: legacy decoding, real-data round trip, transport size, accounting separation and safe duration formatting passed.")
