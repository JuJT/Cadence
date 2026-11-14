import SwiftUI
import CadenceCore

struct CoursesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var mode = "Semaine"
    @State private var date = Date()
    @State private var search = ""
    @State private var showNew = false
    @State private var showCalendar = false
    private var interval: DateInterval? {
        switch mode {
        case "Jour": return Atelier.day(date)
        case "Semaine": return Calendar.current.dateInterval(of: .weekOfYear, for: date)
        default: return nil
        }
    }
    private var occurrences: [CourseOccurrence] {
        store.state.occurrences.filter {
            (interval == nil || interval!.contains($0.start)) && (search.isEmpty || $0.title.localizedStandardContains(search))
        }.sorted { $0.start < $1.start }
    }
    private var manualSessions: [StudySession] {
        store.state.sessions.filter {
            $0.kind == .course && $0.linkedOccurrenceID == nil && (interval == nil || interval!.contains($0.startedAt)) &&
            (search.isEmpty || $0.topic.localizedStandardContains(search) || (Atelier.subject($0.subjectID, in: store.state)?.name.localizedStandardContains(search) ?? false))
        }.sorted { $0.startedAt < $1.startedAt }
    }
    private var days: [Date] {
        Set(occurrences.map { Calendar.current.startOfDay(for: $0.start) } + manualSessions.map { Calendar.current.startOfDay(for: $0.startedAt) }).sorted()
    }
    var body: some View {
        List {
            Section {
                Picker("Affichage", selection: $mode) { Text("Semaine").tag("Semaine"); Text("Jour").tag("Jour"); Text("Liste").tag("Liste") }.pickerStyle(.segmented)
                if mode != "Liste" {
                    HStack {
                        Button("Précédent", systemImage: "chevron.left") { shift(-1) }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        Spacer()
                        DatePicker("Date", selection: $date, displayedComponents: .date).labelsHidden()
                        Spacer()
                        Button("Suivant", systemImage: "chevron.right") { shift(1) }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    }
                }
            }.listRowBackground(Color.clear)
            if days.isEmpty {
                EmptyCard(title: "Aucun cours ici", symbol: "calendar", description: "Ajoutez un cours manuel ou choisissez les calendriers de votre emploi du temps.").listRowBackground(Color.clear)
            }
            ForEach(days, id: \.self) { day in
                Section(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")))) {
                    ForEach(occurrences.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }) { occurrence in
                        NavigationLink { CourseDetailView(occurrenceID: occurrence.id) } label: { CourseRow(occurrence: occurrence) }
                    }
                    ForEach(manualSessions.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: day) }) { session in
                        NavigationLink { SessionEditorView(session: session) } label: { SessionRow(session: session) }
                    }
                }
            }
            Section {
                Button { showCalendar = true } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(Atelier.blue)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.state.settings.calendarEnabled ? "Calendriers liés" : "Lier mon emploi du temps").font(.headline).foregroundStyle(.primary)
                            Text(store.lastSyncAt.map { "Actualisé " + $0.cadenceFormatted(date: .abbreviated, time: .shortened) } ?? "Apple et Google déjà synchronisé sur l’iPhone")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
                Text("Les cours à venir ne comptent pas dans vos durées. Les estimations restent séparées des séances mesurées ou confirmées.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Cours")
        .searchable(text: $search, prompt: "Rechercher un cours")
        .refreshable { await store.refreshCalendars() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Ajouter un cours", systemImage: "plus") { showNew = true } } }
        .sheet(isPresented: $showNew) { NavigationStack { NewSessionView(kind: .course) } }
        .sheet(isPresented: $showCalendar) { NavigationStack { CalendarSettingsView() } }
    }
    private func shift(_ direction: Int) { date = Calendar.current.date(byAdding: .day, value: direction * (mode == "Semaine" ? 7 : 1), to: date) ?? date }
}

struct CourseRow: View {
    @EnvironmentObject private var store: AppStore
    let occurrence: CourseOccurrence
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(Color(cadenceHex: Atelier.subject(occurrence.subjectID, in: store.state)?.colorHex ?? "#2776F8")).frame(width: 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(occurrence.title).font(.headline)
                Text(occurrence.start.cadenceFormatted(date: .omitted, time: .shortened) + " – " + occurrence.end.cadenceFormatted(date: .omitted, time: .shortened))
                    .font(.subheadline).foregroundStyle(.secondary)
                Label(occurrence.calendarName, systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                if occurrence.sourceMissing { Label("N’apparaît plus dans le calendrier", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            }
            Spacer(minLength: 0)
            StatusBadge(title: occurrence.status.label, color: occurrence.status == .needsReview ? .orange : Atelier.blue)
        }.padding(.vertical, 5).fixedSize(horizontal: false, vertical: true)
    }
}

struct CourseDetailView: View {
    @EnvironmentObject private var store: AppStore
    let occurrenceID: UUID
    @State private var showEdit = false
    @State private var showLink = false
    @State private var showConfirm = false
    @State private var confirmedMinutes = 60.0
    private var occurrence: CourseOccurrence? { store.state.occurrences.first { $0.id == occurrenceID } }
    var body: some View {
        Group {
            if let course = occurrence {
                List {
                    Section {
                        HStack { SubjectMark(subject: Atelier.subject(course.subjectID, in: store.state)); VStack(alignment: .leading, spacing: 5) { Text(course.title).font(.title3.bold()); Text(Atelier.subject(course.subjectID, in: store.state)?.name ?? "Matière à classer").foregroundStyle(.secondary) } }
                        LabeledContent("Date", value: course.start.cadenceFormatted(date: .complete, time: .omitted))
                        LabeledContent("Horaire", value: course.start.cadenceFormatted(date: .omitted, time: .shortened) + " – " + course.end.cadenceFormatted(date: .omitted, time: .shortened))
                        LabeledContent("Provenance", value: "Calendrier · " + course.calendarName)
                        HStack { Text("État"); Spacer(); StatusBadge(title: course.status.label, color: course.status == .needsReview ? .orange : Atelier.blue) }
                        if course.sourceMissing { Label("L’événement n’apparaît plus dans la source. Vos séances et vos notes sont conservées.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                        if course.status == .needsReview { Text("Vérifiez la matière, l’horaire et la séance associée. Les données personnelles sont conservées jusqu’à votre décision.").font(.footnote).foregroundStyle(.secondary) }
                    }
                    Section("Suivi du cours") {
                        Button("Chronométrer ce cours", systemImage: "play.fill") {
                            guard let subject = course.subjectID else { showEdit = true; return }
                            store.start(kind: .course, subjectID: subject, topic: course.title, occurrenceID: course.id)
                            store.route = "revision"
                        }.disabled(store.state.activeSession != nil || course.linkedSessionID != nil)
                        Button("Confirmer une durée", systemImage: "checkmark.circle") { confirmedMinutes = (course.confirmedSeconds ?? course.end.timeIntervalSince(course.start)) / 60; showConfirm = true }.disabled(course.subjectID == nil || course.linkedSessionID != nil || course.end > .now)
                        Button("Associer à une séance manuelle", systemImage: "link") { showLink = true }.disabled(course.linkedSessionID != nil)
                        Button("Modifier la matière ou l’horaire", systemImage: "pencil") { showEdit = true }
                    }
                    if let pendingStart = course.pendingStart {
                        Section("Modification du calendrier à examiner") {
                            LabeledContent("Horaire conservé", value: course.start.cadenceFormatted(date: .abbreviated, time: .shortened) + " – " + course.end.cadenceFormatted(date: .omitted, time: .shortened))
                            LabeledContent("Nouvel horaire", value: pendingStart.cadenceFormatted(date: .abbreviated, time: .shortened) + " – " + (course.pendingEnd ?? course.end).cadenceFormatted(date: .omitted, time: .shortened))
                            if let title = course.pendingTitle, title != course.title { LabeledContent("Nouveau titre", value: title) }
                            Button("Adopter la modification du calendrier", systemImage: "checkmark.circle") { store.acceptCalendarChanges(course.id) }
                            Button("Conserver mon horaire personnel", systemImage: "pin") { store.keepOccurrenceChanges(course.id) }
                        }
                    }
                    if let linked = store.state.sessions.first(where: { $0.id == course.linkedSessionID }) {
                        Section("Séance associée") {
                            NavigationLink { SessionEditorView(session: linked) } label: { SessionRow(session: linked) }
                            Text("La durée de cette séance remplace l’estimation du calendrier.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Menu("Changer l’état", systemImage: "ellipsis.circle") {
                            Button("Marquer absent") { store.setOccurrenceStatus(course.id, status: .absent) }
                            Button("Ignorer ce cours") { store.setOccurrenceStatus(course.id, status: .ignored) }
                            Button("Rétablir comme cours planifié") { store.setOccurrenceStatus(course.id, status: .scheduled) }
                        }.disabled(course.linkedSessionID != nil)
                    } footer: { Text("Ces actions modifient uniquement votre suivi Cadence. Votre calendrier système reste inchangé.") }
                }
                .sheet(isPresented: $showEdit) { NavigationStack { OccurrenceEditorView(occurrence: course) } }
                .sheet(isPresented: $showLink) { NavigationStack { SessionLinkView(occurrence: course) } }
                .sheet(isPresented: $showConfirm) {
                    NavigationStack {
                        Form {
                            Section("Temps de cours effectué") {
                                Stepper("\(Int(confirmedMinutes)) minutes", value: $confirmedMinutes, in: 1...1440, step: 5)
                                Text("Cette durée sera comptée comme confirmée, à la place de l’estimation.").font(.footnote).foregroundStyle(.secondary)
                            }
                        }.navigationTitle("Confirmer le cours").navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { showConfirm = false } }
                                ToolbarItem(placement: .confirmationAction) { Button("Confirmer") { store.confirmOccurrence(course.id, seconds: confirmedMinutes * 60); showConfirm = false } }
                            }
                    }.presentationDetents([.medium, .large])
                }
            } else { EmptyCard(title: "Cours introuvable", symbol: "calendar", description: "Revenez à la liste pour sélectionner un cours.") }
        }.navigationTitle("Détail du cours").navigationBarTitleDisplayMode(.inline)
    }
}

private struct OccurrenceEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let occurrence: CourseOccurrence
    @State private var title: String
    @State private var subjectID: UUID?
    @State private var start: Date
    @State private var end: Date
    init(occurrence: CourseOccurrence) {
        self.occurrence = occurrence
        _title = State(initialValue: occurrence.title); _subjectID = State(initialValue: occurrence.subjectID)
        _start = State(initialValue: occurrence.start); _end = State(initialValue: occurrence.end)
    }
    var body: some View {
        Form {
            Section("Dans Cadence") {
                TextField("Titre", text: $title)
                SubjectPicker(selection: $subjectID)
                DatePicker("Début", selection: $start)
                DatePicker("Fin", selection: $end)
            }
            Section { Text("La modification est locale. L’événement d’origine dans Calendrier reste inchangé.").foregroundStyle(.secondary) }
        }.navigationTitle("Modifier le cours").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { store.updateOccurrence(occurrence.id, subjectID: subjectID, title: title, start: start, end: end); if store.errorMessage == nil { dismiss() } }.disabled(subjectID == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end <= start) }
            }
    }
}

private struct SessionLinkView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let occurrence: CourseOccurrence
    private var candidates: [StudySession] {
        store.state.sessions.filter { $0.kind == .course && $0.linkedOccurrenceID == nil && $0.endedAt != nil && (occurrence.subjectID == nil || $0.subjectID == occurrence.subjectID) }.sorted { abs($0.startedAt.timeIntervalSince(occurrence.start)) < abs($1.startedAt.timeIntervalSince(occurrence.start)) }
    }
    var body: some View {
        List {
            Section { Text("Choisissez la séance qui correspond à ce cours. Sa durée remplacera le temps estimé : les deux ne seront pas additionnés.").foregroundStyle(.secondary) }
            if candidates.isEmpty { EmptyCard(title: "Aucune séance à associer", symbol: "link", description: "Ajoutez d’abord un cours manuel terminé pour cette matière.") }
            ForEach(candidates) { session in
                Button { store.linkSession(sessionID: session.id, occurrenceID: occurrence.id); if store.errorMessage == nil { dismiss() } } label: { SessionRow(session: session) }
            }
        }.navigationTitle("Associer une séance").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
    }
}
