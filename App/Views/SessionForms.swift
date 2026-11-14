import SwiftUI
import CadenceCore

struct NewSessionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: SessionKind
    @State private var timer: Bool
    @State private var subjectID: UUID?
    @State private var topic = ""
    @State private var notes = ""
    @State private var start = Date().addingTimeInterval(-1800)
    @State private var minutes = 30.0
    @State private var occurrenceID: UUID?
    @State private var confirmOverlap = false
    init(kind: SessionKind, startAsTimer: Bool = true) { _kind = State(initialValue: kind); _timer = State(initialValue: startAsTimer) }
    private var matchingOccurrences: [CourseOccurrence] {
        guard kind == .course, let subjectID else { return [] }
        return store.state.occurrences.filter {
            $0.subjectID == subjectID && $0.linkedSessionID == nil && $0.status != .absent && $0.status != .cancelled && $0.status != .ignored &&
            abs($0.start.timeIntervalSince(timer ? .now : start)) < 86400
        }.sorted { $0.start < $1.start }
    }
    private var overlapping: Bool {
        let began = timer ? Date() : start
        let end = timer ? began.addingTimeInterval(1) : start.addingTimeInterval(minutes * 60)
        guard kind == .course, occurrenceID == nil else { return false }
        return store.state.occurrences.contains {
            $0.subjectID == subjectID && $0.start < end && $0.end > began && $0.status != .absent && $0.status != .ignored && $0.status != .cancelled
        } || store.state.sessions.contains {
            $0.kind == .course && $0.subjectID == subjectID && $0.startedAt < end && ($0.endedAt ?? end) > began
        }
    }
    var body: some View {
        Form {
            Section("Séance") {
                Picker("Type", selection: $kind) { Text("Cours").tag(SessionKind.course); Text("Révision").tag(SessionKind.revision) }.pickerStyle(.segmented)
                SubjectPicker(selection: $subjectID)
                TextField("Chapitre ou sujet (facultatif)", text: $topic)
                Picker("Saisie", selection: $timer) { Text("Chronométrer").tag(true); Text("Durée passée").tag(false) }.pickerStyle(.segmented)
            }
            if !timer {
                Section("Durée réalisée") {
                    DatePicker("Début", selection: $start, in: ...Date())
                    HStack { Text("Durée en minutes"); Spacer(); TextField("Minutes", value: $minutes, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100) }
                    Stepper("\(minutes.formatted(.number.precision(.fractionLength(0)))) minutes", value: $minutes, in: 1...1440, step: 5)
                }
            }
            if kind == .course && !matchingOccurrences.isEmpty {
                Section {
                    Picker("Associer au calendrier", selection: $occurrenceID) {
                        Text("Cours supplémentaire distinct").tag(nil as UUID?)
                        ForEach(matchingOccurrences) { occurrence in
                            Text(occurrence.title + " · " + occurrence.start.cadenceFormatted(date: .abbreviated, time: .shortened)).tag(Optional(occurrence.id))
                        }
                    }
                } header: { Text("Éviter un double comptage") } footer: {
                    Text("Si cette séance correspond à un cours de votre emploi du temps, associez-les. La durée réelle remplacera l’estimation.")
                }
            }
            if !timer { Section("Notes (facultatif)") { TextEditor(text: $notes).frame(minHeight: 100).accessibilityLabel("Notes de séance") } }
            if timer && store.state.activeSession != nil { Section { Label("Une séance est déjà active. Terminez-la avant d’en démarrer une nouvelle.", systemImage: "exclamationmark.circle").foregroundStyle(.orange) } }
        }
        .navigationTitle(kind == .course ? "Nouveau cours" : "Nouvelle révision").navigationBarTitleDisplayMode(.inline)
        .onAppear { subjectID = store.state.settings.defaultSubjectID ?? store.state.subjects.first(where: { !$0.isArchived })?.id }
        .onChange(of: kind) { _, _ in occurrenceID = nil }
        .onChange(of: subjectID) { _, _ in occurrenceID = nil }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button(timer ? "Démarrer" : "Ajouter") { if overlapping { confirmOverlap = true } else { save(allowOverlap: false) } }.disabled(subjectID == nil || (!timer && (!minutes.isFinite || minutes <= 0 || minutes > 1440 || start.addingTimeInterval(minutes * 60) > .now)) || (timer && store.state.activeSession != nil)) }
        }
        .confirmationDialog("Ce cours chevauche un cours du calendrier. Enregistrer une séance supplémentaire distincte ?", isPresented: $confirmOverlap, titleVisibility: .visible) {
            Button("Oui, ajouter un cours distinct") { save(allowOverlap: true) }
            Button("Revenir pour associer les séances", role: .cancel) { }
        }
    }
    private func save(allowOverlap: Bool) {
        guard let subjectID else { return }
        if timer {
            store.start(kind: kind, subjectID: subjectID, topic: topic, occurrenceID: occurrenceID)
            if store.errorMessage == nil { store.route = "revision"; dismiss() }
        } else {
            let end = start.addingTimeInterval(minutes * 60)
            let session = StudySession(subjectID: subjectID, kind: kind, origin: .manual, topic: topic, notes: notes, startedAt: start, endedAt: end, activeSegments: [TimeSegment(start: start, end: end)], linkedOccurrenceID: occurrenceID)
            store.saveSession(session, allowOverlap: allowOverlap || occurrenceID != nil)
            if store.errorMessage == nil { dismiss() }
        }
    }
}

struct SessionEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let session: StudySession
    @State private var subjectID: UUID?
    @State private var kind: SessionKind
    @State private var topic: String
    @State private var notes: String
    @State private var start: Date
    @State private var minutes: Double
    @State private var deleteConfirmation = false
    @State private var overlapConfirmation = false
    init(session: StudySession) {
        self.session = session
        _subjectID = State(initialValue: session.subjectID); _kind = State(initialValue: session.kind)
        _topic = State(initialValue: session.topic); _notes = State(initialValue: session.notes)
        _start = State(initialValue: session.startedAt); _minutes = State(initialValue: session.elapsed(at: .now) / 60)
    }
    private var isActive: Bool { session.endedAt == nil }
    private var timeChanged: Bool { !isActive && (start != session.startedAt || abs(minutes * 60 - session.elapsed(at: session.endedAt ?? .now)) > 0.5) }
    private var hasNewOverlap: Bool {
        guard kind == .course, session.linkedOccurrenceID == nil,
              timeChanged || subjectID != session.subjectID || kind != session.kind else { return false }
        let end = isActive ? Date() : start.addingTimeInterval(minutes * 60)
        return store.state.occurrences.contains {
            $0.subjectID == subjectID && $0.start < end && $0.end > start && ![.absent, .ignored, .cancelled].contains($0.status)
        } || store.state.sessions.contains {
            $0.id != session.id && $0.kind == .course && $0.subjectID == subjectID && $0.startedAt < end && ($0.endedAt ?? end) > start
        }
    }
    var body: some View {
        Form {
            Section("Séance") {
                SubjectPicker(selection: $subjectID)
                Picker("Type", selection: $kind) { Text("Cours").tag(SessionKind.course); Text("Révision").tag(SessionKind.revision) }.disabled(isActive || session.linkedOccurrenceID != nil)
                TextField("Chapitre ou sujet", text: $topic)
                DatePicker("Début", selection: $start, in: ...Date()).disabled(isActive)
                if !isActive {
                    HStack { Text("Durée en minutes"); Spacer(); TextField("Minutes", value: $minutes, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100) }
                    if timeChanged { Text("La durée corrigée sera répartie à partir de l’heure de début.").font(.footnote).foregroundStyle(.secondary) }
                } else { Text("Terminez la séance pour corriger sa durée.").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Notes") { TextEditor(text: $notes).frame(minHeight: 140).accessibilityLabel("Notes de séance") }
            Section { LabeledContent("Provenance", value: session.origin.label); if session.linkedOccurrenceID != nil { Label("Associée à un cours du calendrier", systemImage: "link") } }
            if !isActive { Section { Button("Supprimer la séance", role: .destructive) { deleteConfirmation = true } } }
        }
        .navigationTitle("Modifier la séance").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { if hasNewOverlap { overlapConfirmation = true } else { save(allowOverlap: false) } }.disabled(subjectID == nil || (!isActive && (!minutes.isFinite || minutes < 0 || minutes > 1440 || start.addingTimeInterval(minutes * 60) > .now))) } }
        .confirmationDialog("Supprimer définitivement cette séance ?", isPresented: $deleteConfirmation, titleVisibility: .visible) {
            Button("Supprimer la séance", role: .destructive) { store.deleteSession(session.id); if store.errorMessage == nil { dismiss() } }
            Button("Conserver", role: .cancel) { }
        }
        .confirmationDialog("Confirmer une séance distincte malgré le chevauchement ?", isPresented: $overlapConfirmation, titleVisibility: .visible) {
            Button("Enregistrer séparément") { save(allowOverlap: true) }
            Button("Revenir", role: .cancel) { }
        }
    }
    private func save(allowOverlap: Bool) {
        guard let subjectID else { return }
        var edited = session
        edited.subjectID = subjectID; edited.kind = kind; edited.topic = topic; edited.notes = notes
        if !isActive && timeChanged {
            edited.startedAt = start; edited.endedAt = start.addingTimeInterval(minutes * 60)
            edited.activeSegments = [TimeSegment(start: start, end: edited.endedAt)]
        }
        store.saveSession(edited, allowOverlap: allowOverlap)
        if store.errorMessage == nil { dismiss() }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var kind: SessionKind?
    @State private var search = ""
    init(initialKind: SessionKind? = nil) { _kind = State(initialValue: initialKind) }
    private var sessions: [StudySession] {
        store.state.sessions.filter {
            (kind == nil || $0.kind == kind) && (search.isEmpty || $0.topic.localizedStandardContains(search) || $0.notes.localizedStandardContains(search) || (Atelier.subject($0.subjectID, in: store.state)?.name.localizedStandardContains(search) ?? false))
        }.sorted { $0.startedAt > $1.startedAt }
    }
    var body: some View {
        List {
            Section { Picker("Type", selection: $kind) { Text("Tout").tag(nil as SessionKind?); Text("Cours").tag(Optional(SessionKind.course)); Text("Révisions").tag(Optional(SessionKind.revision)) }.pickerStyle(.segmented) }
            if sessions.isEmpty { EmptyCard(title: "Aucune séance", symbol: "clock.arrow.circlepath", description: "Vos séances enregistrées apparaîtront ici.") }
            ForEach(sessions) { session in NavigationLink { SessionEditorView(session: session) } label: { SessionRow(session: session) } }
        }.navigationTitle("Historique").searchable(text: $search, prompt: "Matière, chapitre ou notes")
    }
}
