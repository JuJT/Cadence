import SwiftUI
import CadenceCore

struct RevisionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var subjectID: UUID?
    @State private var topic = ""
    @State private var showFinish = false
    @State private var showManual = false
    @State private var showHomework = false
    @State private var showMusic = false

    var body: some View {
        ScrollViewReader { scrollProxy in
            AtelierPage {
                if let active = store.state.activeSession {
                    timer(active).id("revision.content.top")
                } else {
                    newRevision.id("revision.content.top")
                    AtelierCard {
                        CadenceSectionHeader(title: "Votre suivi")
                        statisticsShortcut
                        Divider()
                        NavigationLink(destination: HistoryView(initialKind: .revision)) {
                            RevisionActionLabel(title: "Historique des révisions", symbol: "clock.arrow.circlepath")
                        }.buttonStyle(.plain).accessibilityIdentifier("revision.history")
                        Divider()
                        Button { showManual = true } label: {
                            RevisionActionLabel(title: "Ajouter une révision passée", symbol: "plus")
                        }.buttonStyle(.plain)
                    }
                }
            }
            .onChange(of: store.state.activeSession?.id) { _, _ in
                // La nouvelle mise en page ne doit pas hériter du défilement du formulaire.
                scrollProxy.scrollTo("revision.content.top", anchor: .top)
            }
        }
        .navigationTitle(store.state.activeSession.map { $0.kind == .course ? "Cours en cours" : "Révision en cours" } ?? "Révision")
        .navigationBarTitleDisplayMode(store.state.activeSession == nil ? .large : .inline)
        .onAppear { if subjectID == nil { subjectID = store.state.settings.defaultSubjectID ?? store.state.subjects.first(where: { !$0.isArchived })?.id } }
        .alert("Terminer la séance ?", isPresented: $showFinish) {
            Button("Terminer et enregistrer") { store.finish() }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("La durée suivie sera enregistrée dans votre historique.")
        }
        .sheet(isPresented: $showManual) { NavigationStack { NewSessionView(kind: .revision, startAsTimer: false) } }
        .sheet(isPresented: $showHomework) { HomeworkPickerSheet() }
        .sheet(isPresented: $showMusic) { NavigationStack { MusicView() } }
    }

    private var newRevision: some View {
        AtelierCard {
            CadenceSectionHeader(title: "Nouvelle séance")
            VStack(alignment: .leading, spacing: 6) {
                Text("Matière").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                SubjectPicker(selection: $subjectID)
                    .pickerStyle(.menu)
                    .font(.headline)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Chapitre ou objectif").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                TextField("Ex. Suites, exercices, lecture…", text: $topic)
                    .font(.body).textFieldStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Chapitre ou objectif (facultatif)")
            }
            ProminentAction(title: "Démarrer une révision", symbol: "play.fill") {
                guard let id = subjectID ?? store.state.subjects.first(where: { !$0.isArchived })?.id else { return }
                store.start(kind: .revision, subjectID: id, topic: topic)
            }
            .disabled(store.state.subjects.allSatisfy(\.isArchived))
            .accessibilityIdentifier("session.start")
        }
    }

    private var statisticsShortcut: some View {
        Button { store.route = "statistiques" } label: {
            RevisionActionLabel(title: "Statistiques", symbol: "chart.bar.xaxis")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("revision.statistics.shortcut")
    }

    private func timer(_ active: StudySession) -> some View {
        VStack(spacing: 16) {
            SessionDial(session: active, subject: Atelier.subject(active.subjectID, in: store.state))
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { controls(active) }
            } else {
                HStack(spacing: 12) { controls(active) }
            }
            AtelierCard {
                if let id = active.activeHomeworkID, let item = store.state.homework.first(where: { $0.id == id }) {
                    CadenceSectionHeader(title: "Devoir associé", subtitle: item.source.subject)
                    Text(SchoolRichText.plain(item.source.description)).font(.subheadline)
                        .accessibilityIdentifier("session.homework.description")
                    Button("Valider ce devoir", systemImage: "checkmark.circle") { store.setHomeworkCompletion(id, isDone: true) }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("session.homework.complete")
                    Divider()
                }
                Button { showHomework = true } label: {
                    RevisionActionLabel(title: active.activeHomeworkID == nil ? "Associer un devoir" : "Changer de devoir", symbol: "checklist")
                }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("session.homework.choose")
            }
            AtelierCard {
                Button { showMusic = true } label: {
                    RevisionActionLabel(title: "Musique", symbol: "headphones")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("session.music")
                Divider()
                NavigationLink { SessionEditorView(session: active) } label: {
                    RevisionActionLabel(title: "Modifier les notes et le chapitre", symbol: "square.and.pencil")
                }.buttonStyle(.plain)
            }
            sessionStatistics(active)
            Text(active.isPaused ? "Votre séance est en pause. Reprenez quand vous le souhaitez." : "Votre temps est conservé, même lorsque l’application est fermée.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func sessionStatistics(_ active: StudySession) -> some View {
        CadenceTimelineView(interval: 30) { now in
            let dayTotals = Statistics.totals(state: store.state, in: Atelier.day(now), now: now)
            let week = Calendar.current.dateInterval(of: .weekOfYear, for: now) ?? Atelier.day(now)
            let subjectTotals = Statistics.bySubject(state: store.state, in: week, now: now)[active.subjectID] ?? StudyTotals()
            AtelierCard {
                statisticsShortcut
                Divider()
                if dynamicTypeSize.isAccessibilitySize {
                    sessionMetric("Aujourd’hui", detail: "Cours et révisions", seconds: dayTotals.total, symbol: "stopwatch")
                    Divider()
                    sessionMetric("Cette matière", detail: "Cette semaine", seconds: subjectTotals.total, symbol: "calendar")
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        sessionMetric("Aujourd’hui", detail: "Cours et révisions", seconds: dayTotals.total, symbol: "stopwatch")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider().frame(height: 50)
                        sessionMetric("Cette matière", detail: "Cette semaine", seconds: subjectTotals.total, symbol: "calendar")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func sessionMetric(_ title: String, detail: String, seconds: Double, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(Atelier.duration(seconds))
                .font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func controls(_ active: StudySession) -> some View {
        SecondaryAction(title: active.isPaused ? "Reprendre" : "Pause", symbol: active.isPaused ? "play.fill" : "pause.fill") {
            if active.isPaused { store.resume() } else { store.pause() }
        }.accessibilityIdentifier(active.isPaused ? "session.resume" : "session.pause")
        ProminentAction(title: "Terminer", symbol: "stop.fill") { showFinish = true }.accessibilityIdentifier("session.finish")
    }
}

private struct RevisionActionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Atelier.blue)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct SessionDial: View {
    let session: StudySession
    let subject: Subject?
    @ScaledMetric(relativeTo: .largeTitle) private var timerFontSize = 51.0

    var body: some View {
        AtelierCard {
            HStack(alignment: .top, spacing: 12) {
                SubjectMark(subject: subject)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(subject?.name ?? "Matière archivée")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(CadenceColors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(session.isPaused ? "En pause" : session.kind.label,
                          systemImage: session.isPaused ? "pause.circle" : session.kind.symbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            let topic = session.topic.trimmingCharacters(in: .whitespacesAndNewlines)
            if !topic.isEmpty && topic.localizedCaseInsensitiveCompare(subject?.name ?? "") != .orderedSame {
                Text(topic).font(.subheadline).foregroundStyle(.secondary)
            }

            VStack(spacing: 5) {
                SessionElapsedText(session: session)
                    .font(.system(size: timerFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Atelier.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.42)
                    .accessibilityIdentifier("session.elapsed")
                Text("Temps écoulé").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

struct SessionElapsedText: View {
    let session: StudySession
    @Environment(\.cadenceTabIsActive) private var activeTab
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()

    private var runningSessionID: UUID? {
        session.isActive && !session.isPaused && activeTab && scenePhase == .active ? session.id : nil
    }

    var body: some View {
        let elapsed = DurationText.clock(session.elapsed(at: now))
        Text(elapsed)
            .monospacedDigit()
            .accessibilityLabel("Temps suivi : " + elapsed)
            .task(id: runningSessionID) { @MainActor in
                guard runningSessionID != nil else { return }
                now = .now
                // The view only samples the clock. Persisted segments retain the time across launches.
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) }
                    catch { return }
                    guard !Task.isCancelled else { return }
                    now = .now
                }
            }
    }
}

struct SubjectPicker: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: UUID?
    var body: some View {
        Picker("Matière", selection: $selection) {
            Text("Choisir une matière").tag(nil as UUID?)
            ForEach(store.state.subjects.filter { !$0.isArchived || $0.id == selection }.sorted { $0.position < $1.position }) { subject in
                Label(subject.name, systemImage: subject.symbol).tag(Optional(subject.id))
            }
        }
    }
}
