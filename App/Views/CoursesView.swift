import SwiftUI
import CadenceCore

struct CoursesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var mode = "Jour"
    @State private var date = Date()
    @State private var search = ""
    @State private var showNew = false
    private var calendar: Calendar {
        var value = store.state.schoolSync == nil ? Calendar.current : SchoolDateCodec.parisCalendar
        value.locale = Locale(identifier: "fr_FR")
        value.firstWeekday = 2
        return value
    }
    private var hasCourseContents: Bool {
        (store.pronoteProfile ?? store.pronotePortal.profile)?.capabilities.contains("contents") == true ||
        store.pronotePortal.sections.keys.contains { $0 == "contents" || $0.hasPrefix("contents:") }
    }
    private var schoolDataIsOld: Bool {
        guard let sync = store.state.schoolSync else { return false }
        if sync.hasError { return true }
        return (sync.lastTimetableSync ?? sync.lastSuccessfulFetch).map { Date().timeIntervalSince($0) > 24 * 3600 } ?? false
    }
    private var interval: DateInterval? {
        switch mode {
        case "Jour": return Statistics.dayInterval(containing: date, calendar: calendar)
        case "Semaine": return calendar.dateInterval(of: .weekOfYear, for: date)
        default: return nil
        }
    }
    var body: some View {
        let groups = dayGroups()
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Picker("Affichage", selection: $mode) {
                    ForEach(["Jour", "Semaine", "Liste"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).cadenceSegmentedStyle()
                if mode != "Liste" {
                    VStack(spacing: 1) {
                        HStack {
                            Button { shift(-1) } label: {
                                Image(systemName: "chevron.left").frame(width: 44, height: 44)
                            }.accessibilityLabel(mode == "Semaine" ? "Semaine précédente" : "Jour précédent")
                                .accessibilityIdentifier("courses.previous")
                            Spacer()
                            DatePicker("Date", selection: $date, displayedComponents: .date).labelsHidden()
                                .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
                                .accessibilityIdentifier("courses.date")
                            Spacer()
                            Button { shift(1) } label: {
                                Image(systemName: "chevron.right").frame(width: 44, height: 44)
                            }.accessibilityLabel(mode == "Semaine" ? "Semaine suivante" : "Jour suivant")
                                .accessibilityIdentifier("courses.next")
                        }
                        if mode == "Jour" { dayStrip }
                    }.padding(4).cadenceSurface(radius: 22)
                }
                if groups.isEmpty {
                    EmptyCard(title: search.isEmpty ? "Aucun cours prévu" : "Aucun cours trouvé", symbol: "calendar",
                              description: search.isEmpty ? "Consultez une autre date ou ajoutez un cours." : "Essayez une autre matière.")
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(CourseDisplay.dayTitle(group.date, calendar: calendar).capitalized)
                            .font(.headline).foregroundStyle(CadenceColors.ink).padding(.leading, 3)
                        ForEach(group.entries) { entry in
                            switch entry {
                            case .scheduled(let course):
                                NavigationLink { CourseDetailView(occurrenceID: course.id) } label: { CourseRow(occurrence: course) }
                                    .buttonStyle(.plain)
                            case .manual(let session):
                                NavigationLink { SessionEditorView(session: session) } label: {
                                    SessionRow(session: session).padding(9).cadenceSurface(radius: 12)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if hasCourseContents { PronoteShortcutRow(section: .contents) }
                NavigationLink { SchoolConnectionView() } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(Atelier.blue)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.state.schoolSync == nil ? "Connecter PRONOTE" : "Cours et devoirs synchronisés").font(.headline).foregroundStyle(CadenceColors.ink)
                            Text(store.schoolStatus)
                                .font(.caption).foregroundStyle(.secondary)
                            if let last = store.state.schoolSync?.lastSuccessfulFetch {
                                Text("Dernière actualisation · " + last.cadenceFormatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if schoolDataIsOld { Text("Données à actualiser").font(.caption2).foregroundStyle(.orange) }
                        }
                        Spacer(minLength: 0)
                        if store.schoolSyncing { ProgressView() }
                        else {
                            Image(systemName: schoolDataIsOld ? "exclamationmark.circle" : store.state.schoolSync == nil ? "chevron.right" : "checkmark.circle.fill")
                                .foregroundStyle(schoolDataIsOld ? Color.orange : store.state.schoolSync == nil ? CadenceColors.secondary : CadenceColors.positive)
                        }
                    }.padding(17).cadenceSurface()
                }.buttonStyle(.plain)
                SecondaryAction(title: "Ajouter un cours", symbol: "plus") { showNew = true }.accessibilityIdentifier("courses.add")
                Text("Les cours terminés sont comptés automatiquement. Vous pouvez retirer ceux qui n’ont pas eu lieu.")
                    .font(.caption).foregroundStyle(CadenceColors.secondary).padding(.horizontal, 4)
            }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 24)
                .frame(maxWidth: CadenceTheme.contentWidth).frame(maxWidth: .infinity)
        }.background(CadenceBackground())
        .navigationTitle("Emploi du temps")
        .searchable(text: $search, prompt: "Rechercher un cours")
        .refreshable { await store.refreshSchool(force: true) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Ajouter un cours", systemImage: "plus") { showNew = true } } }
        .sheet(isPresented: $showNew) { NavigationStack { NewSessionView(kind: .course) } }
    }
    private var dayStrip: some View {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        return HStack(spacing: 1) {
            ForEach(days, id: \.self) { day in
                let selected = calendar.isDate(day, inSameDayAs: date)
                Button { date = day } label: {
                    VStack(spacing: 3) {
                        Text(calendar.veryShortStandaloneWeekdaySymbols[calendar.component(.weekday, from: day) - 1].uppercased())
                            .font(.caption2.weight(.medium))
                        Text(String(calendar.component(.day, from: day))).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(selected ? Color.white : CadenceColors.ink)
                    .background(selected ? Atelier.blue : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                    .accessibilityLabel(CourseDisplay.dayTitle(day, calendar: calendar))
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func dayGroups() -> [CourseDayGroup] {
        let window = interval
        let subjects = store.state.subjects
        func includes(_ date: Date) -> Bool { window.map { date >= $0.start && date < $0.end } ?? true }
        let courses = store.state.visibleOccurrences.filter {
            includes($0.start) && (search.isEmpty || $0.displayTitle(in: subjects).localizedStandardContains(search) || $0.title.localizedStandardContains(search))
        }.sorted { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start }
        let sessions = store.state.sessions.filter {
            $0.kind == .course && $0.linkedOccurrenceID == nil && includes($0.startedAt) &&
                (search.isEmpty || $0.topic.localizedStandardContains(search) || (Atelier.subject($0.subjectID, in: store.state)?.name.localizedStandardContains(search) ?? false))
        }.sorted { $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt }
        let coursesByDay = Dictionary(grouping: courses) { calendar.startOfDay(for: $0.start) }
        let sessionsByDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
        return Set(coursesByDay.keys).union(sessionsByDay.keys).sorted().map {
            CourseDayGroup(date: $0, occurrences: coursesByDay[$0] ?? [], manualSessions: sessionsByDay[$0] ?? [])
        }
    }
    private func shift(_ direction: Int) { date = calendar.date(byAdding: .day, value: direction * (mode == "Semaine" ? 7 : 1), to: date) ?? date }
}

private struct CourseDayGroup: Identifiable {
    let date: Date
    let occurrences: [CourseOccurrence]
    let manualSessions: [StudySession]
    var id: Date { date }
    var entries: [CourseDayEntry] {
        (occurrences.map(CourseDayEntry.scheduled) + manualSessions.map(CourseDayEntry.manual))
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
}

private enum CourseDayEntry: Identifiable {
    case scheduled(CourseOccurrence), manual(StudySession)
    var id: String {
        switch self {
        case .scheduled(let course): return "course-" + course.id.uuidString
        case .manual(let session): return "session-" + session.id.uuidString
        }
    }
    var start: Date {
        switch self {
        case .scheduled(let course): return course.start
        case .manual(let session): return session.startedAt
        }
    }
}

/// School times use Europe/Paris; personal sessions keep the device's normal display zone.
enum CourseDisplay {
    private static func calendar(for course: CourseOccurrence) -> Calendar {
        course.school == nil ? .current : SchoolDateCodec.parisCalendar
    }
    private static func formatted(_ date: Date, style: Date.FormatStyle, calendar: Calendar) -> String {
        var style = style
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
    static func time(_ date: Date, course: CourseOccurrence) -> String {
        formatted(date, style: Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "fr_FR")), calendar: calendar(for: course))
    }
    static func timeRange(_ course: CourseOccurrence) -> String {
        time(course.start, course: course) + " – " + time(course.end, course: course)
    }
    static func date(_ date: Date, course: CourseOccurrence) -> String {
        formatted(date, style: Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "fr_FR")), calendar: calendar(for: course))
    }
    static func shortDay(_ date: Date, course: CourseOccurrence) -> String {
        formatted(date, style: .dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "fr_FR")), calendar: calendar(for: course))
    }
    static func schoolDay(_ date: Date) -> String {
        formatted(date, style: Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "fr_FR")), calendar: SchoolDateCodec.parisCalendar)
    }
    static func dayTitle(_ date: Date, calendar: Calendar) -> String {
        formatted(date, style: .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")), calendar: calendar)
    }
    static func status(_ course: CourseOccurrence, autoCredit: Bool, now: Date = Date()) -> String {
        if course.school?.exempted == true { return "Dispensé" }
        if course.school?.canceled == true { return "Annulé" }
        if course.status == .ignored { return "Non suivi" }
        if course.status == .confirmed { return "Corrigé" }
        if course.status == .estimated { return "Terminé" }
        if [.scheduled, .inProgressScheduled].contains(course.status), !course.sourceMissing,
           course.end <= now, course.school != nil || autoCredit { return "Terminé" }
        return course.status.label
    }
}

private struct CourseContentsSections: View {
    let contents: [SchoolCourseContent]
    var body: some View {
        ForEach(contents) { content in
            Section(content.title.isEmpty ? "Contenu du cours" : content.title) {
                if !SchoolRichText.plain(content.description).isEmpty { Text(SchoolRichText.plain(content.description)).textSelection(.enabled) }
                if let category = content.categoryText, !category.isEmpty { Text(category).font(.caption).foregroundStyle(.secondary) }
                ForEach(content.resourceLinks) { resource in
                    Link(destination: resource.url) { Label(resource.title, systemImage: "arrow.up.right.square") }
                }
                if content.resourceLinks.isEmpty {
                    ForEach(Array(content.files.strings.enumerated()), id: \.offset) { _, name in
                        Label(name, systemImage: "doc").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct CourseRow: View {
    @EnvironmentObject private var store: AppStore
    let occurrence: CourseOccurrence
    var body: some View {
        let tint = Color(cadenceHex: Atelier.subject(occurrence.subjectID, in: store.state)?.colorHex ?? "#2776F8")
        let cancelled = occurrence.school?.canceled == true || occurrence.status == .cancelled
        let room = occurrence.school?.classrooms.joined(separator: ", ") ?? ""
        let teacher = occurrence.school?.teacherNames.joined(separator: ", ") ?? ""
        let detail = [room, teacher].filter { !$0.isEmpty }.joined(separator: " · ")
        HStack(spacing: 9) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(CourseDisplay.time(occurrence.start, course: occurrence)).font(.subheadline.weight(.semibold))
                Text(CourseDisplay.time(occurrence.end, course: occurrence)).font(.caption).foregroundStyle(.secondary)
            }.monospacedDigit().fixedSize(horizontal: true, vertical: false)
            RoundedRectangle(cornerRadius: 2).fill(cancelled ? Color.secondary : tint).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.displayTitle(in: store.state.subjects)).font(.headline).strikethrough(cancelled)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                if let status = sourceStatus {
                    Text(status).font(.caption.weight(.semibold)).foregroundStyle(cancelled ? Color.secondary : Color.orange)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .foregroundStyle(CadenceColors.ink)
        .padding(.horizontal, 11).padding(.vertical, 6).frame(minHeight: 48)
        .cadenceSurface(radius: 13)
    }

    private var sourceStatus: String? {
        if let label = occurrence.school?.statusLabel, !label.isEmpty { return label }
        if occurrence.sourceMissing { return "Absent du dernier relevé" }
        if occurrence.school?.isTest == true { return "Évaluation" }
        if occurrence.school?.canceled == true || occurrence.school?.exempted == true ||
            [.cancelled, .absent, .needsReview].contains(occurrence.status) {
            return CourseDisplay.status(occurrence, autoCredit: store.state.settings.autoCreditCourses)
        }
        return nil
    }
}

struct CourseDetailView: View {
    @EnvironmentObject private var store: AppStore
    let occurrenceID: UUID
    @State private var showEdit = false
    @State private var showLink = false
    @State private var showDurationCorrection = false
    @State private var showUnlinkConfirmation = false
    @State private var correctedMinutes = 60.0
    private var occurrence: CourseOccurrence? { store.state.visibleOccurrences.first { $0.id == occurrenceID } }
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
                        LabeledContent("Date", value: CourseDisplay.date(course.start, course: course))
                        LabeledContent("Horaire", value: CourseDisplay.timeRange(course))
                        LabeledContent("Provenance", value: course.school == nil ? "Calendrier personnel · " + course.calendarName : "PRONOTE")
                        HStack { Text("État"); Spacer(); StatusBadge(title: CourseDisplay.status(course, autoCredit: store.state.settings.autoCreditCourses), color: course.status == .needsReview ? .orange : Atelier.blue) }
                        if course.sourceMissing { Label("L’événement n’apparaît plus dans la source. Vos séances et vos notes sont conservées.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                        if course.status == .needsReview { Text("Vérifiez la matière, l’horaire et la séance associée. Les données personnelles sont conservées jusqu’à votre décision.").font(.footnote).foregroundStyle(.secondary) }
                    }
                    if let school = course.school {
                        Section("Votre cours") {
                            if !school.teacherNames.isEmpty { LabeledContent("Professeur", value: school.teacherNames.joined(separator: ", ")) }
                            if !school.classrooms.isEmpty { LabeledContent("Salle", value: school.classrooms.joined(separator: ", ")) }
                            if !school.groupNames.isEmpty { LabeledContent("Groupe", value: school.groupNames.joined(separator: ", ")) }
                            if school.isTest { Label("Évaluation", systemImage: "doc.text.magnifyingglass").foregroundStyle(.orange) }
                            if school.canceled { Label("Cours annulé par PRONOTE", systemImage: "calendar.badge.minus").foregroundStyle(.secondary) }
                            if school.exempted { Label("Dispense indiquée par PRONOTE", systemImage: "person.crop.circle.badge.checkmark").foregroundStyle(.secondary) }
                        }
                    }
                    CourseContentsSections(contents: SchoolReconciler.contents(for: course, state: store.state))
                    Section("Suivi du cours") {
                        Button("Chronométrer ce cours", systemImage: "play.fill") {
                            guard let subject = course.subjectID else { showEdit = true; return }
                            store.start(kind: .course, subjectID: subject, occurrenceID: course.id)
                            store.route = "revision"
                        }.disabled(store.state.activeSession != nil || course.linkedSessionID != nil || course.school?.canceled == true || course.school?.exempted == true)
                        Button("Corriger la durée suivie", systemImage: "slider.horizontal.3") {
                            correctedMinutes = (course.confirmedSeconds ?? course.end.timeIntervalSince(course.start)) / 60
                            showDurationCorrection = true
                        }.disabled(course.subjectID == nil || course.linkedSessionID != nil || course.end > .now || course.school?.canceled == true || course.school?.exempted == true)
                        Button("Associer à une séance manuelle", systemImage: "link") { showLink = true }.disabled(course.linkedSessionID != nil)
                        Button("Modifier la matière ou l’horaire", systemImage: "pencil") { showEdit = true }
                    }
                    Section {
                        DisclosureGroup("Détails de la source") {
                            Text(course.title).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    if let pendingStart = course.pendingStart {
                        Section("Modification du calendrier personnel") {
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
                            Text("La durée de cette séance remplace celle du créneau, sans compter le cours deux fois.").font(.footnote).foregroundStyle(.secondary)
                            Button("Retirer l’association", systemImage: "link") { showUnlinkConfirmation = true }
                                .accessibilityIdentifier("course.unlink")
                        }
                    }
                    Section {
                        Button("Ce cours n’a pas eu lieu", systemImage: "calendar.badge.minus") { store.setOccurrenceStatus(course.id, status: .ignored) }
                            .disabled(course.linkedSessionID != nil)
                        Button("J’étais absent", systemImage: "person.crop.circle.badge.xmark") { store.setOccurrenceStatus(course.id, status: .absent) }
                            .disabled(course.linkedSessionID != nil)
                        if [.absent, .ignored, .cancelled].contains(course.accountingStatus) {
                            Button("Rétablir le suivi automatique", systemImage: "arrow.uturn.backward") { store.setOccurrenceStatus(course.id, status: .scheduled) }
                                .disabled(course.linkedSessionID != nil || course.school?.canceled == true || course.school?.exempted == true)
                        }
                    } footer: { Text(course.linkedSessionID == nil ? "Le suivi est automatique. Ces choix restent dans Cadenza, sans modifier PRONOTE ni vos calendriers." : "Pour corriger un cours chronométré, ouvrez sa séance associée. Sa durée et ses notes restent conservées.") }
                }
                .cadenceListStyle()
                .sheet(isPresented: $showEdit) { NavigationStack { OccurrenceEditorView(occurrence: course) } }
                .sheet(isPresented: $showLink) { NavigationStack { SessionLinkView(occurrence: course) } }
                .alert("Retirer l’association de cette séance ?", isPresented: $showUnlinkConfirmation) {
                    Button("Retirer l’association", role: .destructive) { store.unlinkSession(occurrenceID: course.id) }
                    Button("Conserver l’association", role: .cancel) { }
                } message: {
                    Text("La séance, sa durée et ses notes sont conservées. Le créneau sera retiré du décompte automatique pour éviter un doublon. Vous pourrez associer la séance à un autre cours.")
                }
                .sheet(isPresented: $showDurationCorrection) {
                    NavigationStack {
                        Form {
                            Section("Temps de cours effectué") {
                                Stepper("\(Int(correctedMinutes)) minutes", value: $correctedMinutes, in: 1...1440, step: 5)
                                Text("Cette correction remplace la durée prévue. Les autres cours continuent à être comptés automatiquement.").font(.footnote).foregroundStyle(.secondary)
                            }
                        }.cadenceListStyle().navigationTitle("Corriger la durée").navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { showDurationCorrection = false } }
                                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { store.confirmOccurrence(course.id, seconds: correctedMinutes * 60); if store.errorMessage == nil { showDurationCorrection = false } } }
                            }
                    }.presentationDetents([.medium, .large])
                }
            } else { EmptyCard(title: "Cours introuvable", symbol: "calendar", description: "Revenez à la liste pour sélectionner un cours.") }
        }.navigationTitle("Détail du cours").navigationBarTitleDisplayMode(.inline)
            .task(id: occurrence?.school?.lessonResourceID) {
                if let id = occurrence?.school?.lessonResourceID { await store.loadPronoteResource(id) }
            }
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
            Section("Dans Cadenza") {
                TextField("Titre", text: $title)
                SubjectPicker(selection: $subjectID)
                DatePicker("Début", selection: $start)
                DatePicker("Fin", selection: $end)
            }
            Section { Text("Cette correction reste dans Cadenza. PRONOTE et les calendriers personnels ne sont pas modifiés.").foregroundStyle(.secondary) }
        }.cadenceListStyle().navigationTitle("Modifier le cours").navigationBarTitleDisplayMode(.inline)
            .environment(\.timeZone, occurrence.school == nil ? TimeZone.current : SchoolDateCodec.parisCalendar.timeZone)
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
            Section { Text("Choisissez la séance qui correspond à ce cours. Sa durée remplacera celle du créneau : ce cours sera compté une seule fois.").foregroundStyle(.secondary) }
            if candidates.isEmpty { EmptyCard(title: "Aucune séance à associer", symbol: "link", description: "Ajoutez d’abord un cours manuel terminé pour cette matière.") }
            ForEach(candidates) { session in
                Button { store.linkSession(sessionID: session.id, occurrenceID: occurrence.id); if store.errorMessage == nil { dismiss() } } label: { SessionRow(session: session) }
            }
        }.cadenceListStyle().navigationTitle("Associer une séance").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
    }
}
