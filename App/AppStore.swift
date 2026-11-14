import Foundation
import Combine
import EventKit
import CadenceCore

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published private(set) var state: CadenceState
    @Published var errorMessage: String?
    @Published private(set) var calendarSources: [CalendarSource] = []
    @Published private(set) var calendarPreview: [CalendarEvent] = []
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var calendarPermissionDescription = "Calendrier non lié"
    @Published private(set) var storageDiagnostic = "Stockage local"
    @Published var route = "accueil"

    private let calendarService = CalendarIntegrationService()
    private var repository: LocalStateRepository?
    private var writesBlocked = false
    var needsRecovery: Bool { writesBlocked }
    private var previewWindow: DateInterval?
    private var previewCalendarIDs: Set<String> = []
    private var calendarObserver: NSObjectProtocol?

    private init() {
        do {
            #if targetEnvironment(simulator)
            let uiTesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
            let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("CadenceUITests", isDirectory: true)
            let repository = try LocalStateRepository(directory: uiTesting ? testDirectory : nil)
            #else
            let repository = try LocalStateRepository()
            #endif
            self.repository = repository
            #if targetEnvironment(simulator)
            if uiTesting {
                var initial = CadenceState.initial()
                initial.settings.onboardingCompleted = true
                self.state = initial
            } else {
                self.state = try repository.load()
            }
            #else
            self.state = try repository.load()
            #endif
        } catch {
            self.state = .initial()
            writesBlocked = true
            errorMessage = "Les données locales n’ont pas pu être lues. Le fichier existant est conservé. Restaurez une sauvegarde JSON pour rétablir le suivi. \(error.localizedDescription)"
        }
        calendarPermissionDescription = calendarService.permissionDescription
        calendarSources = calendarService.sources()
        lastSyncAt = state.settings.lastCalendarSync
        SystemIntegrationService.shared.onDiagnosticChange = { [weak self] in self?.updateDiagnostics() }
        updateDiagnostics()
        if !writesBlocked { SystemIntegrationService.shared.refresh(state: state) }
        calendarObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshCalendars() }
        }
    }

    /// Valider et persister une copie AVANT de publier l'état à l'interface.
    @discardableResult
    func performMutation(_ mutation: (inout CadenceState) throws -> Void) -> Bool {
        guard !writesBlocked, let repository else {
            errorMessage = "Le stockage est indisponible. Aucune modification n’a été enregistrée. Restaurez une sauvegarde."
            return false
        }
        do {
            var updated = state
            try mutation(&updated)
            try BackupCodec.validate(updated)
            try repository.save(updated)
            state = updated
            errorMessage = nil
            SystemIntegrationService.shared.refresh(state: updated)
            updateDiagnostics()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func start(kind: SessionKind, subjectID: UUID, topic: String = "", occurrenceID: UUID? = nil, origin: SessionOrigin = .timer) {
        performMutation { state in
            _ = try CadenceEngine.start(state: &state, subjectID: subjectID, kind: kind, topic: topic, origin: origin, occurrenceID: occurrenceID)
        }
    }
    func pause() { performMutation { _ = try CadenceEngine.pause(state: &$0) } }
    func resume() { performMutation { _ = try CadenceEngine.resume(state: &$0) } }
    func finish() { performMutation { _ = try CadenceEngine.finish(state: &$0) } }
    func saveSubject(_ subject: CadenceCore.Subject) { performMutation { try CadenceEngine.updateSubject(state: &$0, subject: subject) } }
    func deleteSubject(_ id: UUID) { performMutation { try CadenceEngine.deleteSubject(state: &$0, subjectID: id) } }

    func saveSession(_ session: StudySession, allowOverlap: Bool = false) {
        performMutation { state in
            if state.sessions.contains(where: { $0.id == session.id }) {
                var session = session
                let current = state.sessions.first { $0.id == session.id }!
                if current.endedAt == nil || session.endedAt == nil {
                    // Un éditeur ouvert ne peut pas annuler une pause effectuée depuis Raccourcis.
                    session.startedAt = current.startedAt
                    session.endedAt = current.endedAt
                    session.activeSegments = current.activeSegments
                }
                let timingChanged = session.startedAt != current.startedAt || session.endedAt != current.endedAt || session.subjectID != current.subjectID || session.kind != current.kind
                if timingChanged, session.kind == .course, session.linkedOccurrenceID == nil, !allowOverlap {
                    let end = session.endedAt ?? Date()
                    let conflicts = state.sessions.contains {
                        $0.id != session.id && $0.kind == .course && $0.subjectID == session.subjectID && $0.startedAt < end && ($0.endedAt ?? Date()) > session.startedAt
                    } || !CadenceEngine.overlappingOccurrences(state: state, subjectID: session.subjectID, start: session.startedAt, end: end).isEmpty
                    if conflicts { throw CadenceError.courseOverlap }
                }
                try CadenceEngine.updateSession(state: &state, session: session)
            } else {
                guard let end = session.endedAt else { throw AppStoreError.invalidSession }
                _ = try CadenceEngine.addManual(state: &state, subjectID: session.subjectID, kind: session.kind,
                    start: session.startedAt, end: end, topic: session.topic, notes: session.notes,
                    origin: session.origin, occurrenceID: session.linkedOccurrenceID, allowOverlap: allowOverlap)
            }
        }
    }
    func deleteSession(_ id: UUID) { performMutation { try CadenceEngine.deleteSession(state: &$0, sessionID: id) } }
    func setOccurrenceStatus(_ id: UUID, status: CourseStatus) { performMutation { try CadenceEngine.setStatus(state: &$0, occurrenceID: id, status: status) } }
    func confirmOccurrence(_ id: UUID, seconds: Double? = nil) { performMutation { try CadenceEngine.confirm(state: &$0, occurrenceID: id, seconds: seconds) } }
    func linkSession(sessionID: UUID, occurrenceID: UUID) { performMutation { try CadenceEngine.link(state: &$0, sessionID: sessionID, occurrenceID: occurrenceID) } }
    func unlinkSession(occurrenceID: UUID) { performMutation { try CadenceEngine.unlink(state: &$0, occurrenceID: occurrenceID) } }

    func acceptCalendarChanges(_ id: UUID) {
        performMutation { try CalendarReconciler.acceptChanges(state: &$0, occurrenceID: id) }
    }

    func keepOccurrenceChanges(_ id: UUID) {
        performMutation { try CalendarReconciler.keepPersonalChanges(state: &$0, occurrenceID: id) }
    }

    func updateOccurrence(_ id: UUID, subjectID: UUID?, title: String, start: Date, end: Date) {
        performMutation { state in
            guard end > start, let index = state.occurrences.firstIndex(where: { $0.id == id }) else { throw AppStoreError.invalidSession }
            if let subjectID { try CadenceEngine.assignSubject(state: &state, occurrenceID: id, subjectID: subjectID) }
            state.occurrences[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            state.occurrences[index].start = start
            state.occurrences[index].end = end
            state.occurrences[index].userEdited = true
        }
    }

    func updateSettings(_ settings: AppSettings) {
        var settings = settings
        // Changer de sources invalide l'aperçu, jamais les séances déjà sauvées.
        if Set(settings.selectedCalendarIDs) != Set(state.settings.selectedCalendarIDs) {
            calendarPreview = []; previewWindow = nil; previewCalendarIDs = []
            // Le consentement initial ne vaut pas import de toute nouvelle source.
            settings.calendarEnabled = false
        }
        performMutation { state in
            state.settings = settings
            CadenceEngine.setAutoCredit(state: &state, enabled: settings.autoCreditCourses)
        }
    }

    func requestCalendarAccess() async {
        do {
            _ = try await calendarService.requestAccess()
            calendarPermissionDescription = calendarService.permissionDescription
            calendarSources = calendarService.sources()
        } catch { errorMessage = error.localizedDescription }
    }

    private func syncWindow(now: Date = Date()) -> DateInterval {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return DateInterval(start: calendar.date(byAdding: .day, value: -30, to: today)!, end: calendar.date(byAdding: .day, value: 31, to: today)!)
    }

    func previewCalendarImport() async {
        do {
            let ids = Set(state.settings.selectedCalendarIDs)
            guard !ids.isEmpty else { throw AppStoreError.noCalendars }
            let available = Set(calendarService.sources().map(\.id))
            guard ids.isSubset(of: available) else { throw AppStoreError.unavailableCalendars }
            let window = syncWindow()
            let events = try calendarService.events(calendarIDs: ids, window: window)
            calendarPreview = events
            previewWindow = window
            previewCalendarIDs = ids
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func importCalendarPreview() {
        guard let window = previewWindow, previewCalendarIDs == Set(state.settings.selectedCalendarIDs) else {
            errorMessage = "Préparez l’aperçu des calendriers sélectionnés avant d’importer."
            return
        }
        let events = calendarPreview
        let ids = previewCalendarIDs
        if performMutation({ state in
            state.settings.calendarEnabled = true
            _ = CalendarReconciler.sync(state: &state, events: events, calendarIDs: ids, window: window)
        }) {
            lastSyncAt = Date()
            calendarPreview = []; previewWindow = nil
        }
    }

    func refreshCalendars() async {
        calendarPermissionDescription = calendarService.permissionDescription
        calendarSources = calendarService.sources()
        guard state.settings.calendarEnabled, !state.settings.selectedCalendarIDs.isEmpty,
              calendarService.hasAccess, !writesBlocked else { return }
        do {
            let window = syncWindow()
            let ids = Set(state.settings.selectedCalendarIDs)
            // Une source disparue d'iOS n'est pas une preuve de suppression des cours.
            let availableIDs = Set(calendarSources.map(\.id))
            let accessibleIDs = ids.intersection(availableIDs)
            guard !accessibleIDs.isEmpty else { return }
            let events = try calendarService.events(calendarIDs: accessibleIDs, window: window)
            if performMutation({ state in
                _ = CalendarReconciler.sync(state: &state, events: events, calendarIDs: accessibleIDs, window: window)
            }) { lastSyncAt = Date() }
        } catch { errorMessage = error.localizedDescription }
    }

    func foreground() async {
        await refreshCalendars()
        if !writesBlocked {
            performMutation { state in
                let enabled = state.settings.autoCreditCourses
                CadenceEngine.setAutoCredit(state: &state, enabled: enabled)
            }
        }
    }

    func backupData() throws -> Data { try BackupCodec.encode(state) }
    func csvData() throws -> Data { Data(BackupCodec.csv(state).utf8) }

    func restoreBackup(_ data: Data) {
        do {
            let restored = try BackupCodec.decode(data)
            let repository = try self.repository ?? LocalStateRepository()
            try repository.save(restored)
            self.repository = repository
            state = restored
            lastSyncAt = restored.settings.lastCalendarSync
            writesBlocked = false
            errorMessage = nil
            calendarPreview = []; previewWindow = nil
            SystemIntegrationService.shared.refresh(state: restored)
            updateDiagnostics()
        } catch { errorMessage = "Restauration refusée ; données conservées. \(error.localizedDescription)" }
    }

    private func updateDiagnostics() {
        storageDiagnostic = writesBlocked ? "Lecture impossible · fichier conservé" : "JSON local · sauvegarde atomique · \(SystemIntegrationService.shared.diagnostic)"
    }
}

private enum AppStoreError: LocalizedError {
    case invalidSession, noCalendars, unavailableCalendars
    var errorDescription: String? {
        switch self {
        case .invalidSession: return "Vérifiez la matière, le début et la fin de la séance."
        case .noCalendars: return "Choisissez au moins un calendrier pour préparer l’import."
        case .unavailableCalendars: return "Une source sélectionnée n’est plus disponible dans iOS. Vérifiez vos comptes Calendrier ou désélectionnez cette source ; son historique est conservé."
        }
    }
}
