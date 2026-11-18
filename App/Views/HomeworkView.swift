import SwiftUI
import CadenceCore

private enum HomeworkFilter: String, CaseIterable, Identifiable {
    case all = "Tous", pending = "À faire", completed = "Terminés", overdue = "Retard"
    var id: String { rawValue }
}

private struct HomeworkDateGroup: Identifiable {
    let date: Date
    let items: [HomeworkItem]
    var id: Date { date }
}

struct HomeworkView: View {
    @EnvironmentObject private var store: AppStore
    @State private var filter: HomeworkFilter = .pending
    @State private var subjectFilter = "all"
    @State private var search = ""

    var body: some View {
        CadenceTimelineView(interval: 30) { now in
            page(now: now)
        }
        .navigationTitle("Devoirs")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, prompt: "Rechercher un devoir")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refreshSchool(force: true) }
                } label: {
                    if store.schoolSyncing { ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(store.schoolSyncing)
                .accessibilityLabel("Actualiser les devoirs")
                .accessibilityIdentifier("homework.refresh")
            }
        }
    }

    private func page(now: Date) -> some View {
        let items = filteredHomework(now: now)
        let worked = HomeworkPresentation.workedSeconds(state: store.state, now: now)
        let groups = Dictionary(grouping: items) { SchoolDateCodec.parisCalendar.startOfDay(for: $0.source.deadline) }
            .map { HomeworkDateGroup(date: $0.key, items: $0.value) }.sorted { $0.date < $1.date }
        return AtelierPage(lazy: true) {
            Picker("État des devoirs", selection: $filter) {
                ForEach(HomeworkFilter.allCases) { value in Text(value.rawValue).tag(value) }
            }
            .pickerStyle(.segmented).cadenceSegmentedStyle()
            .accessibilityIdentifier("homework.filter")
            subjectMenu
            if items.isEmpty {
                EmptyCard(title: store.state.homework.isEmpty ? "Vos prochains devoirs" : "Aucun devoir ici",
                          symbol: "checklist",
                          description: store.state.homework.isEmpty
                            ? "Connectez votre compte scolaire dans Réglages pour retrouver vos devoirs PRONOTE. Les devoirs synchronisés restent disponibles hors connexion."
                            : "Aucun devoir ne correspond à ces filtres.")
            }
            ForEach(groups) { group in
                homeworkSection(group, worked: worked, now: now)
            }
            Label(store.schoolStatus, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption).foregroundStyle(CadenceColors.secondary)
                .accessibilityIdentifier("homework.sync.status")
        }
        .refreshable { await store.refreshSchool(force: true) }
    }

    private var subjectMenu: some View {
        HStack {
            Label("Matière", systemImage: "books.vertical").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Picker("Filtrer par matière", selection: $subjectFilter) {
                Text("Toutes les matières").tag("all")
                Text("À classer").tag("unclassified")
                ForEach(store.state.subjects.sorted { $0.position < $1.position }) { subject in
                    Text(subject.name).tag(subject.id.uuidString)
                }
            }.pickerStyle(.menu)
                .accessibilityIdentifier("homework.subject.filter")
        }.padding(.horizontal, 6)
    }

    private func homeworkSection(_ group: HomeworkDateGroup, worked: [String: TimeInterval], now: Date) -> some View {
        Section {
            ForEach(group.items) { item in
                NavigationLink { HomeworkDetailView(homeworkID: item.id) } label: {
                    HomeworkRow(item: item, subject: Atelier.subject(item.subjectID, in: store.state),
                                workedSeconds: worked[item.id, default: 0], now: now)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("homework.row." + item.id)
            }
        } header: {
            CadenceSectionHeader(title: HomeworkPresentation.deadline(group.date),
                                 subtitle: HomeworkPresentation.relativeDay(group.date, now: now))
                .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("homework.date." + HomeworkPresentation.dayKey(group.date))
        }
    }

    private func filteredHomework(now: Date) -> [HomeworkItem] {
        store.state.homework.filter { item in
            let matchesState: Bool
            switch filter {
            case .all: matchesState = true
            case .pending: matchesState = !item.isDone
            case .completed: matchesState = item.isDone
            case .overdue: matchesState = item.isOverdue(at: now)
            }
            let matchesSubject = subjectFilter == "all" ||
                (subjectFilter == "unclassified" && item.subjectID == nil) || item.subjectID?.uuidString == subjectFilter
            let matchesSearch = search.isEmpty || item.source.subject.localizedStandardContains(search) ||
                item.source.description.localizedStandardContains(search) ||
                (Atelier.subject(item.subjectID, in: store.state)?.name.localizedStandardContains(search) ?? false)
            return matchesState && matchesSubject && matchesSearch
        }.sorted { lhs, rhs in
            if lhs.source.deadline != rhs.source.deadline { return lhs.source.deadline < rhs.source.deadline }
            if lhs.source.subject != rhs.source.subject { return lhs.source.subject.localizedStandardCompare(rhs.source.subject) == .orderedAscending }
            return lhs.id < rhs.id
        }
    }
}

struct HomeworkDetailView: View {
    let homeworkID: String
    @EnvironmentObject private var store: AppStore
    @State private var subjectSelection: UUID?
    private var item: HomeworkItem? { store.state.homework.first { $0.id == homeworkID } }

    var body: some View {
        CadenceTimelineView(interval: 60) { now in
            if let item {
                details(item, now: now)
            } else {
                AtelierPage { EmptyCard(title: "Devoir indisponible", symbol: "checklist", description: "Ce devoir n’est pas disponible dans le cache local.") }
            }
        }
        .navigationTitle("Devoir")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { subjectSelection = item?.subjectID }
        .onChange(of: item?.subjectID) { _, subjectID in subjectSelection = subjectID }
        .onChange(of: subjectSelection) { _, subjectID in
            guard let subjectID, subjectID != item?.subjectID else { return }
            store.setHomeworkSubject(homeworkID, subjectID: subjectID)
        }
        .accessibilityIdentifier("homework.detail")
    }

    private func details(_ item: HomeworkItem, now: Date) -> some View {
        let subject = Atelier.subject(item.subjectID, in: store.state)
        return AtelierPage {
            AtelierCard {
                HStack(alignment: .top, spacing: 12) {
                    SubjectMark(subject: subject)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(subject?.name ?? item.source.subject).font(.title3.weight(.bold)).foregroundStyle(CadenceColors.ink)
                        Text("Pour le " + HomeworkPresentation.deadline(item.source.deadline))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    HomeworkStateBadge(item: item, now: now)
                    if item.subjectID == nil { StatusBadge(title: "Matière à classer", color: .orange) }
                }
                if item.source.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Aucune consigne supplémentaire dans le flux PRONOTE.").foregroundStyle(.secondary)
                } else {
                    Text(item.source.description).font(.body).foregroundStyle(CadenceColors.ink)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .accessibilityIdentifier("homework.description")
                }
                if let difficulty = HomeworkPresentation.difficulty(item.source.difficulty) {
                    Label("Difficulté : " + difficulty, systemImage: "slider.horizontal.3")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let minutes = item.source.lengthMinutes, minutes.isFinite, minutes > 0 {
                    Label("Durée estimée : " + Atelier.duration(minutes * 60), systemImage: "clock")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            workActions(item)
            AtelierCard {
                Label("Temps consacré à ce devoir", systemImage: "timer")
                    .font(.subheadline).foregroundStyle(.secondary)
                HomeworkWorkedClock(homeworkID: item.id)
                if store.state.activeSession?.activeHomeworkID == item.id {
                    Label(store.state.activeSession?.isPaused == true ? "Séance en pause" : "Devoir en cours", systemImage: "timer")
                        .font(.subheadline).foregroundStyle(Atelier.blue)
                }
            }
            completionCard(item)
            AtelierCard {
                Text("Matière dans Cadenza").font(.headline)
                SubjectPicker(selection: $subjectSelection).pickerStyle(.menu)
                    .accessibilityIdentifier("homework.subject.assign")
                if subject?.isArchived == true {
                    Text("Choisissez une matière active pour démarrer une nouvelle séance.").font(.caption).foregroundStyle(.secondary)
                }
            }
            resources(item)
            if item.sourceMissing {
                Label("Ce devoir est conservé sur l’iPhone. Il ne figure plus dans le dernier flux, mais votre suivi reste disponible.", systemImage: "tray.full")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func workActions(_ item: HomeworkItem) -> some View {
        if let active = store.state.activeSession {
            if active.activeHomeworkID == item.id {
                ProminentAction(title: "Ouvrir la séance", symbol: "timer") { store.route = "revision" }
                    .accessibilityIdentifier("homework.open.session")
                SecondaryAction(title: "Ne plus travailler ce devoir", symbol: "minus.circle") {
                    store.assignHomeworkToActiveSession(nil)
                }.accessibilityIdentifier("homework.detach")
            } else {
                if active.subjectID != item.subjectID {
                    Text("Votre séance reste classée en \(Atelier.subject(active.subjectID, in: store.state)?.name ?? "sa matière actuelle"). Le temps consacré à ce devoir sera suivi séparément.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ProminentAction(title: "Faire ce devoir dans la séance", symbol: "link") {
                    store.assignHomeworkToActiveSession(item.id)
                    if store.state.activeSession?.activeHomeworkID == item.id { store.route = "revision" }
                }.accessibilityIdentifier("homework.attach")
                Text("Le chronomètre en cours est conservé.").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            ProminentAction(title: "Lancer ce devoir", symbol: "play.fill") {
                store.startHomework(item.id)
                if store.state.activeSession?.activeHomeworkID == item.id { store.route = "revision" }
            }
            .disabled(!store.state.subjects.contains { $0.id == item.subjectID && !$0.isArchived })
            .accessibilityIdentifier("homework.start")
            if item.subjectID == nil {
                Text("Choisissez d’abord la matière de ce devoir.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func completionCard(_ item: HomeworkItem) -> some View {
        AtelierCard {
            HStack {
                Text("Réalisation").font(.headline)
                Spacer()
                StatusBadge(title: item.isDone ? "Terminé" : "À faire", color: item.isDone ? CadenceColors.positive : Atelier.blue)
            }
            Button {
                store.setHomeworkCompletion(item.id, isDone: !item.isDone)
            } label: {
                Label(item.isDone ? "Remettre à faire" : "Marquer comme terminé", systemImage: item.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle")
                    .frame(minHeight: 44)
            }.accessibilityIdentifier("homework.complete")
            LabeledContent("Dans PRONOTE", value: item.sourceDone ? "Terminé" : "À faire")
                .font(.caption).foregroundStyle(.secondary)
            Text(item.localCompletionOverride == nil
                 ? "Vous pouvez valider ce devoir ici. PRONOTE ne sera pas modifié."
                 : "Votre choix dans Cadenza est conservé lors des synchronisations. PRONOTE n’a pas été modifié.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func resources(_ item: HomeworkItem) -> some View {
        let links = HomeworkPresentation.links(item.source.resourceLinks)
        let linkedLabels = Set(links.flatMap { [$0.title, $0.url.absoluteString] })
        let labels = Array(Set(item.source.attachmentLabels)).filter { !linkedLabels.contains($0) }.sorted()
        if !labels.isEmpty || !links.isEmpty {
            AtelierCard {
                Text("Documents et liens").font(.headline)
                ForEach(links) { resource in
                    Link(destination: resource.url) {
                        Label(resource.title, systemImage: "arrow.up.right.square")
                            .frame(minHeight: 44, alignment: .leading)
                    }
                }
                ForEach(labels, id: \.self) { label in
                    Label(label, systemImage: "doc").font(.subheadline).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if links.isEmpty {
                    Text("Le flux indique le nom du document, sans lien de téléchargement.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Choose a homework allocation without interrupting the current timer.
struct HomeworkPickerSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var includeCompleted = false

    var body: some View {
        NavigationStack {
            List {
                if let active = store.state.activeSession {
                    Section {
                        Text("Votre séance continue en \(Atelier.subject(active.subjectID, in: store.state)?.name ?? "sa matière actuelle"). Choisissez le devoir auquel attribuer le temps à partir de maintenant.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Aucun devoir associé", systemImage: "minus.circle") {
                            store.assignHomeworkToActiveSession(nil); dismiss()
                        }.accessibilityIdentifier("homework.picker.detach")
                        Toggle("Inclure les devoirs terminés", isOn: $includeCompleted)
                    }
                    choices(for: active, sameSubject: true)
                    choices(for: active, sameSubject: false)
                    if available.isEmpty {
                        Text("Aucun devoir à proposer dans le cache actuel.").foregroundStyle(.secondary)
                    }
                } else {
                    Text("Démarrez une séance pour y associer un devoir.").foregroundStyle(.secondary)
                }
            }
            .cadenceListStyle()
            .navigationTitle("Choisir un devoir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .accessibilityIdentifier("homework.picker")
    }

    private var available: [HomeworkItem] {
        store.state.homework.filter { includeCompleted || !$0.isDone }.sorted { $0.source.deadline < $1.source.deadline }
    }

    @ViewBuilder private func choices(for active: StudySession, sameSubject: Bool) -> some View {
        let items = available.filter { ($0.subjectID == active.subjectID) == sameSubject }
        if !items.isEmpty {
            Section(sameSubject ? "Même matière" : "Autres matières") {
                ForEach(items) { item in
                    Button {
                        store.assignHomeworkToActiveSession(item.id); dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            SubjectMark(subject: Atelier.subject(item.subjectID, in: store.state))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(Atelier.subject(item.subjectID, in: store.state)?.name ?? item.source.subject).font(.headline)
                                Text(item.source.description.isEmpty ? "Consigne non renseignée" : item.source.description)
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                Text("Pour le " + HomeworkPresentation.deadline(item.source.deadline)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if active.activeHomeworkID == item.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Atelier.blue) }
                        }.padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("homework.picker.row." + item.id)
                }
            }
        }
    }
}

private struct HomeworkRow: View {
    let item: HomeworkItem
    let subject: Subject?
    let workedSeconds: TimeInterval
    let now: Date
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SubjectMark(subject: subject)
            VStack(alignment: .leading, spacing: 7) {
                Text(subject?.name ?? item.source.subject).font(.headline).foregroundStyle(CadenceColors.ink)
                Text(item.source.description.isEmpty ? "Consigne non renseignée" : item.source.description)
                    .font(.subheadline).foregroundStyle(CadenceColors.secondary).lineLimit(3)
                Text("Pour le " + HomeworkPresentation.deadline(item.source.deadline)).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    HomeworkStateBadge(item: item, now: now)
                    if workedSeconds > 0 {
                        Label(Atelier.duration(workedSeconds), systemImage: "timer").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 13)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).cadenceSurface(radius: 22)
    }
}

private struct HomeworkStateBadge: View {
    let item: HomeworkItem
    let now: Date
    var body: some View {
        StatusBadge(title: item.isDone ? "Terminé" : item.isOverdue(at: now) ? "En retard" : "À faire",
                    color: item.isDone ? CadenceColors.positive : item.isOverdue(at: now) ? .orange : Atelier.blue)
    }
}

private enum HomeworkPresentation {
    static func relativeDay(_ date: Date, now: Date) -> String? {
        let calendar = SchoolDateCodec.parisCalendar
        let today = calendar.startOfDay(for: now)
        if date == today { return "Aujourd’hui" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), date == tomorrow { return "Demain" }
        return nil
    }

    static func deadline(_ date: Date) -> String {
        deadlineFormatter.string(from: date)
    }

    static func dayKey(_ date: Date) -> String { dayKeyFormatter.string(from: date) }

    private static let deadlineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = SchoolDateCodec.parisCalendar
        formatter.timeZone = SchoolDateCodec.parisCalendar.timeZone
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .long; formatter.timeStyle = .none
        return formatter
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = SchoolDateCodec.parisCalendar
        formatter.timeZone = SchoolDateCodec.parisCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func workedSeconds(state: CadenceState, now: Date) -> [String: TimeInterval] {
        Statistics.homeworkSeconds(state: state, in: DateInterval(start: .distantPast, end: now), now: now)
    }

    static func difficulty(_ value: SchoolJSON?) -> String? {
        guard let value else { return nil }
        let text: String
        switch value {
        case .number(let number): text = number.isFinite ? String(format: "%g", number) : ""
        case .bool(let flag): text = flag ? "Oui" : "Non"
        default: text = value.strings.joined(separator: ", ")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    static func links(_ resources: [SchoolResourceLink]) -> [SchoolResourceLink] {
        var seen = Set<String>()
        return resources.filter { resource in
            guard let scheme = resource.url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  resource.url.host != nil else { return false }
            return seen.insert(resource.url.absoluteString).inserted
        }
    }
}

/// Only this number ticks once a second, not the description, documents or form.
private struct HomeworkWorkedClock: View {
    let homeworkID: String
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let reference = Date()
        let baseline = HomeworkPresentation.workedSeconds(state: store.state, now: reference)[homeworkID, default: 0]
        let session = store.state.activeSession
        let segment = session?.homeworkWorkSegments?.last
        let running = session?.isPaused == false && segment?.homeworkID == homeworkID && segment?.end == nil
        Group {
            if running {
                CadenceTimelineView(interval: 1) { now in
                    value(baseline + max(0, now.timeIntervalSince(reference)))
                }
            } else { value(baseline) }
        }
    }

    private func value(_ seconds: TimeInterval) -> some View {
        Text(Atelier.clock(seconds)).font(.title2.monospacedDigit().weight(.semibold))
            .foregroundStyle(CadenceColors.ink).accessibilityIdentifier("homework.worked.time")
    }
}
