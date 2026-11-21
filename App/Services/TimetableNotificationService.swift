import BackgroundTasks
import Combine
import CadenceCore
import Foundation
import UserNotifications

@MainActor
final class TimetableNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = TimetableNotificationService()
    nonisolated static let taskID = "com.cadence.study.schedule-refresh"
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "cadenza.timetable.notify")
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var message: String?
    private var authorized: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }
    private let center = UNUserNotificationCenter.current()
    private let stateKey = "cadenza.timetable.alertHistory.v1"
    private var generation = UUID()

    private struct Batch: Codable {
        var id = "timetable." + UUID().uuidString
        let changes: [TimetableAlert]
    }
    private struct History: Codable {
        var baseline: TimetableAlertBaseline
        var pending: [Batch]
    }

    func configure() {
        center.delegate = self
    }

    func readPermission() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    func setEnabled(_ value: Bool) async {
        message = nil
        if value {
            await readPermission()
            if authorization == .notDetermined {
                do {
                    _ = try await center.requestAuthorization(options: [.alert, .sound])
                    await readPermission()
                } catch {
                    message = "La demande de notification a échoué. Réessayez dans un instant."
                    return
                }
            }
            guard authorized else { return }
        }
        if enabled != value {
            enabled = value
            UserDefaults.standard.set(value, forKey: "cadenza.timetable.notify")
            resetHistory()
        }
        if value {
            scheduleNextRefresh()
            Task { await AppStore.shared.refreshSchool() }
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskID)
        }
    }

    func resetHistory() {
        generation = UUID()
        UserDefaults.standard.removeObject(forKey: stateKey)
        Task {
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("timetable.") }.map(\.identifier))
            let delivered = await center.deliveredNotifications()
            center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix("timetable.") }.map(\.request.identifier))
        }
    }

    func scheduleNextRefresh() {
        guard enabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { message = "L’actualisation en arrière-plan est indisponible. Les alertes restent actives à l’ouverture de Cadenza." }
    }

    func observe(_ snapshot: SchoolSnapshot, occurrences: [CourseOccurrence], profile: PronoteProfile) async {
        guard enabled, !snapshot.syncState.hasError, !Task.isCancelled else { return }
        let current = generation
        await readPermission()
        guard enabled, current == generation, !Task.isCancelled else { return }
        let account = [profile.establishment, profile.resourceID, profile.displayName].joined(separator: "\u{1f}")
        let now = Date()
        let baseline = TimetableAlertBaseline(account: account,
            window: DateInterval(start: snapshot.windowStart, end: snapshot.windowEnd), occurrences: occurrences,
            fetchedIDs: Set(snapshot.timetable.map(\.id)), now: now)
        let previous = UserDefaults.standard.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(History.self, from: $0) }
        var history = History(baseline: baseline, pending: [])
        if authorized, let previous, previous.baseline.account == account {
            history.pending = previous.pending.filter { $0.changes.contains { $0.lesson.endAt > now } }
            let changes = baseline.changes(since: previous.baseline, now: now)
            if !changes.isEmpty { history.pending.append(Batch(changes: changes)) }
        }
        guard save(history) else { return }
        // Persist the new baseline and pending request together. A failed add retries at
        // the next sync. A previously delivered request keeps its stable identifier.
        guard !history.pending.isEmpty else { return }
        let deliveredIDs = Set(await center.deliveredNotifications().map(\.request.identifier))
        guard enabled, current == generation, !Task.isCancelled else { return }
        for batch in history.pending {
            if !deliveredIDs.contains(batch.id) {
                do { try await center.add(request(for: batch, now: now)) }
                catch { message = "Une alerte sera réessayée à la prochaine synchronisation."; return }
                guard enabled, current == generation else {
                    center.removeDeliveredNotifications(withIdentifiers: [batch.id])
                    center.removePendingNotificationRequests(withIdentifiers: [batch.id])
                    return
                }
            }
            history.pending.removeAll { $0.id == batch.id }
            guard save(history), !Task.isCancelled else { return }
        }
    }

    private func save(_ history: History) -> Bool {
        guard let data = try? JSONEncoder().encode(history) else { return false }
        UserDefaults.standard.set(data, forKey: stateKey)
        return true
    }

    private func request(for batch: Batch, now: Date) -> UNNotificationRequest {
        let changes = batch.changes.filter { $0.lesson.endAt > now }
        let content = UNMutableNotificationContent()
        let format = DateFormatter()
        format.locale = Locale(identifier: "fr_FR")
        format.timeZone = SchoolDateCodec.parisCalendar.timeZone
        format.dateFormat = "EEE d MMM 'à' HH'h'mm"
        content.title = changes.count == 1 ? changes[0].kind.title : "\(changes.count) changements de cours"
        content.body = changes.prefix(4).map { change in
            let lesson = change.lesson
            var parts = [lesson.subjectName, format.string(from: lesson.startAt)]
            if changes.count > 1 { parts.insert(change.kind.title, at: 0) }
            if change.kind == .moved, let old = change.previousStart, old != lesson.startAt {
                parts.append("auparavant " + format.string(from: old))
            }
            if change.kind == .teacherAbsent { parts += lesson.teacherNames }
            else if change.kind == .modified { parts += lesson.classrooms + lesson.teacherNames }
            return parts.joined(separator: " · ")
        }.joined(separator: "\n")
        content.threadIdentifier = "timetable"
        content.sound = .default
        return UNNotificationRequest(identifier: batch.id, content: content, trigger: nil)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.threadIdentifier == "timetable" else { return }
        await MainActor.run { AppStore.shared.route = "cours" }
    }
}
