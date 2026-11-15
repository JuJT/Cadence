import SwiftUI
import Charts
import CadenceCore

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showNewSession = false
    @ScaledMetric(relativeTo: .largeTitle) private var totalFontSize = 42.0

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
                Text("Prêt pour une nouvelle séance ?")
                    .font(.title3).foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                todayCard(totals)
                if let active = store.state.activeSession {
                    ActiveSessionCard(session: active) { store.route = "revision" }
                }
                if let next = store.state.occurrences.filter({ $0.start > context.date && $0.status != .cancelled && $0.status != .ignored && $0.status != .absent }).sorted(by: { $0.start < $1.start }).first {
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
                                    Text("Votre planning vous attend").font(.headline).foregroundStyle(CadenceColors.ink)
                                    Text("Ajoutez un cours ou liez votre emploi du temps.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
                ProminentAction(title: "Nouvelle séance", symbol: "play.fill") { showNewSession = true }
                    .accessibilityIdentifier("session.new")
                Button { store.route = "statistiques" } label: {
                    weekCard(now: context.date)
                }.buttonStyle(.plain)
                HStack {
                    Text("Historique récent").font(.headline)
                    Spacer()
                    NavigationLink("Tout voir") { HistoryView() }
                        .font(.subheadline.weight(.medium))
                }.padding(.top, 8)
                if store.state.sessions.isEmpty {
                    AtelierCard {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title2).foregroundStyle(Atelier.blue.opacity(0.75))
                                .frame(width: 34, height: 40).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Une première séance ?").font(.headline)
                                Text("Vos cours et vos révisions se retrouveront ici.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    AtelierCard {
                        ForEach(Array(store.state.sessions.sorted(by: { $0.startedAt > $1.startedAt }).prefix(5))) { session in
                            NavigationLink { SessionEditorView(session: session) } label: { SessionRow(session: session) }.buttonStyle(.plain)
                            if session.id != store.state.sessions.sorted(by: { $0.startedAt > $1.startedAt }).prefix(5).last?.id { Divider() }
                        }
                    }
                }
                Label(syncDescription, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
            }
        }
        .navigationTitle("Bonjour,")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showNewSession) { NewSessionSheet() }
    }

    private var syncDescription: String {
        guard store.state.settings.calendarEnabled else { return "Calendrier facultatif · suivi manuel disponible" }
        guard let date = store.lastSyncAt else { return "Calendrier activé · aucun import effectué" }
        return "Dernière synchronisation : " + date.cadenceFormatted(date: .abbreviated, time: .shortened)
    }

    private func todayCard(_ totals: StudyTotals) -> some View {
        AtelierCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 24) {
                    totalLabel(totals.total)
                    Spacer(minLength: 8)
                    dailyRing(totals).frame(width: 112, height: 112)
                }
                VStack(alignment: .leading, spacing: 18) {
                    totalLabel(totals.total)
                    dailyRing(totals).frame(width: 112, height: 112)
                }
            }
            VStack(spacing: 12) {
                summaryRow("Cours", detail: "Mesurés ou confirmés", seconds: totals.courseMeasured, color: Atelier.blue)
                Divider().overlay(Color.white.opacity(0.25))
                summaryRow("Révisions", detail: nil, seconds: totals.revisions, color: Atelier.revision)
                if totals.courseEstimated > 0 {
                    Divider().overlay(Color.white.opacity(0.25))
                    summaryRow("Cours estimés", detail: "D’après le calendrier", seconds: totals.courseEstimated, color: .cyan)
                }
            }
        }
    }

    private func totalLabel(_ seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
                Text("Aujourd’hui").font(.headline).foregroundStyle(CadenceColors.ink)
            Text(Atelier.duration(seconds))
                .font(.system(size: totalFontSize, weight: .bold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .tracking(-1.5).foregroundStyle(CadenceColors.ink)
            Text("de temps suivi").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func summaryRow(_ title: String, detail: String?, seconds: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(LinearGradient(colors: [color.opacity(0.55), color], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 10, height: 10).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Text(Atelier.duration(seconds)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
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
                    Text(next.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))) + " · " + next.start.cadenceFormatted(date: .omitted, time: .shortened) + " – " + next.end.cadenceFormatted(date: .omitted, time: .shortened))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        }
    }

    private func weekCard(now: Date) -> some View {
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now) ?? Atelier.day(now)
        let totals = Statistics.totals(state: store.state, in: interval, now: now)
        let days = weekDays(in: interval, now: now)
        return AtelierCard {
            HStack {
                Label("Cette semaine", systemImage: "chart.bar.xaxis")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 20) {
                    weekTotal(totals)
                    Spacer(minLength: 0)
                    miniHistogram(days, total: totals.total).frame(width: 142, height: 66)
                }
                VStack(alignment: .leading, spacing: 16) {
                    weekTotal(totals)
                    miniHistogram(days, total: totals.total).frame(height: 66)
                }
            }
        }.foregroundStyle(CadenceColors.ink)
    }

    private func weekTotal(_ totals: StudyTotals) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Atelier.duration(totals.total))
                .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
            Text("Cours et révisions").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func weekDays(in interval: DateInterval, now: Date) -> [HomeDayTotal] {
        var days: [HomeDayTotal] = []
        var date = interval.start
        while date < interval.end {
            let day = Atelier.day(date)
            days.append(HomeDayTotal(date: date, totals: Statistics.totals(state: store.state, in: day, now: now)))
            date = day.end
        }
        return days
    }

    private func miniHistogram(_ days: [HomeDayTotal], total: Double) -> some View {
        Group {
            if total > 0 {
                Chart(days) { day in
                    BarMark(x: .value("Jour", day.date, unit: .day), y: .value("Cours", (day.totals.courseMeasured + day.totals.courseEstimated) / 3600))
                        .foregroundStyle(LinearGradient(colors: [Atelier.blue.opacity(0.55), Atelier.blue], startPoint: .top, endPoint: .bottom))
                        .cornerRadius(3)
                    BarMark(x: .value("Jour", day.date, unit: .day), y: .value("Révisions", day.totals.revisions / 3600))
                        .foregroundStyle(Atelier.revision.opacity(0.6)).cornerRadius(3)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
            } else {
                HStack(alignment: .bottom, spacing: 9) {
                    ForEach(days) { _ in
                        Capsule().fill(Atelier.blue.opacity(0.12)).frame(maxWidth: .infinity).frame(height: 4)
                    }
                }.frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Répartition des cours et révisions sur la semaine")
        .accessibilityValue(total > 0 ? Atelier.duration(total) : "Aucune séance cette semaine")
    }

    private func dailyRing(_ totals: StudyTotals) -> some View {
        Chart {
            if totals.total > 0 {
                SectorMark(angle: .value("Cours", totals.courseMeasured + totals.courseEstimated), innerRadius: .ratio(0.75), angularInset: 2)
                    .foregroundStyle(LinearGradient(colors: [.cyan.opacity(0.55), Atelier.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .cornerRadius(7)
                SectorMark(angle: .value("Révisions", totals.revisions), innerRadius: .ratio(0.75), angularInset: 2)
                    .foregroundStyle(LinearGradient(colors: [Atelier.revision.opacity(0.55), Atelier.revision], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .cornerRadius(7)
            } else {
                SectorMark(angle: .value("Aucune séance", 1), innerRadius: .ratio(0.75))
                    .foregroundStyle(Atelier.blue.opacity(0.12))
            }
        }
        .shadow(color: Atelier.blue.opacity(totals.total > 0 ? 0.17 : 0), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Répartition du jour : cours \(Atelier.duration(totals.courseMeasured + totals.courseEstimated)), révisions \(Atelier.duration(totals.revisions))")
    }
}

private struct HomeDayTotal: Identifiable {
    let date: Date
    let totals: StudyTotals
    var id: Date { date }
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
