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
            includes($0.start) && (search.isEmpty || $0.displayTitle(in: store.state.subjects).localizedStandardContains(search) || $0.title.localizedStandardContains(search))
        }.sorted { $0.start < $1.start }
    }
    private var manualSessions: [StudySession] {
        store.state.sessions.filter {
            $0.kind == .course && $0.linkedOccurrenceID == nil && includes($0.startedAt) &&
            (search.isEmpty || $0.topic.localizedStandardContains(search) || (Atelier.subject($0.subjectID, in: store.state)?.name.localizedStandardContains(search) ?? false))
        }.sorted { $0.startedAt < $1.startedAt }
    }
    private var days: [Date] {
        Set(occurrences.map { Calendar.current.startOfDay(for: $0.start) } + manualSessions.map { Calendar.current.startOfDay(for: $0.startedAt) }).sorted()
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Picker("Affichage", selection: $mode) { Text("Semaine").tag("Semaine"); Text("Jour").tag("Jour"); Text("Liste").tag("Liste") }
                    .pickerStyle(.segmented).cadenceSegmentedStyle()
                if mode != "Liste" {
                    HStack {
                        Button { shift(-1) } label: {
                            Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(mode == "Semaine" ? "Semaine précédente" : "Jour précédent")
                        .accessibilityIdentifier("courses.previous")
                        Spacer()
                        DatePicker("Date", selection: $date, displayedComponents: .date).labelsHidden()
                            .accessibilityIdentifier("courses.date")
                        Spacer()
                        Button { shift(1) } label: {
                            Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(mode == "Semaine" ? "Semaine suivante" : "Jour suivant")
                        .accessibilityIdentifier("courses.next")
                    }.padding(6).cadenceSurface(radius: 28)
                }
            if days.isEmpty {
                EmptyCard(title: "Votre semaine se dessine ici", symbol: "calendar", description: "Liez votre emploi du temps ou ajoutez un cours pour retrouver votre journée, en un regard.")
            }
            ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 12) {
                    Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR"))))
                        .font(.headline).foregroundStyle(CadenceColors.ink)
                    ForEach(occurrences.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }) { occurrence in
                        HStack(alignment: .top, spacing: 10) {
                            Text(occurrence.start.cadenceFormatted(date: .omitted, time: .shortened))
                                .font(.caption.monospacedDigit()).foregroundStyle(CadenceColors.secondary)
                                .frame(width: 43, alignment: .leading).padding(.top, 16)
                            NavigationLink { CourseDetailView(occurrenceID: occurrence.id) } label: { CourseRow(occurrence: occurrence) }
                                .buttonStyle(.plain)
                        }
                    }
                    ForEach(manualSessions.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: day) }) { session in
                        NavigationLink { SessionEditorView(session: session) } label: { SessionRow(session: session).padding(12).cadenceSurface(radius: 18) }
                            .buttonStyle(.plain)
                    }
                }.padding(16).cadenceSurface()
            }
                Button { showCalendar = true } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(Atelier.blue)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.state.settings.calendarEnabled ? "Cours synchronisés" : "Lier mon emploi du temps").font(.headline).foregroundStyle(CadenceColors.ink)
                            Text(store.lastSyncAt.map { "Calendrier Apple · " + $0.cadenceFormatted(date: .omitted, time: .shortened) } ?? "Vos calendriers Apple et Google sur l’iPhone")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: store.state.settings.calendarEnabled ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(store.state.settings.calendarEnabled ? CadenceColors.positive : CadenceColors.secondary)
                    }.padding(17).cadenceSurface()
                }.buttonStyle(.plain)
                SecondaryAction(title: "Ajouter un cours", symbol: "plus") { showNew = true }.accessibilityIdentifier("courses.add")
                Text("Les cours à venir ne comptent pas dans vos durées. Les estimations restent séparées du temps mesuré.")
                    .font(.caption).foregroundStyle(CadenceColors.secondary).padding(.horizontal, 4)
            }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 24)
                .frame(maxWidth: CadenceTheme.contentWidth).frame(maxWidth: .infinity)
        }.background(CadenceBackground())
        .navigationTitle("Emploi du temps")
        .searchable(text: $search, prompt: "Rechercher un cours")
        .refreshable { await store.refreshCalendars() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Ajouter un cours", systemImage: "plus") { showNew = true } } }
        .sheet(isPresented: $showNew) { NavigationStack { NewSessionView(kind: .course) } }
        .sheet(isPresented: $showCalendar) { NavigationStack { CalendarSettingsView() } }
    }
    private func includes(_ start: Date) -> Bool {
        guard let interval else { return true }
        return start >= interval.start && start < interval.end
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
                Text(occurrence.displayTitle(in: store.state.subjects)).font(.headline).foregroundStyle(CadenceColors.ink)
                Text(occurrence.start.cadenceFormatted(date: .omitted, time: .shortened) + " – " + occurrence.end.cadenceFormatted(date: .omitted, time: .shortened))
                    .font(.subheadline).foregroundStyle(.secondary)
                Label(occurrence.calendarName, systemImage: "calendar").font(.caption2).foregroundStyle(CadenceColors.secondary).lineLimit(1)
                if occurrence.sourceMissing { Label("N’apparaît plus dans le calendrier", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            }
            Spacer(minLength: 0)
            StatusBadge(title: occurrence.status.label, color: occurrence.status == .needsReview ? .orange : Atelier.blue)
        }.padding(12).fixedSize(horizontal: false, vertical: true)
            .background(LinearGradient(colors: [Atelier.blue.opacity(0.10), Atelier.ice.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(Atelier.ice.opacity(0.35), lineWidth: 0.75) }
    }
}

struct CourseDetailView: View {
    @EnvironmentObject private var store: AppStore
    let occurrenceID: UUID
    @State private var showEdit = false
    @State private var showLink = false
    @State private var showConfirm = false
    @State private var showUnlinkConfirmation = false
    @State private var confirmedMinutes = 60.0
    private var occurrence: CourseOccurrence? { store.state.occurrences.first { $0.id == occurrenceID } }
    var body: some View {
        Group {
            if let course = occurrence {
                List {
                    Section {
                        HStack {
                            SubjectMark(subject: Atelier.subject(course.subjectID, in: store.state))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(course.displayTitle(in: store.state.subjects)).font(.title3.bold())
                                if course.subjectID == nil { Text("Matière à classer").foregroundStyle(.secondary) }
                            }
                        }
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
                            store.start(kind: .course, subjectID: subject, occurrenceID: course.id)
                            store.route = "revision"
                        }.disabled(store.state.activeSession != nil || course.linkedSessionID != nil)
                        Button("Confirmer une durée", systemImage: "checkmark.circle") { confirmedMinutes = (course.confirmedSeconds ?? course.end.timeIntervalSince(course.start)) / 60; showConfirm = true }.disabled(course.subjectID == nil || course.linkedSessionID != nil || course.end > .now)
                        Button("Associer à une séance manuelle", systemImage: "link") { showLink = true }.disabled(course.linkedSessionID != nil)
                        Button("Modifier la matière ou l’horaire", systemImage: "pencil") { showEdit = true }
                    }
                    Section {
                        DisclosureGroup("Détails du calendrier") {
                            Text(course.title).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                        }
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
                            Button("Retirer l’association", systemImage: "link") { showUnlinkConfirmation = true }
                                .accessibilityIdentifier("course.unlink")
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
                .alert("Retirer l’association de cette séance ?", isPresented: $showUnlinkConfirmation) {
                    Button("Retirer l’association", role: .destructive) { store.unlinkSession(occurrenceID: course.id) }
                    Button("Conserver l’association", role: .cancel) { }
                } message: {
                    Text("La séance, sa durée et ses notes sont conservées. Le créneau du calendrier sera marqué « Ignoré » pour éviter de rétablir son estimation. Vous pourrez associer la séance à un autre cours.")
                }
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
