import Foundation

public enum SubjectAliasResolver {
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func subjectID(for title: String, subjects: [Subject]) -> UUID? {
        let text = normalize(title)
        guard !text.isEmpty else { return nil }
        let eligible = subjects.filter { !$0.isArchived }
        func matches(_ pattern: String) -> Bool {
            let normalized = normalize(pattern)
            return !normalized.isEmpty && (" " + text + " ").contains(" " + normalized + " ")
        }
        // User aliases take precedence over the fallback subject names. Ambiguous rules never guess.
        let aliases = eligible.filter { $0.aliases.contains(where: matches) }
        if !aliases.isEmpty { return aliases.count == 1 ? aliases[0].id : nil }
        let names = eligible.filter { matches($0.name) }
        return names.count == 1 ? names[0].id : nil
    }

    public static func isRevision(_ title: String) -> Bool {
        let words = Set(normalize(title).split(separator: " ").map(String.init))
        return !words.isDisjoint(with: ["revision", "revisions", "reviser"])
    }
}

public struct ImportReport: Equatable, Sendable {
    public var inserted: Int = 0
    public var updated: Int = 0
    public var missing: Int = 0
    public var ignored: Int = 0
    public var needsReview: Int = 0
    public init() {}
}

public enum CalendarReconciler {
    /// Must receive a complete, successfully fetched snapshot for precisely these calendars/window.
    /// Never call with an empty snapshot after a permission or EventKit failure.
    public static func sync(state: inout CadenceState, events: [CalendarEvent], calendarIDs: Set<String>, window: DateInterval, now: Date = Date()) -> ImportReport {
        var report = ImportReport()
        let previousIDs = Set(state.occurrences.map(\.id))
        var seen: Set<UUID> = []
        let snapshot = events.filter { calendarIDs.contains($0.calendarIdentifier) && $0.end > $0.start && $0.start < window.end && $0.end > window.start }
        let incomingIDs = Set(snapshot.map { $0.calendarIdentifier + "\u{1F}" + $0.eventIdentifier })
        for event in snapshot {
            let matching = matchingIndices(event: event, occurrences: state.occurrences, incomingIDs: incomingIDs)
            let excluded = event.isAllDay || SubjectAliasResolver.isRevision(event.title) || state.settings.excludedKeywords.contains {
                let keyword = SubjectAliasResolver.normalize($0)
                return !keyword.isEmpty && SubjectAliasResolver.normalize(event.title).contains(keyword)
            }
            if matching.count == 1, let i = matching.first {
                seen.insert(state.occurrences[i].id)
                var occurrence = state.occurrences[i]
                let changed = occurrence.sourceFingerprint.isEmpty
                    ? abs(occurrence.start.timeIntervalSince(event.start)) > 1 || abs(occurrence.end.timeIntervalSince(event.end)) > 1 || occurrence.title != event.title
                    : occurrence.sourceFingerprint != fingerprint(event)
                let protected = occurrence.userEdited || occurrence.identityUncertain || occurrence.linkedSessionID != nil || [.confirmed, .measured].contains(occurrence.accountingStatus)
                occurrence.eventIdentifier = event.eventIdentifier
                occurrence.externalIdentifier = event.externalIdentifier
                occurrence.occurrenceAnchor = event.occurrenceAnchor
                occurrence.isRecurring = event.isRecurring
                occurrence.calendarName = event.calendarName
                occurrence.lastSeenAt = now
                occurrence.sourceFingerprint = fingerprint(event)
                let returnedFromMissing = occurrence.sourceMissing
                occurrence.sourceMissing = false
                if excluded {
                    report.ignored += 1
                    if protected {
                        markReview(&occurrence)
                    } else {
                        occurrence.status = .ignored; occurrence.previousStatus = nil
                    }
                } else if changed && protected {
                    markReview(&occurrence)
                    occurrence.pendingStart = event.start
                    occurrence.pendingEnd = event.end
                    occurrence.pendingTitle = event.title
                } else {
                    if !protected {
                        occurrence.start = event.start; occurrence.end = event.end; occurrence.title = event.title
                        occurrence.subjectID = SubjectAliasResolver.subjectID(for: event.title, subjects: state.subjects)
                        occurrence.status = occurrence.subjectID == nil ? .needsReview : automaticStatus(for: occurrence, autoCredit: state.settings.autoCreditCourses, now: now)
                        occurrence.previousStatus = nil
                    } else if returnedFromMissing && occurrence.pendingStart == nil {
                        occurrence.status = occurrence.previousStatus ?? (occurrence.linkedSessionID == nil ? .confirmed : .measured)
                        occurrence.previousStatus = nil
                    }
                }
                state.occurrences[i] = occurrence
                report.updated += 1
            } else if excluded {
                // Excluded events are observed without materializing a course or affecting personal sessions.
                report.ignored += 1
                for i in matching { seen.insert(state.occurrences[i].id) }
            } else {
                let subjectID = SubjectAliasResolver.subjectID(for: event.title, subjects: state.subjects)
                var occurrence = CourseOccurrence(calendarIdentifier: event.calendarIdentifier, eventIdentifier: event.eventIdentifier, externalIdentifier: event.externalIdentifier, occurrenceAnchor: event.occurrenceAnchor, isRecurring: event.isRecurring, calendarName: event.calendarName, title: event.title, start: event.start, end: event.end, subjectID: subjectID, lastSeenAt: now, sourceFingerprint: fingerprint(event))
                if matching.isEmpty && subjectID != nil { occurrence.status = automaticStatus(for: occurrence, autoCredit: state.settings.autoCreditCourses, now: now) }
                else { occurrence.status = .needsReview; occurrence.identityUncertain = !matching.isEmpty }
                // Ambiguous candidates retain their original records; no implicit merge or credit for the new one.
                for i in matching {
                    seen.insert(state.occurrences[i].id)
                    state.occurrences[i].identityUncertain = true
                    markReview(&state.occurrences[i])
                }
                state.occurrences.append(occurrence)
                seen.insert(occurrence.id)
                report.inserted += 1
            }
        }
        for i in state.occurrences.indices {
            var occurrence = state.occurrences[i]
            guard previousIDs.contains(occurrence.id), calendarIDs.contains(occurrence.calendarIdentifier), occurrence.start >= window.start, occurrence.start < window.end, !seen.contains(occurrence.id) else { continue }
            // An acknowledged missing source must not reopen the same review on every refresh.
            guard !occurrence.sourceMissing else { continue }
            report.missing += 1
            occurrence.sourceMissing = true
            if occurrence.userEdited || occurrence.identityUncertain || occurrence.linkedSessionID != nil || [.confirmed, .measured].contains(occurrence.accountingStatus) {
                markReview(&occurrence)
            } else {
                occurrence.status = .cancelled; occurrence.previousStatus = nil
            }
            state.occurrences[i] = occurrence
        }
        refreshCredits(state: &state, now: now)
        report.needsReview = state.occurrences.filter { $0.status == .needsReview }.count
        state.settings.lastCalendarSync = now
        return report
    }

    public static func refreshCredits(state: inout CadenceState, now: Date = Date()) {
        for i in state.occurrences.indices {
            let occurrence = state.occurrences[i]
            guard !occurrence.sourceMissing, occurrence.subjectID != nil, occurrence.linkedSessionID == nil, [.scheduled, .inProgressScheduled, .estimated].contains(occurrence.status) else { continue }
            state.occurrences[i].status = automaticStatus(for: occurrence, autoCredit: state.settings.autoCreditCourses, now: now)
        }
    }

    public static func automaticStatus(for occurrence: CourseOccurrence, autoCredit: Bool, now: Date) -> CourseStatus {
        if occurrence.end <= now { return autoCredit ? .estimated : .scheduled }
        return occurrence.start <= now ? .inProgressScheduled : .scheduled
    }

    /// Accept source schedule changes without editing the measured session or its segments.
    public static func acceptChanges(state: inout CadenceState, occurrenceID: UUID, now: Date = Date()) throws {
        guard let i = state.occurrences.firstIndex(where: { $0.id == occurrenceID }) else { throw CadenceError.occurrenceNotFound }
        guard !state.occurrences[i].sourceMissing else { throw CadenceError.invalidBackup("La source calendrier est absente ; conservez ou ignorez le cours manuellement.") }
        if let start = state.occurrences[i].pendingStart { state.occurrences[i].start = start }
        if let end = state.occurrences[i].pendingEnd { state.occurrences[i].end = end }
        if let title = state.occurrences[i].pendingTitle { state.occurrences[i].title = title }
        state.occurrences[i].pendingStart = nil; state.occurrences[i].pendingEnd = nil; state.occurrences[i].pendingTitle = nil
        state.occurrences[i].status = state.occurrences[i].previousStatus ?? automaticStatus(for: state.occurrences[i], autoCredit: state.settings.autoCreditCourses, now: now)
        state.occurrences[i].previousStatus = nil
        state.occurrences[i].identityUncertain = false
    }

    public static func keepPersonalChanges(state: inout CadenceState, occurrenceID: UUID, now: Date = Date()) throws {
        guard let i = state.occurrences.firstIndex(where: { $0.id == occurrenceID }) else { throw CadenceError.occurrenceNotFound }
        state.occurrences[i].pendingStart = nil; state.occurrences[i].pendingEnd = nil; state.occurrences[i].pendingTitle = nil
        state.occurrences[i].status = state.occurrences[i].previousStatus ?? automaticStatus(for: state.occurrences[i], autoCredit: state.settings.autoCreditCourses, now: now)
        state.occurrences[i].previousStatus = nil
        state.occurrences[i].userEdited = true
        state.occurrences[i].identityUncertain = false
    }

    private static func markReview(_ occurrence: inout CourseOccurrence) {
        if occurrence.status != .needsReview { occurrence.previousStatus = occurrence.status }
        occurrence.status = .needsReview
    }

    private static func matchingIndices(event: CalendarEvent, occurrences: [CourseOccurrence], incomingIDs: Set<String>) -> [Int] {
        let candidates = occurrences.indices.filter { occurrences[$0].calendarIdentifier == event.calendarIdentifier }
        func sameOccurrence(_ occurrence: CourseOccurrence) -> Bool {
            if event.isRecurring || occurrence.isRecurring {
                let oldAnchor = occurrence.occurrenceAnchor ?? occurrence.start
                let newAnchor = event.occurrenceAnchor ?? event.start
                return abs(oldAnchor.timeIntervalSince(newAnchor)) < 1
            }
            return true
        }
        let identified = candidates.filter {
            let old = occurrences[$0]
            return !event.eventIdentifier.isEmpty && old.eventIdentifier == event.eventIdentifier && sameOccurrence(old)
        }
        if !identified.isEmpty { return identified }
        if let external = event.externalIdentifier, !external.isEmpty {
            let externalMatches = candidates.filter {
                let old = occurrences[$0]
                // External identifiers can collide. If the old Apple identifier still exists
                // in this snapshot, both events are present and must stay distinct.
                let oldStillPresent = old.eventIdentifier != event.eventIdentifier
                    && incomingIDs.contains(old.calendarIdentifier + "\u{1F}" + old.eventIdentifier)
                return !oldStillPresent && old.externalIdentifier == external && sameOccurrence(old)
            }
            if !externalMatches.isEmpty { return externalMatches }
        }
        // An ID still present elsewhere in this snapshot represents a distinct occurrence, not a resync.
        return candidates.filter {
            let old = occurrences[$0]
            guard !incomingIDs.contains(old.calendarIdentifier + "\u{1F}" + old.eventIdentifier) else { return false }
            return SubjectAliasResolver.normalize(old.title) == SubjectAliasResolver.normalize(event.title)
                && abs(old.start.timeIntervalSince(event.start)) <= 300
                && abs(old.end.timeIntervalSince(event.end)) <= 300
        }
    }

    private static func fingerprint(_ event: CalendarEvent) -> String {
        [event.calendarIdentifier, SubjectAliasResolver.normalize(event.title), String(Int(event.start.timeIntervalSince1970)), String(Int(event.end.timeIntervalSince1970))].joined(separator: "\u{1F}")
    }
}
