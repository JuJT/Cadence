import SwiftUI

struct SchoolConnectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var codeOrLink = ""
    @State private var messageRequested = false
    @State private var working = false

    var body: some View {
        List {
            Section {
                Label("Vos cours et devoirs", systemImage: "graduationcap")
                    .font(.headline)
                Text("Connectez votre compte une fois. Votre emploi du temps et vos devoirs s’actualisent ensuite automatiquement, sans calendrier Apple.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if store.schoolSignedIn {
                Section("Compte scolaire") {
                    if let address = store.schoolEmail { Text(address).privacySensitive() }
                    Label("Connexion enregistrée", systemImage: "checkmark.shield")
                    Button("Actualiser maintenant", systemImage: "arrow.clockwise") {
                        Task { await store.refreshSchool(force: true) }
                    }.disabled(store.schoolSyncing || working)
                    Button("Déconnecter cet iPhone", role: .destructive) {
                        working = true
                        Task {
                            await store.disconnectSchool()
                            working = false; codeOrLink = ""; messageRequested = false
                        }
                    }.disabled(working || store.schoolSyncing)
                }
            } else {
                Section("1 · Recevoir mon accès") {
                    TextField("Adresse e-mail du compte autorisé", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        .accessibilityIdentifier("school.login.email")
                    Button(messageRequested ? "Renvoyer le message" : "Recevoir le message de connexion", systemImage: "envelope") {
                        working = true
                        Task {
                            if await store.requestSchoolLogin(email: email) { messageRequested = true }
                            working = false
                        }
                    }.disabled(working || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("school.login.request")
                }
                if messageRequested {
                    Section("2 · Valider la connexion") {
                        SecureField("Code reçu ou lien complet", text: $codeOrLink)
                            .textContentType(.oneTimeCode).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().privacySensitive()
                            .accessibilityIdentifier("school.login.verification")
                        Text("Si le message contient un bouton de connexion, faites un appui long dessus pour copier son lien, puis collez-le ici sans l’ouvrir. Un code reçu par e-mail convient aussi.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Connecter mon compte", systemImage: "lock.open") {
                            working = true
                            Task {
                                if await store.verifySchoolLogin(email: email, codeOrLink: codeOrLink) { codeOrLink = "" }
                                working = false
                            }
                        }.disabled(working || codeOrLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("school.login.verify")
                    }
                }
            }
            Section("Synchronisation") {
                if store.schoolSyncing || working { ProgressView("Mise à jour en cours…") }
                Text(store.schoolStatus).font(.subheadline)
                if let error = store.schoolError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Text("Hors connexion, les dernières données enregistrées restent disponibles. Vos révisions, cours manuels et devoirs validés dans l’app sont conservés.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .cadenceListStyle()
        .navigationTitle("Connexion scolaire")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
        .onAppear { if email.isEmpty, let current = store.schoolEmail { email = current } }
        .onChange(of: store.schoolSignedIn) { _, signedIn in if signedIn { codeOrLink = "" } }
    }
}
