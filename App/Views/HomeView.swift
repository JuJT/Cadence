import SwiftUI
import Charts
import CadenceCore

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showNewSession = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let totals = Statistics.totals(state: store.state, in: Atelier.day(context.date), now: context.date)
            AtelierPage {
                if store.needsRecovery {
                    AtelierCard {
                        Label("Récupération des données", systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(.orange)
                        Text("Le fichier local existant est conservé. Restaurez une sauvegarde pour reprendre votre suivi.").foregroundStyle(.secondary)
                        NavigationLink("Restaurer une sauvegarde") { SettingsView() }
                    }
                }
                Text("Voici votre journée de cours et de révisions.").foregroundStyle(.secondary)
                AtelierCard {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 24) {
                            totalLabel(totals.total)
                            Spacer()
                            dailyRing(totals).frame(width: 106, height: 106)
                        }
                        totalLabel(totals.total)
                    }
                    MetricRow(title: "Cours mesurés ou confirmés", seconds: totals.courseMeasured)
                    MetricRow(title: "Cours estimés", seconds: totals.courseEstimated, color: .cyan)
                    MetricRow(title: "Révisions", seconds: totals.revisions, color: Atelier.revision)
                    Text("Les estimations suivent votre emploi du temps et peuvent être corrigées.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let active = store.state.activeSession {
                    ActiveSessionCard(session: active) { store.route = "revision" }
                }
                if let next = store.state.occurrences.filter({ $0.start > context.date && $0.status != .cancelled && $0.status != .ignored && $0.status != .absent }).sorted(by: { $0.start < $1.start }).first {
                    NavigationLink { CourseDetailView(occurrenceID: next.id) } label: {
                        AtelierCard {
                            Label("Prochain cours", systemImage: "calendar").font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                SubjectMark(subject: Atelier.subject(next.subjectID, in: store.state))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(next.displayTitle(in: store.state.subjects)).font(.headline).foregroundStyle(.primary)
                                    Text(next.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))) + " · " + next.start.cadenceFormatted(date: .omitted, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
                ProminentAction(title: "Nouvelle séance", symbol: "play.fill") { showNewSession = true }
                    .accessibilityIdentifier("session.new")
                HStack { Text("Historique récent").font(.title3.bold()); Spacer(); NavigationLink("Tout voir") { HistoryView() }.font(.subheadline) }
                if store.state.sessions.isEmpty {
                    EmptyCard(title: "Une première séance ?", symbol: "timer", description: "Démarrez une révision ou ajoutez un cours pour retrouver votre suivi ici.")
                } else {
                    AtelierCard {
                        ForEach(Array(store.state.sessions.sorted(by: { $0.startedAt > $1.startedAt }).prefix(5))) { session in
                            NavigationLink { SessionEditorView(session: session) } label: { SessionRow(session: session) }.buttonStyle(.plain)
                            if session.id != store.state.sessions.sorted(by: { $0.startedAt > $1.startedAt }).prefix(5).last?.id { Divider() }
                        }
                    }
                }
                Label(syncDescription, systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Cadence")
        .sheet(isPresented: $showNewSession) { NewSessionSheet() }
    }
    private var syncDescription: String {
        guard store.state.settings.calendarEnabled else { return "Calendrier facultatif · suivi manuel disponible" }
        guard let date = store.lastSyncAt else { return "Calendrier activé · aucun import effectué" }
        return "Dernière synchronisation : " + date.cadenceFormatted(date: .abbreviated, time: .shortened)
    }
    private func totalLabel(_ seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aujourd’hui").font(.headline)
            Text(Atelier.duration(seconds)).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit().minimumScaleFactor(0.7)
            Text("de temps suivi").font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private func dailyRing(_ totals: StudyTotals) -> some View {
        Chart {
            if totals.total > 0 {
                SectorMark(angle: .value("Cours", totals.courseMeasured + totals.courseEstimated), innerRadius: .ratio(0.74), angularInset: 2).foregroundStyle(Atelier.blue)
                SectorMark(angle: .value("Révisions", totals.revisions), innerRadius: .ratio(0.74), angularInset: 2).foregroundStyle(Atelier.revision)
            } else { SectorMark(angle: .value("Aucune séance", 1), innerRadius: .ratio(0.74)).foregroundStyle(Color.secondary.opacity(0.15)) }
        }.accessibilityElement(children: .ignore).accessibilityLabel("Cours : \(Atelier.duration(totals.courseMeasured + totals.courseEstimated)), révisions : \(Atelier.duration(totals.revisions))")
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
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Atelier.clock(session.elapsed(at: context.date))).font(.title2.monospacedDigit().bold()).foregroundStyle(Atelier.color(for: session.kind))
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
