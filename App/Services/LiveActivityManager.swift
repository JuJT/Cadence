import ActivityKit
import CadenceCore
import Foundation
import UIKit
import WidgetKit

@MainActor
final class SystemIntegrationService {
    static let shared = SystemIntegrationService()
    // A burst replaces one pending state instead of chaining an unbounded queue
    // of tasks, each holding an obsolete copy of the school cache.
    private var pendingActivityState: CadenceState?
    private var activityWorker: Task<Void, Never>?
    private var lastActivityKey: ActivityKey?
    private var latestState: CadenceState?
    private var snapshotWorker: Task<Void, Never>?
    private var minuteWorker: Task<Void, Never>?
    private var lastSnapshotState: CadenceState?
    private var lastSnapshotMinute: Int?
    private var lastSnapshotPayload: Data?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private(set) var lastActivityError: String?
    private(set) var lastSnapshotPublished = false
    var onDiagnosticChange: (() -> Void)?

    private struct ActivityKey: Equatable {
        let enabled: Bool
        let sessionID: UUID?
        let name: String?
        let kind: SessionKind?
        let segments: [TimeSegment]
        init(state: CadenceState) {
            enabled = state.settings.liveActivityEnabled
            let session = enabled ? state.activeSession : nil
            sessionID = session?.id
            name = session.flatMap { session in state.subjects.first { $0.id == session.subjectID }?.name }
            kind = session?.kind
            segments = session?.activeSegments ?? []
        }
    }

    private init() {
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.scheduleSnapshot()
                self.scheduleMinuteRefresh()
            }
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.minuteWorker?.cancel(); self?.minuteWorker = nil }
        })
    }

    var diagnostic: String {
        #if CADENCE_EXTENSIONS
        let group: String
        if SharedSnapshotStore.container != nil {
            group = "Widgets : résumé publié dans le conteneur partagé; lecture à vérifier sur l’appareil."
        } else {
            #if CADENCE_KEYCHAIN_SHARED
            group = lastSnapshotPublished
                ? "Widgets : résumé écrit dans le trousseau autorisé de l’app ; la lecture par l’extension reste distincte."
                : "Widgets : écriture du résumé indisponible. La signature de l’app et de l’extension doit autoriser un groupe commun."
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
        return [group, SharedSnapshotStore.transportDiagnostic, receipt, activity, lastActivityError].compactMap { $0 }.joined(separator: "\n")
        #else
        return "Version autonome : aucune extension intégrée. Raccourcis ouvre l’app."
        #endif
    }

    func refresh(state: CadenceState) {
        latestState = state
        scheduleSnapshot()
        scheduleMinuteRefresh()
        pendingActivityState = state
        guard activityWorker == nil else { return }
        activityWorker = Task { [weak self] in
            guard let self else { return }
            while let state = self.pendingActivityState {
                self.pendingActivityState = nil
                let key = ActivityKey(state: state)
                if key != self.lastActivityKey || self.activityNeedsRecovery(key) {
                    await self.reconcileActivity(state: state)
                    self.lastActivityKey = key
                }
            }
            self.activityWorker = nil
        }
    }

    private func activityNeedsRecovery(_ key: ActivityKey) -> Bool {
        #if CADENCE_EXTENSIONS
        let activities = Activity<SessionActivityAttributes>.activities
        guard let id = key.sessionID else { return !activities.isEmpty }
        return !activities.contains { $0.attributes.sessionID == id && $0.activityState != .ended && $0.activityState != .dismissed }
        #else
        return false
        #endif
    }

    private func scheduleSnapshot() {
        guard snapshotWorker == nil else { return }
        snapshotWorker = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            guard let self else { return }
            self.snapshotWorker = nil
            guard let state = self.latestState else { return }
            self.publishSnapshotIfNeeded(state: state)
        }
    }

    private func scheduleMinuteRefresh() {
        guard minuteWorker == nil, UIApplication.shared.applicationState == .active else { return }
        minuteWorker = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date().timeIntervalSince1970
                let delay = max(1, 60 - now.truncatingRemainder(dividingBy: 60))
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                guard let self, UIApplication.shared.applicationState == .active else { return }
                self.scheduleSnapshot()
            }
        }
    }

    private func publishSnapshotIfNeeded(state: CadenceState) {
        let now = Date()
        let minute = Int(now.timeIntervalSince1970 / 60)
        // Date-based totals advance once per foreground minute; identical calls
        // within it do not repeatedly calculate seven days of statistics.
        guard !lastSnapshotPublished || minute != lastSnapshotMinute || state != lastSnapshotState else { return }
        lastSnapshotMinute = minute
        lastSnapshotState = state
        if let day = Calendar.current.dateInterval(of: .day, for: now) {
            let totals = Statistics.totals(state: state, in: day, now: now)
            let active = state.activeSession
            let upcoming = state.visibleOccurrences.filter {
                $0.end > now && !$0.sourceMissing && $0.status != .cancelled && $0.status != .ignored && $0.status != .absent &&
                $0.school?.canceled != true && $0.school?.exempted != true
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
                return state.subjects.filter { (values[$0.id]?.courses ?? 0) + (values[$0.id]?.revisions ?? 0) > 0 }
                    .sorted { left, right in
                        let lhs = (values[left.id]?.courses ?? 0) + (values[left.id]?.revisions ?? 0)
                        let rhs = (values[right.id]?.courses ?? 0) + (values[right.id]?.revisions ?? 0)
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
            // Ignore only the publication timestamp for deduplication. Session
            // state, upcoming course, day boundaries and all durations still count.
            let payload = snapshotPayload(snapshot)
            guard !lastSnapshotPublished || payload == nil || payload != lastSnapshotPayload else { return }
            lastSnapshotPublished = SharedSnapshotStore.write(snapshot)
            if lastSnapshotPublished {
                lastSnapshotPayload = payload
                WidgetCenter.shared.reloadAllTimelines()
            }
            onDiagnosticChange?()
        }
    }

    private func snapshotPayload(_ snapshot: WidgetSnapshot) -> Data? {
        guard let data = try? JSONEncoder().encode(snapshot),
              var values = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        values.removeValue(forKey: "updatedAt")
        // A new day needs a fresh zero-valued publication as well: widget views
        // correctly refuse to present yesterday's snapshot as today's totals.
        values["publicationDay"] = Calendar.current.startOfDay(for: snapshot.updatedAt).timeIntervalSince1970
        return try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
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
                lastActivityError = "Séance de plus de 8 heures : la Live Activity n’est pas relancée automatiquement. Votre séance continue dans Cadenza."
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
