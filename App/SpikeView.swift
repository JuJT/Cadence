import SwiftUI
import CadenceCore

/// Premier IPA à essayer : même moteur et même extension, écran minimal.
/// Il ne valide aucune capacité avant installation réelle et retour utilisateur.
struct SpikeView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            List {
                Section("Preuve de faisabilité") {
                    Text("Cadence · essai iPhone")
                        .font(.title2.bold())
                    Text("Vérifiez l’installation, Raccourcis, le widget et la Live Activity. Ces fonctions ne sont pas encore validées sur votre appareil.")
                    Text("Aucune donnée Calendrier ni connexion nécessaire.")
                }
                Section("Séance d’essai") {
                    if let session = store.state.activeSession {
                        Text(session.kind.label)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(duration(session.elapsed(at: context.date)))
                                .font(.largeTitle.monospacedDigit())
                                .accessibilityLabel("Temps actif")
                        }
                        Text(session.isPaused ? "En pause" : "En cours")
                        Button(session.isPaused ? "Reprendre" : "Pause") {
                            if session.isPaused { store.resume() } else { store.pause() }
                        }
                        Button("Terminer") { store.finish() }
                    } else {
                        Button("Démarrer une révision d’essai") {
                            if let subject = store.state.subjects.first(where: { !$0.isArchived }) {
                                store.start(kind: .revision, subjectID: subject.id, topic: "Essai de faisabilité")
                            }
                        }
                    }
                }
                Section("Diagnostic") {
                    Text(store.storageDiagnostic).font(.footnote)
                    Text("Historique local : \(store.state.sessions.filter { $0.endedAt != nil }.count) séance(s)")
                }
                Section("Sur votre iPhone") {
                    Text("Laissez tourner deux minutes, verrouillez l’écran et ouvrez la Dynamic Island. Ajoutez le widget Cadence puis lancez « Démarrer une révision » dans Raccourcis après avoir terminé la séance.")
                    Text("Le compteur dépend des dates enregistrées ; aucun traitement permanent en arrière-plan n’est requis.")
                }
            }
            .navigationTitle("Essai Cadence")
            .alert("Cadence", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("Compris", role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
    }

    private func duration(_ seconds: Double) -> String {
        let seconds = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
