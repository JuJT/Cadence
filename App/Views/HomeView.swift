import SwiftUI
import CadenceCore

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showNewSession = false
    var body: some View {
        CadenceTimelineView(interval: 60) { now in
            AtelierPage {
                if store.needsRecovery {
                    AtelierCard {
                        Label("Récupération des données", systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(.orange)
                        Text("Le fichier local existant est conservé. Restaurez une sauvegarde pour reprendre votre suivi.").foregroundStyle(.secondary)
                        NavigationLink("Restaurer une sauvegarde") { SettingsView() }
                    }
                }
                studyActions
                CadenceSectionHeader(title: "Vie scolaire")
                if let next = store.state.visibleOccurrences.filter({
                    $0.start > now && !$0.sourceMissing && $0.school?.canceled != true && $0.school?.exempted != true
                        && ![.cancelled, .ignored, .absent].contains($0.accountingStatus)
                }).min(by: { $0.start < $1.start }) {
                    NavigationLink { CourseDetailView(occurrenceID: next.id) } label: {
                        nextCourseCard(next)
                    }.buttonStyle(.plain)
                } else {
                    Button { store.route = "cours" } label: {
                        AtelierCard {
                            Label("Prochain cours", systemImage: "calendar")
                                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Atelier.blue.opacity(0.35)).frame(width: 4, height: 40)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Aucun cours à venir").font(.headline).foregroundStyle(CadenceColors.ink)
                                    Text("Consulter l’emploi du temps")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
                if store.state.schoolSync != nil || !store.state.homework.isEmpty {
                    Button { store.route = "devoirs" } label: { homeworkCard(now: now) }
                        .buttonStyle(.plain).accessibilityIdentifier("home.homework")
                }
                if let profile = store.pronoteProfile ?? store.pronotePortal.profile {
                    CadenceSectionHeader(title: "Établissement",
                        subtitle: [profile.className, profile.establishment].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    PronoteQuickLinksView(sections: [.news, .attendance, .discussions, .contents, .evaluations, .gradebook, .menus, .account, .homepage])
                } else {
                    NavigationLink { SchoolConnectionView() } label: {
                        Label("Connecter mon établissement", systemImage: "graduationcap")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered)
                }
                NavigationLink { SchoolConnectionView() } label: {
                    HStack(spacing: 8) {
                        if store.schoolSyncing { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.triangle.2.circlepath") }
                        Text(syncDescription)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2)
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                }.buttonStyle(.plain)
            }
        }
        .navigationTitle("Aujourd’hui")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showNewSession) { NewSessionSheet() }
        .refreshable { await store.refreshSchool(force: true) }
    }

    private var studyActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            CadenceSectionHeader(title: "Révision")
            if let active = store.state.activeSession {
                ActiveSessionCard(session: active) {
                    if store.state.activeSession?.isPaused == true { store.resume() }
                    store.openRevisionRoot()
                }
            } else {
                ProminentAction(title: "Démarrer une révision", symbol: "play.fill") { store.openRevisionRoot() }
                    .accessibilityIdentifier("home.revision")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { studyLinks(singleLine: true) }
                VStack(alignment: .leading, spacing: 8) { studyLinks(singleLine: false) }
            }
        }
    }

    @ViewBuilder private func studyLinks(singleLine: Bool) -> some View {
        studyLink("Statistiques", symbol: "chart.bar.xaxis", id: "home.statistics", singleLine: singleLine) { store.route = "statistiques" }
        if store.state.activeSession == nil {
            studyLink("Nouvelle séance", symbol: "plus", id: "session.new", singleLine: singleLine) { showNewSession = true }
        }
    }

    private func studyLink(_ title: String, symbol: String, id: String, singleLine: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold)).fixedSize(horizontal: singleLine, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 12)
                .cadenceReadingSurface(radius: 14)
        }.buttonStyle(.plain).foregroundStyle(Atelier.blue).accessibilityIdentifier(id)
    }

    private var syncDescription: String {
        if store.schoolSyncing { return "Actualisation des cours et devoirs…" }
        guard let date = store.state.schoolSync?.lastSuccessfulFetch else { return store.schoolStatus }
        return "PRONOTE · actualisé " + date.cadenceFormatted(date: .abbreviated, time: .shortened)
    }

    private func nextCourseCard(_ next: CourseOccurrence) -> some View {
        AtelierCard {
            Label("Prochain cours", systemImage: "calendar")
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Atelier.blue, .cyan.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 46).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(next.displayTitle(in: store.state.subjects)).font(.headline).foregroundStyle(CadenceColors.ink)
                    Text(CourseDisplay.shortDay(next.start, course: next) + " · " + CourseDisplay.timeRange(next))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        }
    }

    private func homeworkCard(now: Date) -> some View {
        let pending = store.state.homework.filter { !$0.isDone }.sorted { $0.source.deadline < $1.source.deadline }
        let overdue = pending.filter { $0.isOverdue(at: now) }.count
        return AtelierCard {
            HStack {
                Label("Mes devoirs", systemImage: "checklist").font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(pending.count)").font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
                Text(pending.isEmpty ? "Tout est à jour" : "à faire").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if overdue > 0 { Text("\(overdue) en retard").font(.caption).foregroundStyle(.orange) }
            }
            if let next = pending.first {
                Text((Atelier.subject(next.subjectID, in: store.state)?.name ?? next.source.subject) + " · " + CourseDisplay.schoolDay(next.source.deadline))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.foregroundStyle(CadenceColors.ink)
    }

}

private struct NewSessionSheet: View {
    private enum FormRoute: Hashable {
        case revision, course
        var kind: SessionKind { self == .revision ? .revision : .course }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var detent: PresentationDetent = .medium
    @State private var path: [FormRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        path.append(.revision)
                    } label: {
                        choice("Révision", subtitle: "Travailler une matière ou ajouter une révision passée.", symbol: SessionKind.revision.symbol, color: Atelier.revision)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("session.choose.revision")
                    Button {
                        path.append(.course)
                    } label: {
                        choice("Cours", subtitle: "Chronométrer un cours ou saisir une durée réalisée.", symbol: SessionKind.course.symbol, color: Atelier.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("session.choose.course")
                } header: {
                    Text("Quel type de séance souhaitez-vous ajouter ?")
                }
            }
            .cadenceListStyle()
            .navigationTitle("Nouvelle séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
            .navigationDestination(for: FormRoute.self) { route in
                NewSessionView(kind: route.kind, onComplete: { dismiss() })
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .onChange(of: path) { _, routes in
            detent = routes.isEmpty ? .medium : .large
        }
    }

    private func choice(_ title: String, subtitle: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2).foregroundStyle(color).frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct ActiveSessionCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let session: StudySession
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            AtelierCard {
                HStack {
                    SubjectMark(subject: Atelier.subject(session.subjectID, in: store.state))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Atelier.subject(session.subjectID, in: store.state)?.name ?? "Matière archivée").font(.headline)
                        Text(session.kind.label + " · " + (session.isPaused ? "En pause" : "En cours")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                layout {
                    Text(session.isPaused ? "Reprendre la séance" : "Ouvrir la séance")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Atelier.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SessionElapsedText(session: session).font(.title3.monospacedDigit().bold()).foregroundStyle(Atelier.blue)
                }
            }.foregroundStyle(.primary)
        }.buttonStyle(.plain)
    }
}

struct SessionRow: View {
    @EnvironmentObject private var store: AppStore
    let session: StudySession
    var body: some View {
        HStack(spacing: 12) {
            SubjectMark(subject: Atelier.subject(session.subjectID, in: store.state))
            VStack(alignment: .leading, spacing: 4) {
                Text(Atelier.subject(session.subjectID, in: store.state)?.name ?? "Matière archivée").font(.headline)
                Text(session.kind.label + " · " + session.startedAt.cadenceFormatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                if !session.topic.isEmpty { Text(session.topic).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Atelier.duration(session.elapsed(at: .now))).font(.subheadline.weight(.semibold)).monospacedDigit()
                if session.endedAt == nil { StatusBadge(title: session.isPaused ? "Pause" : "En cours", color: Atelier.color(for: session.kind)) }
                else { Text(session.origin.label).font(.caption2).foregroundStyle(.secondary) }
            }
        }.foregroundStyle(.primary).padding(.vertical, 2)
    }
}
