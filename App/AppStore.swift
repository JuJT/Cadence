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
    @Published private(set) var schoolSignedIn = false
    @Published private(set) var schoolEmail: String?
    @Published private(set) var schoolSyncing = false
    @Published private(set) var schoolStatus = "Connexion scolaire à configurer"
    @Published private(set) var schoolError: String?

    private let calendarService = CalendarIntegrationService()
    private let schoolService = SupabaseSchoolService()
    private var lastSchoolAttempt: Date?
    private var schoolEpoch = UUID()
    private var schoolOperation: UUID?
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
                if ProcessInfo.processInfo.arguments.contains("--uitesting-courses") {
                    // Données fictives, isolées du stockage normal et exclues des appareils physiques.
                    let calendar = Calendar.current
                    let today = calendar.startOfDay(for: Date())
                    let examples = [(0, "Français", "FRANCAIS - PROF. EXEMPLE"),
                                    (1, "Anglais", "ANGLAIS - PROF. EXEMPLE - [GROUPE-TEST]"),
                                    (7, "SVT", "SCIENCES VIE & TERRE - PROF. EXEMPLE")]
                    initial.occurrences = examples.compactMap { offset, name, title in
                        guard let subject = initial.subjects.first(where: { $0.name == name }),
                              let day = calendar.date(byAdding: .day, value: offset, to: today),
                              let start = calendar.date(byAdding: .hour, value: 8, to: day) else { return nil }
                        return CourseOccurrence(calendarIdentifier: "test-calendar", eventIdentifier: "test-\(offset)",
                            calendarName: "Calendrier de test", title: title, start: start,
                            end: start.addingTimeInterval(3600), subjectID: subject.id)
                    }
                }
                if ProcessInfo.processInfo.arguments.contains("--uitesting-showcase") {
                    Self.populateShowcase(&initial)
                }
                if ProcessInfo.processInfo.arguments.contains("--uitesting-school") {
                    SchoolUITestFixtures.populate(&initial)
                }
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
        // School refresh never depends on EventKit notifications or permissions.
        SessionCompanionService.shared.synchronizeExistingSession(activeSessionID: state.activeSession?.id)
    }

    #if targetEnvironment(simulator)
    /// Explicit XCTest fixture, never compiled into the iPhone executable.
    private static func populateShowcase(_ state: inout CadenceState) {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        state.settings.calendarEnabled = true
        state.settings.selectedCalendarIDs = ["showcase-calendar"]
        state.settings.lastCalendarSync = now
        let rows = [("Mathématiques", 8, 0, 60), ("Histoire-Géographie", 9, 0, 60),
                    ("Français", 10, 15, 60), ("Physique-Chimie", 14, 0, 120), ("SVT", 16, 15, 60)]
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            for (index, row) in rows.enumerated() {
                guard let subject = state.subjects.first(where: { $0.name == row.0 }),
                      let start = calendar.date(bySettingHour: row.1, minute: row.2, second: 0, of: day) else { continue }
                state.occurrences.append(CourseOccurrence(calendarIdentifier: "showcase-calendar", eventIdentifier: "showcase-\(offset)-\(index)", calendarName: "Emploi du temps", title: row.0.uppercased() + " - GROUPE DE DÉMONSTRATION", start: start, end: start.addingTimeInterval(Double(row.3 * 60)), subjectID: subject.id))
            }
            if day < today, let subject = state.subjects.first {
                let start = day.addingTimeInterval(9 * 3600)
                let duration = Double([120, 155, 95, 180, 135, 75, 160][offset % 7] * 60)
                state.sessions.append(StudySession(subjectID: subject.id, kind: .revision, origin: .manual, topic: "Présentation en simulateur", startedAt: start, endedAt: start.addingTimeInterval(duration), activeSegments: [TimeSegment(start: start, end: start.addingTimeInterval(duration))]))
            }
        }
        if let maths = state.subjects.first, let french = state.subjects.first(where: { $0.name == "Français" }) {
            let courseStart = now.addingTimeInterval(-260 * 60)
            let revisionStart = now.addingTimeInterval(-75 * 60)
            state.sessions.append(StudySession(subjectID: maths.id, kind: .course, origin: .manual, startedAt: courseStart, endedAt: revisionStart, activeSegments: [TimeSegment(start: courseStart, end: revisionStart)]))
            state.sessions.append(StudySession(subjectID: french.id, kind: .revision, origin: .manual, topic: "Lecture", startedAt: revisionStart, endedAt: now, activeSegments: [TimeSegment(start: revisionStart, end: now)]))
        }
    }
    #endif

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
            let previousSessionID = state.activeSession?.id
            state = updated
            errorMessage = nil
            SystemIntegrationService.shared.refresh(state: updated)
            if previousSessionID != updated.activeSession?.id {
                SessionCompanionService.shared.sessionDidChange(activeSessionID: updated.activeSession?.id)
            }
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
    func startHomework(_ id: String) {
        guard let item = state.homework.first(where: { $0.id == id }), let subjectID = item.subjectID else {
            errorMessage = "Choisissez d’abord la matière de ce devoir."; return
        }
        if state.activeSession != nil { assignHomeworkToActiveSession(id); return }
        if performMutation({ state in
            _ = try CadenceEngine.start(state: &state, subjectID: subjectID, kind: .revision,
                topic: item.source.subject, homeworkID: id)
        }) { route = "revision" }
    }
    func assignHomeworkToActiveSession(_ id: String?) {
        performMutation { try CadenceEngine.setActiveHomework(state: &$0, homeworkID: id) }
    }
    func setHomeworkCompletion(_ id: String, isDone: Bool) {
        performMutation { state in
            try CadenceEngine.setHomeworkCompletion(state: &state, homeworkID: id, isDone: isDone)
            if isDone, state.activeSession?.activeHomeworkID == id {
                try CadenceEngine.setActiveHomework(state: &state, homeworkID: nil)
            }
        }
    }
    func setHomeworkSubject(_ id: String, subjectID: UUID) {
        performMutation { try CadenceEngine.assignHomeworkSubject(state: &$0, homeworkID: id, subjectID: subjectID) }
    }
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
            if state.occurrences[index].school != nil,
               state.occurrences[index].start != start || state.occurrences[index].end != end || state.occurrences[index].title != title.trimmingCharacters(in: .whitespacesAndNewlines) {
                state.occurrences[index].schoolScheduleOverridden = true
            }
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
        await refreshSchool(force: false)
        if !writesBlocked {
            performMutation { state in
                CadenceEngine.setAutoCredit(state: &state, enabled: true)
            }
        }
    }

    @discardableResult
    func requestSchoolLogin(email: String) async -> Bool {
        let epoch = schoolEpoch
        schoolError = nil
        do { try await schoolService.requestLogin(email: email); return epoch == schoolEpoch }
        catch { if epoch == schoolEpoch { schoolError = error.localizedDescription }; return false }
    }

    @discardableResult
    func verifySchoolLogin(email: String, codeOrLink: String) async -> Bool {
        invalidateSchoolRequests()
        let epoch = schoolEpoch
        schoolError = nil
        do {
            try await schoolService.verifyLogin(email: email, codeOrLink: codeOrLink)
            guard epoch == schoolEpoch else { return false }
            await refreshSchool(force: true)
            return epoch == schoolEpoch && schoolSignedIn && schoolError == nil
        } catch { if epoch == schoolEpoch { schoolError = error.localizedDescription }; return false }
    }

    func disconnectSchool() async {
        invalidateSchoolRequests()
        let epoch = schoolEpoch
        schoolError = nil
        do { try await schoolService.signOut() }
        catch { if epoch == schoolEpoch { schoolError = error.localizedDescription } }
        let signedIn = await schoolService.hasSession
        let email = await schoolService.email
        guard epoch == schoolEpoch else { return }
        schoolSignedIn = signedIn
        schoolEmail = email
        schoolStatus = signedIn ? "La connexion reste enregistrée · réessayez la déconnexion" : "Déconnecté · données locales conservées"
    }

    private func invalidateSchoolRequests() {
        schoolEpoch = UUID(); schoolOperation = nil; schoolSyncing = false
    }

    func refreshSchool(force: Bool = true) async {
        guard !writesBlocked, !schoolSyncing else { return }
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            schoolSignedIn = state.schoolSync != nil
            schoolStatus = state.schoolSync == nil ? "Suivi manuel" : "Données fictives de recette · hors connexion"
            return
        }
        #endif
        let epoch = schoolEpoch
        let operation = UUID()
        schoolOperation = operation
        schoolSyncing = true
        defer { if schoolOperation == operation { schoolSyncing = false; schoolOperation = nil } }
        let signedIn = await schoolService.hasSession
        let email = await schoolService.email
        guard epoch == schoolEpoch else { return }
        schoolSignedIn = signedIn
        schoolEmail = email
        guard schoolSignedIn else {
            schoolStatus = state.schoolSync == nil ? "Connecter PRONOTE via Supabase" : "Cache scolaire disponible · connexion à rétablir"
            return
        }
        if !force, let lastSchoolAttempt, Date().timeIntervalSince(lastSchoolAttempt) < 300 { return }
        lastSchoolAttempt = Date()
        schoolError = nil
        do {
            let snapshot = try await schoolService.fetchSnapshot()
            guard epoch == schoolEpoch else { return }
            guard performMutation({ state in _ = try SchoolReconciler.sync(state: &state, snapshot: snapshot) }) else {
                schoolError = errorMessage; return
            }
            lastSyncAt = state.schoolSync?.lastSuccessfulFetch
            schoolStatus = snapshot.syncState.hasError ? "Cache actualisé · source PRONOTE à vérifier" : "PRONOTE synchronisé avec Supabase"
        } catch {
            let signedIn = await schoolService.hasSession
            let email = await schoolService.email
            guard epoch == schoolEpoch else { return }
            schoolSignedIn = signedIn
            schoolEmail = email
            schoolError = error.localizedDescription
            schoolStatus = state.schoolSync == nil ? "Connexion scolaire indisponible" : "Hors connexion · dernier emploi du temps conservé"
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
            invalidateSchoolRequests()
            state = restored
            lastSyncAt = restored.settings.lastCalendarSync
            writesBlocked = false
            errorMessage = nil
            calendarPreview = []; previewWindow = nil
            SystemIntegrationService.shared.refresh(state: restored)
            SessionCompanionService.shared.synchronizeExistingSession(activeSessionID: restored.activeSession?.id)
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
