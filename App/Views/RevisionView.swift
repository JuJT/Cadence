import SwiftUI
import CadenceCore

struct RevisionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var subjectID: UUID?
    @State private var topic = ""
    @State private var showFinish = false
    @State private var showManual = false
    var body: some View {
        AtelierPage {
            if let active = store.state.activeSession {
                timer(active)
            } else {
                AtelierCard {
                    Label("Prêt pour une révision ?", systemImage: "books.vertical").font(.title3.bold())
                    Text("Choisissez une matière et lancez votre séance. Les pauses sont déduites du temps suivi.").foregroundStyle(.secondary)
                    SubjectPicker(selection: $subjectID)
                    TextField("Chapitre ou objectif (facultatif)", text: $topic).textFieldStyle(.roundedBorder)
                }
                ProminentAction(title: "Démarrer une révision", symbol: "play.fill", tint: Atelier.revision) {
                    guard let id = subjectID ?? store.state.subjects.first(where: { !$0.isArchived })?.id else { return }
                    store.start(kind: .revision, subjectID: id, topic: topic)
                }.disabled(store.state.subjects.allSatisfy(\.isArchived)).accessibilityIdentifier("session.start")
                SecondaryAction(title: "Ajouter une révision passée", symbol: "plus") { showManual = true }
                Text("Le temps est calculé à partir des dates de début et de pause, même lorsque l’application est fermée.")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("Voir l’historique des révisions") { HistoryView(initialKind: .revision) }
            }
        }
        .navigationTitle(store.state.activeSession?.kind == .course ? "Cours en cours" : "Révision")
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
            StatusBadge(title: active.kind.label + " · " + (active.isPaused ? "En pause" : "En cours"), color: Atelier.color(for: active.kind))
            AtelierCard {
                VStack(spacing: 18) {
                    SubjectMark(subject: Atelier.subject(active.subjectID, in: store.state))
                    Text(Atelier.subject(active.subjectID, in: store.state)?.name ?? "Matière archivée").font(.title2.bold()).multilineTextAlignment(.center)
                    if !active.topic.isEmpty { Text(active.topic).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Atelier.clock(active.elapsed(at: context.date)))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                            .minimumScaleFactor(0.6).lineLimit(1).padding(.vertical, 24)
                            .accessibilityLabel("Temps suivi : \(Atelier.duration(active.elapsed(at: context.date)))")
                    }
                    Text(active.isPaused ? "La durée reste figée pendant la pause." : "Votre suivi continue lorsque l’iPhone est verrouillé.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { controls(active) }
                VStack(spacing: 12) { controls(active) }
            }
            NavigationLink("Modifier les notes et le chapitre") { SessionEditorView(session: active) }
            Text("Une seule séance chronométrée à la fois. Terminez celle-ci avant d’en démarrer une nouvelle.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func controls(_ active: StudySession) -> some View {
        SecondaryAction(title: active.isPaused ? "Reprendre" : "Pause", symbol: active.isPaused ? "play.fill" : "pause.fill") {
            if active.isPaused { store.resume() } else { store.pause() }
        }.accessibilityIdentifier(active.isPaused ? "session.resume" : "session.pause")
        ProminentAction(title: "Terminer", symbol: "stop.fill", tint: Atelier.color(for: active.kind)) { showFinish = true }.accessibilityIdentifier("session.finish")
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
