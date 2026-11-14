import Foundation

public struct StudyTotals: Equatable, Sendable {
    public var courseMeasured: TimeInterval
    public var courseEstimated: TimeInterval
    public var revisions: TimeInterval
    public var total: TimeInterval { courseMeasured + courseEstimated + revisions }
    public var courses: TimeInterval { courseMeasured + courseEstimated }
    public init(courseMeasured: TimeInterval = 0, courseEstimated: TimeInterval = 0, revisions: TimeInterval = 0) {
        self.courseMeasured = courseMeasured; self.courseEstimated = courseEstimated; self.revisions = revisions
    }
    public static func + (lhs: StudyTotals, rhs: StudyTotals) -> StudyTotals {
        StudyTotals(courseMeasured: lhs.courseMeasured + rhs.courseMeasured, courseEstimated: lhs.courseEstimated + rhs.courseEstimated, revisions: lhs.revisions + rhs.revisions)
    }
}

public enum Statistics {
    public static func totals(state: CadenceState, in interval: DateInterval, now: Date = Date()) -> StudyTotals {
        bySubject(state: state, in: interval, now: now).values.reduce(StudyTotals(), +)
    }

    public static func bySubject(state: CadenceState, in interval: DateInterval, now: Date = Date()) -> [UUID: StudyTotals] {
        guard interval.end > interval.start, interval.start < now else { return [:] }
        let bounded = DateInterval(start: interval.start, end: min(interval.end, now))
        var totals: [UUID: StudyTotals] = [:]
        for session in state.sessions {
            let duration = session.seconds(in: bounded, now: now)
            var value = totals[session.subjectID] ?? StudyTotals()
            if session.kind == .course { value.courseMeasured += duration } else { value.revisions += duration }
            totals[session.subjectID] = value
        }
        let sessionIDs = Set(state.sessions.map(\.id))
        for occurrence in state.occurrences {
            guard let subjectID = occurrence.subjectID, occurrence.end > occurrence.start else { continue }
            // Measured time replaces the estimate for the entire occurrence, including other days.
            if let linked = occurrence.linkedSessionID, sessionIDs.contains(linked) { continue }
            let status = occurrence.accountingStatus
            guard status == .estimated || status == .confirmed else { continue }
            // A scheduled future class is never credited, including malformed imported status flags.
            guard occurrence.end <= now else { continue }
            let intersection = max(0, min(occurrence.end, bounded.end).timeIntervalSince(max(occurrence.start, bounded.start)))
            guard intersection > 0 else { continue }
            var value = totals[subjectID] ?? StudyTotals()
            if status == .estimated { value.courseEstimated += intersection }
            else {
                // A confirmed duration is allocated proportionally across its planned interval.
                let duration = occurrence.confirmedSeconds ?? occurrence.end.timeIntervalSince(occurrence.start)
                value.courseMeasured += duration * intersection / occurrence.end.timeIntervalSince(occurrence.start)
            }
            totals[subjectID] = value
        }
        return totals
    }

    public static func dayInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 24 * 3600)
    }
}

public enum DurationText {
    public static func clock(_ seconds: TimeInterval) -> String {
        let safe = seconds.isFinite ? min(max(0, seconds), 3_155_760_000_000) : 0
        let value = Int(safe.rounded(.down))
        return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
    }
    public static func short(_ seconds: TimeInterval) -> String {
        let safe = seconds.isFinite ? min(max(0, seconds), 3_155_760_000_000) : 0
        let minutes = Int(safe / 60)
        return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }
}
