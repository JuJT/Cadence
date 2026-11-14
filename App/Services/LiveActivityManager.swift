import ActivityKit
import CadenceCore
import Foundation
import WidgetKit

@MainActor
final class SystemIntegrationService {
    static let shared = SystemIntegrationService()
    private var pending: Task<Void, Never>?
    private(set) var lastActivityError: String?
    var onDiagnosticChange: (() -> Void)?

    var diagnostic: String {
        #if CADENCE_EXTENSIONS
        let group = SharedSnapshotStore.container == nil
            ? "Widget : ouverture de l’app, sans données partagées."
            : "Conteneur partagé disponible; signature et widget à tester sur appareil."
        let activity = ActivityAuthorizationInfo().areActivitiesEnabled
            ? "Live Activities autorisées par le système; validation iPhone requise."
            : "Live Activities désactivées ou indisponibles."
        return [group, activity, lastActivityError].compactMap { $0 }.joined(separator: "\n")
        #else
        return "Version autonome : aucune extension intégrée. Raccourcis ouvre l’app."
        #endif
    }

    func refresh(state: CadenceState) {
        let now = Date()
        if let day = Calendar.current.dateInterval(of: .day, for: now) {
            let totals = Statistics.totals(state: state, in: day, now: now)
            let active = state.activeSession
            let next = state.occurrences.filter { $0.start > now && $0.status != .cancelled && $0.status != .ignored }
                .sorted { $0.start < $1.start }.first
            let snapshot = WidgetSnapshot(updatedAt: now, courseMeasured: totals.courseMeasured,
                courseEstimated: totals.courseEstimated, revisions: totals.revisions,
                activeSubject: active.flatMap { session in state.subjects.first { $0.id == session.subjectID }?.name },
                activeKind: active?.kind.label, isPaused: active?.isPaused ?? false,
                nextCourseTitle: next?.title, nextCourseStart: next?.start)
            if SharedSnapshotStore.write(snapshot) { WidgetCenter.shared.reloadAllTimelines() }
        }
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            await self?.reconcileActivity(state: state)
        }
    }

    private func reconcileActivity(state: CadenceState) async {
        defer { onDiagnosticChange?() }
        #if CADENCE_EXTENSIONS
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
        #endif
    }
}
