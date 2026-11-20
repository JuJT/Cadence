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
                VStack(alignment: .leading, spacing: 0) {
                    HomeworkRow(item: item, subject: Atelier.subject(item.subjectID, in: store.state),
                                workedSeconds: worked[item.id, default: 0], now: now)
                    Divider().padding(.horizontal, 16)
                    HomeworkQuickActions(item: item).padding(.horizontal, 12).padding(.vertical, 6)
                }
                .cadenceSurface(radius: 24)
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
                SchoolRichText.plain(item.source.description).localizedStandardContains(search) ||
                (Atelier.subject(item.subjectID, in: store.state)?.name.localizedStandardContains(search) ?? false)
            return matchesState && matchesSubject && matchesSearch
        }.sorted { lhs, rhs in
            if lhs.source.deadline != rhs.source.deadline { return lhs.source.deadline < rhs.source.deadline }
            if lhs.source.subject != rhs.source.subject { return lhs.source.subject.localizedStandardCompare(rhs.source.subject) == .orderedAscending }
            return lhs.id < rhs.id
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
                                Text(SchoolRichText.plain(item.source.description).isEmpty ? "Consigne non renseignée" : SchoolRichText.plain(item.source.description))
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
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SubjectMark(subject: subject)
                Text(subject?.name ?? item.source.subject).font(.headline).foregroundStyle(CadenceColors.ink)
                Spacer(minLength: 0)
                Menu {
                    Section("Matière dans Cadenza") {
                        ForEach(store.state.subjects.filter { !$0.isArchived }.sorted { $0.position < $1.position }) { choice in
                            Button {
                                store.setHomeworkSubject(item.id, subjectID: choice.id)
                            } label: {
                                if choice.id == item.subjectID { Label(choice.name, systemImage: "checkmark") }
                                else { Text(choice.name) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Changer la matière de ce devoir")
            }
            let instructions = SchoolRichText.plain(item.source.description)
            Text(instructions.isEmpty ? "Aucune consigne supplémentaire" : instructions)
                .font(.body).foregroundStyle(CadenceColors.ink).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled).accessibilityIdentifier("homework.instructions." + item.id)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { metadata.font(.caption).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 5) { metadata.font(.caption).foregroundStyle(.secondary) }
            }
            let links = HomeworkPresentation.links(item.source.resourceLinks)
            let linked = Set(links.flatMap { [$0.title, $0.url.absoluteString] })
            ForEach(links) { resource in
                Link(destination: resource.url) { Label(resource.title, systemImage: "paperclip").frame(minHeight: 44) }
            }
            ForEach(Array(Set(item.source.attachmentLabels)).filter { !linked.contains($0) }.sorted(), id: \.self) { name in
                Label(name, systemImage: "doc").font(.caption).foregroundStyle(.secondary)
            }
            if item.sourceMissing { Text("Conservé sur cet iPhone").font(.caption).foregroundStyle(.secondary) }
            if subject == nil || subject?.isArchived == true {
                Text("Choisissez une matière dans le menu du devoir pour démarrer une séance.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 16).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var metadata: some View {
        HomeworkStateBadge(item: item, now: now)
        if let minutes = item.source.lengthMinutes, minutes.isFinite, minutes > 0 {
            Label(Atelier.duration(minutes * 60), systemImage: "clock")
                .accessibilityLabel("Durée estimée " + Atelier.duration(minutes * 60))
        }
        if workedSeconds > 0 {
            Label(Atelier.duration(workedSeconds), systemImage: "timer")
                .accessibilityLabel("Temps consacré " + Atelier.duration(workedSeconds))
        }
        if let difficulty = HomeworkPresentation.difficulty(item.source.difficulty), difficulty != "0" {
            Label(difficulty, systemImage: "slider.horizontal.3").accessibilityLabel("Difficulté " + difficulty)
        }
    }
}

private struct HomeworkQuickActions: View {
    let item: HomeworkItem
    @EnvironmentObject private var store: AppStore
    private var active: StudySession? { store.state.activeSession }
    private var isAttached: Bool { active?.activeHomeworkID == item.id }
    private var canStart: Bool {
        active != nil || store.state.subjects.contains { $0.id == item.subjectID && !$0.isArchived }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { completion; session }
            VStack(alignment: .leading, spacing: 4) { completion; session }
        }
    }

    private var completion: some View {
        Button {
            store.setHomeworkCompletion(item.id, isDone: !item.isDone)
        } label: {
            Label(item.isDone ? "À refaire" : "Valider", systemImage: item.isDone ? "arrow.uturn.backward" : "checkmark.circle")
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderless).tint(item.isDone ? Atelier.blue : CadenceColors.positive)
        .accessibilityLabel(item.isDone ? "Remettre ce devoir à faire" : "Marquer ce devoir comme terminé")
        .accessibilityHint("Votre choix est enregistré dans Cadenza.")
        .accessibilityIdentifier("homework.quick.complete." + item.id)
    }

    private var session: some View {
        Button {
            if !isAttached {
                if active == nil { store.startHomework(item.id) }
                else { store.assignHomeworkToActiveSession(item.id) }
            }
            if store.state.activeSession?.activeHomeworkID == item.id { store.route = "revision" }
        } label: {
            Label(isAttached ? "Séance en cours" : active == nil ? "Démarrer" : "Associer", systemImage: isAttached ? "timer" : active == nil ? "play.fill" : "link")
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderless).disabled(!canStart)
        .accessibilityHint(canStart ? "Ouvre le chronomètre associé à ce devoir." : "Choisissez une matière dans le menu du devoir.")
        .accessibilityIdentifier("homework.quick.start." + item.id)
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
