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
    @Published private(set) var pronoteProfile: PronoteProfile?
    @Published private(set) var pronoteChallenge: PronoteSecurityChallenge?
    @Published private(set) var pronotePortal = PronotePortalCache() {
        didSet { SystemIntegrationService.shared.updateGrade(from: pronotePortal) }
    }
    @Published private(set) var pronotePortalLoading: Set<String> = []
    @Published private(set) var pronotePortalErrors: [String: String] = [:]

    private let calendarService = CalendarIntegrationService()
    private let schoolService = PronoteSchoolService()
    private let portalRepository = PronotePortalRepository()
    private var lastSchoolAttempt: Date?
    private var schoolEpoch = UUID()
    private var schoolOperation: UUID?
    private var stateRevision: UInt64 = 0
    private var schoolCacheRepaired = false
    private var portalLoaded = false
    private var portalLoadTask: Task<PronotePortalCache?, Never>?
    private var portalWriteTail: Task<Bool, Never>?
    private var portalWriteOperation: UUID?
    private var portalOperations: [String: UUID] = [:]
    private var remoteWriteOperations: Set<String> = []
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
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--uitesting"),
           ProcessInfo.processInfo.arguments.contains("--uitesting-school") {
            pronotePortal = PronoteUITestFixtures.cache()
            pronoteProfile = pronotePortal.profile
            portalLoaded = true
            schoolSignedIn = true
            schoolStatus = "Données fictives de recette · hors connexion"
        }
        #endif
        calendarPermissionDescription = calendarService.permissionDescription
        calendarSources = calendarService.sources()
        lastSyncAt = state.settings.lastCalendarSync
        SystemIntegrationService.shared.onDiagnosticChange = { [weak self] in self?.updateDiagnostics() }
        updateDiagnostics()
        if !writesBlocked { SystemIntegrationService.shared.refresh(state: state) }
        // School refresh never depends on EventKit notifications or permissions.
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
            guard updated != state else { return true }
            try BackupCodec.validate(updated)
            try repository.save(updated)
            state = updated
            stateRevision &+= 1
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
        await loadInitialPortal()
        guard await repairSchoolCache(epoch: schoolEpoch) else { return }
        await refreshSchool(force: false)
    }

    func refreshScheduleInBackground() async {
        let alerts = TimetableNotificationService.shared
        guard alerts.enabled, !Task.isCancelled else { return }
        alerts.scheduleNextRefresh()
        await refreshSchool(force: true)
    }

    private var isUITestSession: Bool {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--uitesting")
        #else
        return false
        #endif
    }

    func findPronoteSchools(latitude: Double, longitude: Double) async throws -> [PronoteSchool] {
        guard !isUITestSession else { return [] }
        let epoch = schoolEpoch
        let schools = try await schoolService.discover(latitude: latitude, longitude: longitude)
        guard epoch == schoolEpoch, !Task.isCancelled else { throw CancellationError() }
        return schools
    }

    @discardableResult
    func connectPronote(url: String, username: String, password: String, kind: Int = 6) async -> Bool {
        guard !isUITestSession, !schoolSyncing else { return false }
        await loadInitialPortal()
        guard !schoolSyncing else { return false }
        invalidateSchoolRequests()
        let epoch = schoolEpoch, operation = UUID()
        schoolOperation = operation; schoolSyncing = true
        schoolError = nil; pronoteChallenge = nil; schoolSignedIn = false
        defer { finishSchoolOperation(operation) }
        do {
            let profile = try await schoolService.connect(url: url, username: username, password: password, kind: kind)
            guard epoch == schoolEpoch else { return false }
            await installProfile(profile, epoch: epoch)
            guard epoch == schoolEpoch else { return false }
            finishSchoolOperation(operation)
            await refreshSchool(force: true)
            return epoch == schoolEpoch && schoolSignedIn
        } catch {
            handleSchoolError(error, epoch: epoch)
            return false
        }
    }

    @discardableResult
    func completePronoteSecurity(pin: String, password: String, source: String, mode: Int?) async -> Bool {
        guard !isUITestSession, !schoolSyncing, pronoteChallenge != nil else { return false }
        let epoch = schoolEpoch, operation = UUID()
        schoolOperation = operation; schoolSyncing = true; schoolError = nil
        defer { finishSchoolOperation(operation) }
        do {
            let profile = try await schoolService.completeSecurity(pin: pin, password: password, source: source, mode: mode)
            guard epoch == schoolEpoch else { return false }
            await installProfile(profile, epoch: epoch)
            guard epoch == schoolEpoch else { return false }
            finishSchoolOperation(operation)
            await refreshSchool(force: true)
            return epoch == schoolEpoch && schoolSignedIn
        } catch {
            handleSchoolError(error, epoch: epoch)
            return false
        }
    }

    @discardableResult
    func selectPronoteResource(_ id: String) async -> Bool {
        guard !isUITestSession, !schoolSyncing, !id.isEmpty else { return false }
        invalidateSchoolRequests()
        let epoch = schoolEpoch, operation = UUID()
        schoolOperation = operation; schoolSyncing = true; schoolError = nil
        defer { finishSchoolOperation(operation) }
        do {
            let profile = try await schoolService.selectResource(id)
            guard epoch == schoolEpoch else { return false }
            await installProfile(profile, epoch: epoch)
            guard epoch == schoolEpoch else { return false }
            finishSchoolOperation(operation)
            await refreshSchool(force: true)
            return epoch == schoolEpoch && schoolSignedIn
        } catch {
            handleSchoolError(error, epoch: epoch)
            return false
        }
    }

    func disconnectSchool() async {
        guard !isUITestSession else { return }
        invalidateSchoolRequests()
        let epoch = schoolEpoch, operation = UUID()
        schoolOperation = operation; schoolSyncing = true
        pronoteChallenge = nil; schoolError = nil
        defer { finishSchoolOperation(operation) }
        do { try await schoolService.signOut() }
        catch { if epoch == schoolEpoch { schoolError = error.localizedDescription } }
        let signedIn = await schoolService.hasSession
        let email = await schoolService.email
        guard epoch == schoolEpoch else { return }
        schoolSignedIn = signedIn
        schoolEmail = email
        if !signedIn { pronoteProfile = nil }
        schoolStatus = signedIn ? "La connexion reste enregistrée · réessayez la déconnexion" : "Déconnecté · données locales conservées"
    }

    private func invalidateSchoolRequests() {
        TimetableNotificationService.shared.resetHistory()
        schoolEpoch = UUID(); schoolOperation = nil; schoolSyncing = false
        lastSchoolAttempt = nil
        portalOperations = [:]; remoteWriteOperations = []
        pronotePortalLoading = []; pronotePortalErrors = [:]
    }

    private func finishSchoolOperation(_ operation: UUID) {
        if schoolOperation == operation { schoolSyncing = false; schoolOperation = nil }
    }

    private func handleSchoolError(_ error: Error, epoch: UUID) {
        guard epoch == schoolEpoch, !(error is CancellationError) else { return }
        if case PronoteServiceError.security(let challenge) = error {
            pronoteChallenge = challenge
            schoolSignedIn = false
            schoolStatus = "Vérification de sécurité PRONOTE requise"
        } else {
            schoolError = error.localizedDescription
            schoolStatus = state.schoolSync == nil ? "Connexion PRONOTE indisponible" : "Hors connexion · dernier emploi du temps conservé"
        }
    }

    /// Load once before a remote operation. A late disk read cannot replace a newly connected account.
    private func loadInitialPortal() async {
        guard !portalLoaded else { return }
        if isUITestSession { portalLoaded = true; return }
        let epoch = schoolEpoch
        if portalLoadTask == nil {
            let repository = portalRepository
            portalLoadTask = Task { try? await repository.load() }
        }
        let cached = await portalLoadTask?.value
        guard !portalLoaded else { return }
        portalLoaded = true; portalLoadTask = nil
        guard epoch == schoolEpoch, let cached else { return }
        pronotePortal = cached
        pronoteProfile = cached.profile
    }

    /// Keep cache writes ordered across section loads and account changes.
    @discardableResult
    private func updatePortal(epoch: UUID, _ mutation: @escaping (inout PronotePortalCache) -> Void) async -> Bool {
        let previous = portalWriteTail, operation = UUID()
        let task = Task { @MainActor [weak self] () -> Bool in
            _ = await previous?.value
            guard let self, epoch == self.schoolEpoch else { return false }
            var updated = self.pronotePortal
            mutation(&updated)
            if updated == self.pronotePortal { return true }
            do { try await self.portalRepository.save(updated) }
            catch {
                guard epoch == self.schoolEpoch else { return false }
                self.pronotePortalErrors["cache"] = "Le cache scolaire n’a pas pu être enregistré. Les données de cette session restent consultables."
            }
            guard epoch == self.schoolEpoch else { return false }
            self.pronotePortal = updated
            return true
        }
        portalWriteTail = task; portalWriteOperation = operation
        let result = await task.value
        if portalWriteOperation == operation { portalWriteTail = nil; portalWriteOperation = nil }
        return result
    }

    private func installProfile(_ profile: PronoteProfile, epoch: UUID) async {
        guard epoch == schoolEpoch else { return }
        _ = await updatePortal(epoch: epoch) { cache in
            if let old = cache.profile,
               old.resourceID != profile.resourceID || old.establishment != profile.establishment || old.displayName != profile.displayName {
                cache = PronotePortalCache()
            } else if cache.profile == nil && !cache.sections.isEmpty {
                cache = PronotePortalCache()
            }
            cache.profile = profile
        }
        guard epoch == schoolEpoch else { return }
        pronoteProfile = profile; pronoteChallenge = nil
        schoolSignedIn = true; schoolEmail = profile.displayName
        schoolStatus = "Compte PRONOTE connecté"
    }

    /// Reconcile a value off MainActor, then rebase if a timer action changed the live state meanwhile.
    private func reconcileSchool(snapshot: SchoolSnapshot?, epoch: UUID) async -> Bool {
        guard !writesBlocked else { return false }
        do {
            for _ in 0..<4 {
                guard epoch == schoolEpoch, !Task.isCancelled else { return false }
                let base = state, revision = stateRevision
                let updated = try await Task.detached(priority: .userInitiated) {
                    var result = base
                    if let snapshot { _ = try SchoolReconciler.sync(state: &result, snapshot: snapshot) }
                    else { _ = try SchoolReconciler.repairCachedOccurrences(state: &result) }
                    CadenceEngine.setAutoCredit(state: &result, enabled: true)
                    return result
                }.value
                guard epoch == schoolEpoch, !Task.isCancelled else { return false }
                guard revision == stateRevision else { continue }
                return performMutation { $0 = updated }
            }
            return false
        } catch {
            if epoch == schoolEpoch { schoolError = error.localizedDescription }
            return false
        }
    }

    private func repairSchoolCache(epoch: UUID) async -> Bool {
        guard !schoolCacheRepaired else { return true }
        let success = await reconcileSchool(snapshot: nil, epoch: epoch)
        if success, epoch == schoolEpoch { schoolCacheRepaired = true }
        return success
    }

    func refreshSchool(force: Bool = true) async {
        guard !writesBlocked, !schoolSyncing else { return }
        await loadInitialPortal()
        let epoch = schoolEpoch
        guard await repairSchoolCache(epoch: epoch), epoch == schoolEpoch, !schoolSyncing else { return }
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            schoolSignedIn = pronoteProfile != nil || state.schoolSync != nil
            schoolStatus = state.schoolSync == nil ? "Suivi manuel" : "Données fictives de recette · hors connexion"
            return
        }
        #endif
        let operation = UUID()
        schoolOperation = operation
        schoolSyncing = true
        defer { finishSchoolOperation(operation) }
        let signedIn = await schoolService.hasSession
        let email = await schoolService.email
        guard epoch == schoolEpoch else { return }
        schoolSignedIn = signedIn
        schoolEmail = email
        guard schoolSignedIn else {
            schoolStatus = pronoteChallenge == nil
                ? (state.schoolSync == nil ? "Connecter mon compte PRONOTE" : "Cache scolaire disponible · connexion PRONOTE à rétablir")
                : "Vérification de sécurité PRONOTE requise"
            return
        }
        if !force, let lastSchoolAttempt, Date().timeIntervalSince(lastSchoolAttempt) < 300 { return }
        lastSchoolAttempt = Date()
        schoolError = nil
        do {
            let snapshot = try await schoolService.fetchSnapshot()
            guard epoch == schoolEpoch else { return }
            let profile = await schoolService.currentProfile
            if let profile { await installProfile(profile, epoch: epoch) }
            guard epoch == schoolEpoch else { return }
            let applied = await reconcileSchool(snapshot: snapshot, epoch: epoch)
            guard epoch == schoolEpoch else { return }
            guard applied else {
                schoolError = errorMessage ?? schoolError ?? "L’emploi du temps sera actualisé au prochain rafraîchissement. Vos données sont conservées."
                return
            }
            lastSyncAt = state.schoolSync?.lastSuccessfulFetch
            schoolStatus = snapshot.syncState.hasError ? "Cache actualisé · source PRONOTE à vérifier" : "PRONOTE synchronisé directement"
            if let profile, !Task.isCancelled {
                await TimetableNotificationService.shared.observe(snapshot, occurrences: state.occurrences, profile: profile)
                guard epoch == schoolEpoch, !Task.isCancelled, profile.capabilities.contains("grades") else { return }
                let period = profile.currentPeriodID(for: "grades")
                let key = period.map { "grades:" + $0 } ?? "grades"
                let age = Date().timeIntervalSince(pronotePortal.updatedAt[key] ?? .distantPast)
                if age > 900, await SystemIntegrationService.shared.hasGradeWidget(), epoch == schoolEpoch, !Task.isCancelled {
                    await loadPronoteSection("grades", periodID: period)
                }
            }
        } catch {
            let signedIn = await schoolService.hasSession
            let email = await schoolService.email
            guard epoch == schoolEpoch else { return }
            schoolSignedIn = signedIn
            schoolEmail = email
            handleSchoolError(error, epoch: epoch)
        }
    }

    func loadPronoteSection(_ section: String, periodID: String? = nil) async {
        let allowed = Set(["grades", "evaluations", "attendance", "news", "discussions", "menus", "contents", "account", "gradebook", "homepage"])
        guard allowed.contains(section), (periodID?.utf8.count ?? 0) <= 256 else { return }
        await loadInitialPortal()
        guard !isUITestSession else { return }
        if let profile = pronoteProfile, !profile.capabilities.contains(section) { return }
        let key = section + (periodID.map { ":" + $0 } ?? "")
        await loadPortalValue(key: key) { try await self.schoolService.fetchSection(section, periodID: periodID) }
    }

    func loadPronoteThread(_ id: String) async {
        guard !id.isEmpty, id.utf8.count <= 512, !isUITestSession else { return }
        await loadInitialPortal()
        await loadPortalValue(key: "discussion:" + id) { try await self.schoolService.fetchThread(id) }
    }

    func loadPronoteNews(_ id: String) async {
        guard !id.isEmpty, id.utf8.count <= 512, !isUITestSession else { return }
        await loadInitialPortal()
        await loadPortalValue(key: "news:" + id) {
            let value = try await self.schoolService.fetchNewsDetail(id)
            guard value["id"]?.stringValue == id, value["detailsRequired"]?.boolValue == false,
                  ["information", "survey"].contains(value["is"]?.stringValue ?? "") else {
                throw PronoteServiceError.failure("UnsupportedNewsFormat")
            }
            return value
        }
    }

    func loadPronoteRecipients() async {
        await loadInitialPortal()
        guard !isUITestSession, pronoteProfile?.capabilities.contains("compose") == true else { return }
        await loadPortalValue(key: "recipients") { try await self.schoolService.fetchRecipients() }
    }

    func loadPronoteResource(_ id: String) async {
        guard !id.isEmpty, id.utf8.count <= 512, !isUITestSession else { return }
        await loadInitialPortal()
        let epoch = schoolEpoch
        await loadPortalValue(key: "resource:" + id) {
            let (resource, contents) = try await self.schoolService.fetchResource(id)
            guard epoch == self.schoolEpoch else { throw CancellationError() }
            if !contents.isEmpty {
                self.performMutation { state in
                    for content in contents {
                        if let index = state.courseContents.firstIndex(where: { $0.id == content.id }) { state.courseContents[index] = content }
                        else { state.courseContents.append(content) }
                    }
                }
            }
            return resource
        }
    }

    private func loadPortalValue(key: String, fetch: () async throws -> SchoolJSON) async {
        guard portalOperations[key] == nil else { return }
        let epoch = schoolEpoch, operation = UUID()
        portalOperations[key] = operation
        pronotePortalLoading.insert(key); pronotePortalErrors[key] = nil
        defer {
            if portalOperations[key] == operation {
                portalOperations[key] = nil; pronotePortalLoading.remove(key)
            }
        }
        do {
            let value = try await fetch()
            guard epoch == schoolEpoch, portalOperations[key] == operation, !Task.isCancelled else { return }
            let profile = await schoolService.currentProfile
            if let profile { await installProfile(profile, epoch: epoch) }
            guard epoch == schoolEpoch, portalOperations[key] == operation, !Task.isCancelled else { return }
            _ = await updatePortal(epoch: epoch) { cache in
                guard self.portalOperations[key] == operation else { return }
                cache.sections[key] = value; cache.updatedAt[key] = Date()
                if key.hasPrefix("news:"), let id = value["id"]?.stringValue, let list = cache.sections["news"] {
                    cache.sections["news"] = Self.replacingNewsItem(in: list, id: id, with: value)
                }
            }
        } catch {
            guard epoch == schoolEpoch, portalOperations[key] == operation, !(error is CancellationError) else { return }
            pronotePortalErrors[key] = error.localizedDescription
            if case PronoteServiceError.security = error { handleSchoolError(error, epoch: epoch) }
        }
    }

    private static func replacingNewsItem(in list: SchoolJSON, id: String, with replacement: SchoolJSON) -> SchoolJSON {
        if var items = list.arrayValues {
            for index in items.indices where items[index]["id"]?.stringValue == id { items[index] = replacement }
            return .array(items)
        }
        guard var object = list.objectValues else { return list }
        for key in ["items", "news"] {
            guard let items = object[key], items.arrayValues != nil else { continue }
            object[key] = replacingNewsItem(in: items, id: id, with: replacement)
        }
        return .object(object)
    }

    @discardableResult
    func composePronoteMessage(recipientIDs: [String], subject: String, text: String) async -> Bool {
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = Array(Set(recipientIDs)).sorted(), epoch = schoolEpoch
        guard !isUITestSession, pronoteProfile?.capabilities.contains("compose") == true,
              !ids.isEmpty, ids.count <= 20, ids.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }),
              !subject.isEmpty, subject.utf16.count <= 200, !text.isEmpty, text.utf16.count <= 20_000,
              !remoteWriteOperations.contains("compose") else { return false }
        let cached = pronotePortal.sections["recipients"]
        let recipients = cached?.arrayValues ?? cached?["recipients"]?.arrayValues ?? []
        let available = Set(recipients.filter { $0["kind"]?.integerValue == 3 }.compactMap { $0["id"]?.stringValue })
        guard Set(ids).isSubset(of: available) else {
            pronotePortalErrors["compose"] = "Actualisez les destinataires puis choisissez à nouveau les enseignants."
            return false
        }
        remoteWriteOperations.insert("compose"); pronotePortalErrors["compose"] = nil
        defer { if epoch == schoolEpoch { remoteWriteOperations.remove("compose") } }
        do {
            try await schoolService.compose(recipientIDs: ids, subject: subject, text: text)
            guard epoch == schoolEpoch else { return false }
            portalOperations["discussions"] = nil
            pronotePortalLoading.remove("discussions")
            await loadPronoteSection("discussions")
            return epoch == schoolEpoch
        } catch {
            guard epoch == schoolEpoch else { return false }
            pronotePortalErrors["compose"] = error.localizedDescription
            if case PronoteServiceError.security = error { handleSchoolError(error, epoch: epoch) }
            return false
        }
    }

    @discardableResult
    func replyPronoteThread(_ id: String, text: String) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "reply:" + id, epoch = schoolEpoch
        guard !isUITestSession, !id.isEmpty, id.utf8.count <= 512, !text.isEmpty,
              text.utf8.count <= 100_000, !remoteWriteOperations.contains(key) else { return false }
        remoteWriteOperations.insert(key)
        defer { if epoch == schoolEpoch { remoteWriteOperations.remove(key) } }
        do {
            try await schoolService.reply(id, text: text)
            guard epoch == schoolEpoch else { return false }
            // A read started before sending must not suppress the post-send refresh.
            portalOperations["discussion:" + id] = nil
            pronotePortalLoading.remove("discussion:" + id)
            await loadPronoteThread(id)
            return epoch == schoolEpoch
        } catch {
            if epoch == schoolEpoch { pronotePortalErrors["discussion:" + id] = error.localizedDescription }
            return false
        }
    }

    @discardableResult
    func acknowledgePronoteNews(_ id: String) async -> Bool {
        let key = "acknowledge:" + id, epoch = schoolEpoch
        guard !isUITestSession, !id.isEmpty, id.utf8.count <= 512,
              !remoteWriteOperations.contains(key) else { return false }
        remoteWriteOperations.insert(key)
        defer { if epoch == schoolEpoch { remoteWriteOperations.remove(key) } }
        do {
            try await schoolService.acknowledge(id)
            guard epoch == schoolEpoch else { return false }
            // This flag follows the successful explicit RPC, never an article opening.
            _ = await updatePortal(epoch: epoch) { cache in
                if var detail = cache.sections["news:" + id]?.objectValues {
                    detail["acknowledged"] = .bool(true)
                    let updated = SchoolJSON.object(detail)
                    cache.sections["news:" + id] = updated
                    if let list = cache.sections["news"] { cache.sections["news"] = Self.replacingNewsItem(in: list, id: id, with: updated) }
                }
            }
            guard epoch == schoolEpoch else { return false }
            await loadPronoteNews(id)
            guard epoch == schoolEpoch else { return false }
            portalOperations["news"] = nil
            pronotePortalLoading.remove("news")
            await loadPronoteSection("news")
            return epoch == schoolEpoch
        } catch {
            if epoch == schoolEpoch { pronotePortalErrors["news"] = error.localizedDescription }
            return false
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
            stateRevision &+= 1
            schoolCacheRepaired = false
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
