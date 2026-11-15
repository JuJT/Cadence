import SwiftUI
import CadenceCore

struct RevisionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var subjectID: UUID?
    @State private var topic = ""
    @State private var showFinish = false
    @State private var showManual = false
    var body: some View {
        ScrollViewReader { scrollProxy in
            AtelierPage {
            if let active = store.state.activeSession {
                timer(active).id("revision.content.top")
            } else {
                Text("Un moment pour vous concentrer.")
                    .font(.title3).foregroundStyle(.secondary).padding(.bottom, 4)
                    .id("revision.content.top")
                AtelierCard {
                    Label("Votre prochaine révision", systemImage: "books.vertical")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Matière").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        SubjectPicker(selection: $subjectID).pickerStyle(.menu)
                            .font(.title3.weight(.semibold)).controlSize(.large)
                    }.padding(.vertical, 4)
                    Divider().overlay(Color.white.opacity(0.25))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chapitre ou objectif").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        TextField("Ex. Suites, exercices, lecture…", text: $topic)
                            .font(.body).textFieldStyle(.plain).padding(.vertical, 8)
                            .accessibilityLabel("Chapitre ou objectif (facultatif)")
                    }
                }
                ProminentAction(title: "Démarrer une révision", symbol: "play.fill", tint: Atelier.blue) {
                    guard let id = subjectID ?? store.state.subjects.first(where: { !$0.isArchived })?.id else { return }
                    store.start(kind: .revision, subjectID: id, topic: topic)
                }.disabled(store.state.subjects.allSatisfy(\.isArchived)).accessibilityIdentifier("session.start")
                SecondaryAction(title: "Ajouter une révision passée", symbol: "plus") { showManual = true }
                AtelierCard {
                    Label("À votre rythme", systemImage: "pause.circle")
                        .font(.subheadline.weight(.semibold))
                    Text("Les pauses sont déduites de votre séance. Votre suivi continue lorsque vous verrouillez l’iPhone.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink("Voir l’historique des révisions") { HistoryView(initialKind: .revision) }
                        .font(.subheadline.weight(.medium)).padding(.vertical, 4)
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
    }

    private func timer(_ active: StudySession) -> some View {
        VStack(spacing: 24) {
            SessionDial(session: active, subject: Atelier.subject(active.subjectID, in: store.state))
                .frame(maxWidth: .infinity).padding(.top, 8)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { controls(active) }
            } else {
                HStack(spacing: 12) { controls(active) }
            }
            AtelierCard {
                HStack(spacing: 12) {
                    Label("Type de séance", systemImage: "scope")
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 4)
                    StatusBadge(title: active.kind.label, color: Atelier.color(for: active.kind))
                }
            }
            sessionStatistics(active)
            NavigationLink { SessionEditorView(session: active) } label: {
                HStack(spacing: 10) {
                    Label("Modifier les notes et le chapitre", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }.frame(minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(Atelier.blue)
            Text(active.isPaused ? "Votre séance est en pause. Reprenez quand vous le souhaitez." : "Votre temps est conservé, même lorsque l’application est fermée.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func sessionStatistics(_ active: StudySession) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let dayTotals = Statistics.totals(state: store.state, in: Atelier.day(context.date), now: context.date)
            let week = Calendar.current.dateInterval(of: .weekOfYear, for: context.date) ?? Atelier.day(context.date)
            let subjectTotals = Statistics.bySubject(state: store.state, in: week, now: context.date)[active.subjectID] ?? StudyTotals()
            AtelierCard {
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
        ProminentAction(title: "Terminer", symbol: "stop.fill", tint: Atelier.blue) { showFinish = true }.accessibilityIdentifier("session.finish")
    }
}

/// Un anneau de lumière encadre le temps écoulé, sans représenter un objectif.
private struct SessionDial: View {
    let session: StudySession
    let subject: Subject?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var timerFontSize = 52.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if dynamicTypeSize >= .xxLarge {
                AtelierCard {
                    dialContent(now: context.date)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }.frame(maxWidth: 520)
            } else {
                ZStack {
                    dialSurface.padding(14)
                    Circle()
                        .stroke(Atelier.blue.opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 20)
                        .padding(9)
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Atelier.blue.opacity(0.27), .cyan.opacity(0.65), Atelier.blue, Atelier.blue.opacity(0.25)],
                                startPoint: .bottomLeading, endPoint: .topTrailing
                            ),
                            style: StrokeStyle(lineWidth: 16, lineCap: .round)
                        )
                        .padding(9)
                        .opacity(session.isPaused ? 0.55 : 1)
                        .shadow(color: Atelier.blue.opacity(colorScheme == .dark ? 0.16 : 0.24), radius: 15, x: 0, y: 8)
                    Circle()
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.13 : 0.65), lineWidth: 1)
                        .padding(18)
                    dialContent(now: context.date).padding(36)
                }
                .aspectRatio(1, contentMode: .fit).frame(maxWidth: 420)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: session.isPaused)
            }
        }
    }

    @ViewBuilder private var dialSurface: some View {
        if reduceTransparency {
            Circle().fill(Color(uiColor: .secondarySystemGroupedBackground))
        } else {
            Circle().fill(.ultraThinMaterial)
        }
    }

    private func dialContent(now: Date) -> some View {
        VStack(spacing: 12) {
            Image(systemName: subject?.symbol ?? "book.closed")
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundStyle(Atelier.blue).frame(width: 52, height: 52)
                .background(Atelier.blue.opacity(colorScheme == .dark ? 0.15 : 0.09), in: RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.7), lineWidth: 1))
                .accessibilityHidden(true)
            Text(subject?.name ?? "Matière archivée")
                .font(.title3.weight(.semibold)).foregroundStyle(CadenceColors.ink).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !session.topic.isEmpty {
                Text(session.topic).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            Text(Atelier.clock(session.elapsed(at: now)))
                .font(.system(size: timerFontSize, weight: .bold, design: .rounded))
                .monospacedDigit().tracking(-1.8).lineLimit(1).minimumScaleFactor(0.65)
                .foregroundStyle(CadenceColors.ink)
                .padding(.vertical, 5)
                .accessibilityLabel("Temps suivi : \(Atelier.clock(session.elapsed(at: now)))")
            Text(session.isPaused ? "En pause" : "Temps écoulé")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
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
