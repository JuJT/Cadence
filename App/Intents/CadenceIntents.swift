import AppIntents
import CadenceCore
import Foundation

enum ShortcutError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor
private enum ShortcutCommands {
    static func subject(named name: String?) throws -> Subject {
        let store = AppStore.shared
        let query = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if query.isEmpty, let id = store.state.settings.defaultSubjectID,
           let value = store.state.subjects.first(where: { $0.id == id && !$0.isArchived }) { return value }
        let candidates = store.state.subjects.filter {
            !$0.isArchived && ($0.name.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
                $0.aliases.contains { $0.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame })
        }
        guard candidates.count == 1, let value = candidates.first else {
            throw ShortcutError.message(query.isEmpty
                ? "Indiquez une matière ou démarrez d’abord une séance dans Cadence pour définir la matière par défaut."
                : "Matière introuvable ou ambiguë. Utilisez son nom complet dans Cadence.")
        }
        return value
    }
    static func check(_ store: AppStore) throws {
        if let error = store.errorMessage { throw ShortcutError.message(error) }
    }
    static func totals() -> StudyTotals {
        let now = Date()
        let interval = Calendar.current.dateInterval(of: .day, for: now)!
        return Statistics.totals(state: AppStore.shared.state, in: interval, now: now)
    }
}

/// Les intents sont compilés exclusivement dans la cible app. Ils ouvrent son processus,
/// où le même dépôt persistant et le même moteur de séances assurent les transitions.
struct StartRevisionIntent: AppIntent {
    static var title: LocalizedStringResource = "Démarrer une révision"
    static var description = IntentDescription("Démarre une révision dans Cadence, avec votre matière par défaut ou celle indiquée.")
    static var openAppWhenRun = true
    @Parameter(title: "Matière") var subjectName: String?
    @Parameter(title: "Chapitre") var topic: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        let subject = try ShortcutCommands.subject(named: subjectName)
        if let active = store.state.activeSession {
            guard active.kind == .revision && active.subjectID == subject.id else {
                throw ShortcutError.message("Une autre séance est en cours. Terminez-la d’abord dans Cadence.")
            }
            store.route = "revision"
            return .result(dialog: "Cette révision est déjà en cours.")
        }
        store.start(kind: .revision, subjectID: subject.id, topic: topic ?? "", origin: .shortcut)
        try ShortcutCommands.check(store)
        store.route = "revision"
        return .result(dialog: "Révision démarrée.")
    }
}

struct AddCourseIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter un cours"
    static var description = IntentDescription("Enregistre un cours déjà terminé. En cas de chevauchement, ouvrez Cadence pour l’associer au calendrier.")
    static var openAppWhenRun = true
    @Parameter(title: "Matière") var subjectName: String?
    @Parameter(title: "Début") var start: Date
    @Parameter(title: "Durée en minutes", default: 60) var minutes: Double
    @Parameter(title: "Chapitre") var topic: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        let subject = try ShortcutCommands.subject(named: subjectName)
        guard minutes.isFinite, minutes > 0, minutes <= 1440 else {
            throw ShortcutError.message("La durée doit être comprise entre 0 et 1 440 minutes.")
        }
        let end = start.addingTimeInterval(minutes * 60)
        guard end <= Date() else { throw ShortcutError.message("Indiquez un cours déjà terminé.") }
        guard store.performMutation({ state in
            _ = try CadenceEngine.addManual(state: &state, subjectID: subject.id, kind: .course,
                start: start, end: end, topic: topic ?? "", origin: .shortcut)
        }) else { throw ShortcutError.message(store.errorMessage ?? "Le cours n’a pas été enregistré.") }
        store.route = "cours"
        return .result(dialog: "Cours enregistré.")
    }
}

struct PauseSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Mettre en pause"
    static var openAppWhenRun = true
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        guard let active = store.state.activeSession else { return .result(dialog: "Aucune séance en cours.") }
        if active.isPaused { return .result(dialog: "La séance est déjà en pause.") }
        store.pause(); try ShortcutCommands.check(store)
        return .result(dialog: "Séance en pause.")
    }
}

struct ResumeSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Reprendre la séance"
    static var openAppWhenRun = true
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        guard let active = store.state.activeSession else { return .result(dialog: "Aucune séance à reprendre.") }
        if !active.isPaused { return .result(dialog: "La séance est déjà en cours.") }
        store.resume(); try ShortcutCommands.check(store)
        return .result(dialog: "Séance reprise.")
    }
}

struct FinishSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Terminer la séance"
    static var openAppWhenRun = true
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        guard store.state.activeSession != nil else { return .result(dialog: "Aucune séance à terminer.") }
        store.finish(); try ShortcutCommands.check(store)
        return .result(dialog: "Séance terminée et enregistrée.")
    }
}

struct CourseTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Temps de cours aujourd’hui"
    static var openAppWhenRun = true
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let value = ShortcutCommands.totals()
        let dialog = IntentDialog(stringLiteral: "Cours confirmés ou mesurés : \(CompactDuration.text(value.courseMeasured)). Cours estimés : \(CompactDuration.text(value.courseEstimated)).")
        return .result(value: value.courseMeasured + value.courseEstimated, dialog: dialog)
    }
}

struct RevisionTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Temps de révisions aujourd’hui"
    static var openAppWhenRun = true
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let seconds = ShortcutCommands.totals().revisions
        return .result(value: seconds, dialog: IntentDialog(stringLiteral: "Révisions : \(CompactDuration.text(seconds))."))
    }
}

struct TotalTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Temps total aujourd’hui"
    static var openAppWhenRun = true
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let value = ShortcutCommands.totals()
        return .result(value: value.total, dialog: IntentDialog(stringLiteral:
            "Total : \(CompactDuration.text(value.total)), dont \(CompactDuration.text(value.courseEstimated)) de cours estimés."))
    }
}

struct OpenTimetableIntent: AppIntent {
    static var title: LocalizedStringResource = "Ouvrir mon emploi du temps"
    static var openAppWhenRun = true
    @MainActor
    func perform() async throws -> some IntentResult {
        AppStore.shared.route = "cours"
        return .result()
    }
}

struct CalendarCourseEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Cours du calendrier")
    static var defaultQuery = CalendarCourseQuery()
    let id: UUID
    let title: String
    let schedule: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(schedule)")
    }
}

struct CalendarCourseQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CalendarCourseEntity] {
        await MainActor.run {
            AppStore.shared.state.occurrences.filter { identifiers.contains($0.id) }.map {
                CalendarCourseEntity(id: $0.id, title: $0.title,
                    schedule: $0.start.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }
    func suggestedEntities() async throws -> [CalendarCourseEntity] {
        await MainActor.run {
            AppStore.shared.state.occurrences.filter {
                $0.end <= Date() && $0.subjectID != nil && $0.linkedSessionID == nil &&
                ![CourseStatus.absent, .cancelled, .ignored].contains($0.status)
            }.sorted { $0.start > $1.start }.prefix(30).map {
                CalendarCourseEntity(id: $0.id, title: $0.title,
                    schedule: $0.start.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }
}

struct ConfirmCalendarCourseIntent: AppIntent {
    static var title: LocalizedStringResource = "Confirmer un cours du calendrier"
    static var openAppWhenRun = true
    @Parameter(title: "Cours") var course: CalendarCourseEntity
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        guard let occurrence = store.state.occurrences.first(where: { $0.id == course.id }), occurrence.end <= Date() else {
            throw ShortcutError.message("Ce cours est introuvable ou n’est pas encore terminé.")
        }
        store.confirmOccurrence(course.id)
        try ShortcutCommands.check(store)
        return .result(dialog: "Cours confirmé.")
    }
}

struct CadenceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRevisionIntent(), phrases: ["Démarrer une révision dans \(.applicationName)"], shortTitle: "Réviser", systemImageName: "pencil.line")
        AppShortcut(intent: AddCourseIntent(), phrases: ["Ajouter un cours dans \(.applicationName)"], shortTitle: "Ajouter un cours", systemImageName: "book.closed")
        AppShortcut(intent: PauseSessionIntent(), phrases: ["Mettre \(.applicationName) en pause"], shortTitle: "Mettre en pause", systemImageName: "pause.fill")
        AppShortcut(intent: ResumeSessionIntent(), phrases: ["Reprendre ma séance dans \(.applicationName)"], shortTitle: "Reprendre", systemImageName: "play.fill")
        AppShortcut(intent: FinishSessionIntent(), phrases: ["Terminer ma séance dans \(.applicationName)"], shortTitle: "Terminer", systemImageName: "stop.fill")
        AppShortcut(intent: CourseTimeIntent(), phrases: ["Temps de cours dans \(.applicationName)"], shortTitle: "Temps de cours", systemImageName: "book")
        AppShortcut(intent: RevisionTimeIntent(), phrases: ["Temps de révisions dans \(.applicationName)"], shortTitle: "Temps de révisions", systemImageName: "pencil")
        AppShortcut(intent: TotalTimeIntent(), phrases: ["Temps total dans \(.applicationName)"], shortTitle: "Temps total", systemImageName: "chart.bar")
        AppShortcut(intent: OpenTimetableIntent(), phrases: ["Ouvrir l’emploi du temps dans \(.applicationName)"], shortTitle: "Emploi du temps", systemImageName: "calendar")
        AppShortcut(intent: ConfirmCalendarCourseIntent(), phrases: ["Confirmer un cours dans \(.applicationName)"], shortTitle: "Confirmer un cours", systemImageName: "checkmark.circle")
    }
}
