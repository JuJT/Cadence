import SwiftUI
import UserNotifications

struct TimetableNotificationSettings: View {
    @ObservedObject private var service = TimetableNotificationService.shared
    @Environment(\.scenePhase) private var phase
    @State private var requesting = false

    var body: some View {
        List {
            Section {
                Toggle("Changements de cours", isOn: Binding(get: { service.enabled }, set: { enabled in
                    requesting = true
                    Task { await service.setEnabled(enabled); requesting = false }
                })).disabled(requesting)
                if service.authorization == .denied, let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    Link("Autoriser les notifications dans Réglages", destination: url)
                }
            } header: { Text("Emploi du temps PRONOTE") } footer: {
                Text("Recevez une alerte pour un professeur signalé absent ou un cours ajouté, modifié, déplacé, annulé ou retiré. La première synchronisation établit votre emploi du temps de référence.")
            }
            Section {
                Label("À chaque synchronisation", systemImage: "arrow.triangle.2.circlepath")
                Text("Cadenza vérifie les changements à l’ouverture, pendant l’utilisation et lorsque iOS autorise une actualisation en arrière-plan.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let message = service.message { Text(message).font(.footnote) }
            }
        }
        .cadenceListStyle()
        .navigationTitle("Notifications")
        .task(id: phase) { if phase == .active { await service.readPermission() } }
    }
}
