import ActivityKit
import CadenceCore
import Foundation
import WidgetKit

@MainActor
final class SystemIntegrationService {
    static let shared = SystemIntegrationService()
    private var pending: Task<Void, Never>?
    private(set) var lastActivityError: String?
    private(set) var lastSnapshotPublished = false
    var onDiagnosticChange: (() -> Void)?

    var diagnostic: String {
        #if CADENCE_EXTENSIONS
        let group: String
        if SharedSnapshotStore.container != nil {
            group = "Widgets : résumé publié dans le conteneur partagé; lecture à vérifier sur l’appareil."
        } else {
            #if CADENCE_KEYCHAIN_SHARED
            group = lastSnapshotPublished
                ? "Widgets : résumé publié dans le trousseau partagé; lecture à vérifier sur l’appareil."
                : "Widgets : trousseau partagé indisponible. La signature de l’app et de l’extension doit conserver le même groupe de trousseau."
            #else
            group = "Widgets : ouverture de l’app, sans données partagées dans cette variante."
            #endif
        }
        let activity = ActivityAuthorizationInfo().areActivitiesEnabled
            ? "Live Activities autorisées par le système; validation iPhone requise."
            : "Live Activities désactivées ou indisponibles."
        let receipt = SharedSnapshotStore.lastWidgetReadAt.map {
            "Dernière lecture réelle par un widget : " + $0.formatted(date: .abbreviated, time: .shortened)
        } ?? "Aucune lecture du résumé par un widget confirmée pour cette installation."
        return [group, receipt, activity, lastActivityError].compactMap { $0 }.joined(separator: "\n")
        #else
        return "Version autonome : aucune extension intégrée. Raccourcis ouvre l’app."
        #endif
    }

    func refresh(state: CadenceState) {
        let now = Date()
        if let day = Calendar.current.dateInterval(of: .day, for: now) {
            let totals = Statistics.totals(state: state, in: day, now: now)
            let active = state.activeSession
            let upcoming = state.occurrences.filter {
                $0.end > now && $0.status != .cancelled && $0.status != .ignored && $0.status != .absent
            }.sorted { $0.start < $1.start }
            let next = upcoming.first { $0.start > now }
            let week = Calendar.current.dateInterval(of: .weekOfYear, for: now)
            let weekDays: [WidgetDaySummary]? = week.map { interval in
                (0..<7).compactMap { offset in
                    guard let date = Calendar.current.date(byAdding: .day, value: offset, to: interval.start),
                          let interval = Calendar.current.dateInterval(of: .day, for: date) else { return nil }
                    let value = Statistics.totals(state: state, in: interval, now: now)
                    return WidgetDaySummary(date: date, courses: value.courseMeasured,
                        revisions: value.revisions, estimated: value.courseEstimated)
                }
            }
            let topSubject = week.flatMap { interval -> String? in
                let values = Statistics.bySubject(state: state, in: interval, now: now)
                return state.subjects.filter { (values[$0.id]?.courseMeasured ?? 0) + (values[$0.id]?.revisions ?? 0) > 0 }
                    .sorted { left, right in
                        let lhs = (values[left.id]?.courseMeasured ?? 0) + (values[left.id]?.revisions ?? 0)
                        let rhs = (values[right.id]?.courseMeasured ?? 0) + (values[right.id]?.revisions ?? 0)
                        return lhs == rhs ? left.name < right.name : lhs > rhs
                    }.first?.name
            }
            let snapshot = WidgetSnapshot(updatedAt: now, courseMeasured: totals.courseMeasured,
                courseEstimated: totals.courseEstimated, revisions: totals.revisions,
                activeSubject: active.flatMap { session in state.subjects.first { $0.id == session.subjectID }?.name },
                activeKind: active?.kind.label, isPaused: active?.isPaused ?? false,
                nextCourseTitle: next?.displayTitle(in: state.subjects), nextCourseStart: next?.start,
                weekDays: weekDays, topSubjectName: topSubject,
                upcomingCourses: upcoming.prefix(12).map {
                    WidgetCourseSummary(title: String($0.displayTitle(in: state.subjects).prefix(120)), start: $0.start, end: $0.end)
                })
            lastSnapshotPublished = SharedSnapshotStore.write(snapshot)
            if lastSnapshotPublished { WidgetCenter.shared.reloadAllTimelines() }
        }
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            await self?.reconcileActivity(state: state)
        }
    }

    private func reconcileActivity(state: CadenceState) async {
        #if CADENCE_EXTENSIONS
        defer { onDiagnosticChange?() }
        let existing = Activity<SessionActivityAttributes>.activities
        guard state.settings.liveActivityEnabled, let session = state.activeSession else {
            for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let subject = state.subjects.first { $0.id == session.subjectID }
        let now = Date()
        let elapsed = session.elapsed(at: now)
        let content = ActivityContent(state: SessionActivityAttributes.ContentState(
            subjectName: subject?.name ?? "Matière archivée", kindLabel: session.kind.label,
            symbol: session.kind == .course ? "book.closed.fill" : "pencil.line",
            elapsedSeconds: elapsed, runningSince: session.isPaused ? nil : now.addingTimeInterval(-elapsed),
            isPaused: session.isPaused), staleDate: now.addingTimeInterval(8 * 3600))
        for activity in existing where activity.attributes.sessionID != session.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if let current = existing.first(where: { $0.attributes.sessionID == session.id && $0.activityState != .ended && $0.activityState != .dismissed }) {
            await current.update(content)
            lastActivityError = nil
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            guard now.timeIntervalSince(session.startedAt) < 8 * 3600 else {
                lastActivityError = "Séance de plus de 8 heures : la Live Activity n’est pas relancée automatiquement. Votre séance continue dans Cadence."
                return
            }
            do {
                _ = try Activity<SessionActivityAttributes>.request(
                    attributes: SessionActivityAttributes(sessionID: session.id), content: content, pushType: nil)
                lastActivityError = nil
            } catch {
                // Diagnostic local seulement. L’échec ne modifie jamais la séance persistée.
                lastActivityError = "Impossible de créer la Live Activity : \(error.localizedDescription)"
            }
        }
        #else
        onDiagnosticChange?()
        #endif
    }
}
