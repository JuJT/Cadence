import SwiftUI
import CadenceCore

struct SchoolConnectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locator = SchoolLocatorService()
    @State private var address = ""
    @State private var schoolURL = ""
    @State private var schoolName: String?
    @State private var username = ""
    @State private var password = ""
    @State private var working = false
    @State private var finding = false
    @State private var discoveryError: String?
    @State private var schools: [PronoteSchool] = []
    @State private var showSchools = false
    @State private var discoveryTask: Task<Void, Never>?
    @State private var securityPIN = ""
    @State private var newPassword = ""
    @State private var passwordConfirmation = ""
    @State private var securitySource = "Cadenza iPhone"
    @State private var securityMode = 0
    @FocusState private var passwordFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                Label("Votre espace PRONOTE", systemImage: "graduationcap").font(.headline)
                Text("Connectez-vous avec les identifiants PRONOTE fournis par votre établissement.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if store.schoolSignedIn { accountSection }
            else if let challenge = store.pronoteChallenge { securitySection(challenge) }
            else { discoverySection; credentialsSection }
            synchronizationSection
        }
        .cadenceListStyle()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Connexion PRONOTE")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
        .sheet(isPresented: $showSchools) {
            SchoolFinderSheet(schools: schools) { school in
                schoolURL = school.url; schoolName = school.name
            }
        }
        .onChange(of: store.pronoteChallenge) { _, challenge in
            if let challenge { prepareSecurity(challenge) }
        }
        .onChange(of: store.schoolSignedIn) { _, signedIn in if signedIn { clearSecrets() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { clearSecrets() }
        }
        .onDisappear {
            discoveryTask?.cancel(); locator.cancel()
            clearSecrets()
        }
    }

    private var discoverySection: some View {
        Section {
            Button {
                findSchools(usingLocation: true)
            } label: { Label("Autour de moi", systemImage: "location") }
                .disabled(finding || working).accessibilityIdentifier("school.find.nearby")
            HStack(spacing: 10) {
                TextField("Ville, code postal ou adresse", text: $address)
                    .textContentType(.addressCity).autocorrectionDisabled()
                    .submitLabel(.search).onSubmit { findSchools(usingLocation: false) }
                    .accessibilityIdentifier("school.find.address")
                Button { findSchools(usingLocation: false) } label: {
                    Image(systemName: "magnifyingglass").frame(width: 36, height: 36)
                }
                .accessibilityLabel("Rechercher les établissements")
                .accessibilityIdentifier("school.find.search")
                .disabled(finding || working || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if finding { ProgressView("Recherche des établissements…") }
            if let discoveryError {
                Label(discoveryError, systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if let schoolName, !schoolName.isEmpty {
                Label(schoolName, systemImage: "building.2").font(.subheadline)
            }
            TextField("https://…/pronote/", text: $schoolURL)
                .textContentType(.URL).keyboardType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                .accessibilityIdentifier("school.login.url")
            if !schoolURL.isEmpty, SchoolLoginValidation.url(schoolURL) == nil {
                Text("Utilisez l’adresse HTTPS de PRONOTE, pas celle du portail ENT ni une adresse locale.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } header: { Text("1 · Mon établissement") } footer: {
            Text("La localisation est facultative et demandée uniquement avec « Autour de moi ». Vous pouvez aussi saisir directement l’adresse PRONOTE.")
        }
    }

    private var credentialsSection: some View {
        Section {
            Label("Espace élève", systemImage: "person.crop.circle")
            TextField("Identifiant PRONOTE", text: $username)
                .textContentType(.username).textInputAutocapitalization(.never)
                .autocorrectionDisabled().privacySensitive().accessibilityIdentifier("school.login.username")
            SecureField("Mot de passe PRONOTE", text: $password)
                .textContentType(.password).focused($passwordFocused).submitLabel(.done)
                .onSubmit { passwordFocused = false }
                .accessibilityIdentifier("school.login.password")
            Button("Me connecter", systemImage: "lock.open") { connect() }
                .disabled(working || finding || SchoolLoginValidation.url(schoolURL) == nil ||
                    username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                .accessibilityIdentifier("school.login.connect")
        } header: { Text("2 · Mon compte") }
    }

    private var accountSection: some View {
        Section {
            if let profile = store.pronoteProfile {
                Text(profile.displayName).font(.headline).privacySensitive()
                Text(profile.establishment).font(.subheadline).foregroundStyle(.secondary)
                if let className = profile.className, !className.isEmpty {
                    Text(className).font(.subheadline).foregroundStyle(.secondary)
                }
            } else if let name = store.schoolEmail { Text(name).privacySensitive() }
            Label("Connexion enregistrée", systemImage: "checkmark.shield")
            NavigationLink { PronotePortalView() } label: { Label("Mon espace PRONOTE", systemImage: "graduationcap") }
                .accessibilityIdentifier("school.account.portal")
            Button("Actualiser maintenant", systemImage: "arrow.clockwise") {
                Task { await store.refreshSchool(force: true) }
            }.disabled(store.schoolSyncing || working)
            Button("Déconnecter cet iPhone", role: .destructive) {
                working = true
                Task { await store.disconnectSchool(); working = false; clearSecrets() }
            }.disabled(working || store.schoolSyncing)
        } header: { Text("Compte PRONOTE") }
    }

    private func securitySection(_ challenge: PronoteSecurityChallenge) -> some View {
        Section {
            if !challenge.message.isEmpty { Text(challenge.message).font(.subheadline) }
            if challenge.shouldCustomDoubleAuth {
                Picker("Protection de la connexion", selection: $securityMode) {
                    ForEach(modes(for: challenge), id: \.self) { mode in Text(modeTitle(mode)).tag(mode) }
                }.accessibilityIdentifier("school.security.mode")
            }
            if needsPIN(challenge) {
                SecureField(challenge.shouldEnterPIN ? "Code PIN PRONOTE" : "Choisir un code PIN", text: $securityPIN)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .privacySensitive()
                    .accessibilityIdentifier("school.security.pin")
            }
            if challenge.shouldCustomPassword {
                Text("PRONOTE demande de choisir un nouveau mot de passe pour ce compte.")
                    .font(.footnote).foregroundStyle(.secondary)
                SecureField("Nouveau mot de passe PRONOTE", text: $newPassword).textContentType(.newPassword)
                    .privacySensitive()
                    .accessibilityIdentifier("school.security.new-password")
                SecureField("Confirmer le nouveau mot de passe", text: $passwordConfirmation).textContentType(.newPassword)
                    .privacySensitive()
                Text(passwordRule(challenge)).font(.caption).foregroundStyle(.secondary)
            }
            if challenge.shouldEnterSource {
                TextField("Nom de cet appareil", text: $securitySource).textContentType(.nickname)
                    .accessibilityIdentifier("school.security.source")
            }
            Button("Valider la sécurité", systemImage: "checkmark.shield") {
                working = true
                Task {
                    let success = await store.completePronoteSecurity(
                        pin: needsPIN(challenge) ? securityPIN : "",
                        password: challenge.shouldCustomPassword ? newPassword : "",
                        source: challenge.shouldEnterSource ? securitySource.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                        mode: challenge.shouldCustomDoubleAuth ? securityMode : nil)
                    if success { clearSecrets() }
                    working = false
                }
            }
            .disabled(working || !securityReady(challenge))
            .accessibilityIdentifier("school.security.complete")
            Button("Recommencer la connexion", role: .cancel) {
                working = true
                Task { await store.disconnectSchool(); clearSecrets(); working = false }
            }.disabled(working)
        } header: { Text("Sécurité demandée par PRONOTE") }
            .onAppear { prepareSecurity(challenge) }
    }

    private var synchronizationSection: some View {
        Section("Synchronisation") {
            if store.schoolSyncing || working { ProgressView("Mise à jour en cours…") }
            Text(store.schoolStatus).font(.subheadline)
            if let error = store.schoolError {
                Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.orange)
            }
            Text("Hors connexion, les dernières données enregistrées restent disponibles. Vos séances personnelles et vos devoirs validés dans Cadenza sont conservés.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func connect() {
        guard let url = SchoolLoginValidation.url(schoolURL), !working else { return }
        passwordFocused = false
        working = true
        Task {
            let success = await store.connectPronote(url: url, username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password, kind: 6)
            if success { clearSecrets() }
            else if let challenge = store.pronoteChallenge { password = ""; prepareSecurity(challenge) }
            working = false
        }
    }

    private func findSchools(usingLocation: Bool) {
        guard !finding, !working else { return }
        finding = true; discoveryError = nil
        discoveryTask = Task {
            do {
                let coordinate = usingLocation ? try await locator.currentCoordinates() : try await locator.coordinates(for: address)
                try Task.checkCancellation()
                let result = try await store.findPronoteSchools(latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard !Task.isCancelled else { finding = false; return }
                schools = result
                if result.isEmpty { discoveryError = "Aucun établissement trouvé ici. Essayez une ville voisine ou l’adresse PRONOTE." }
                else { showSchools = true }
            } catch {
                if !Task.isCancelled { discoveryError = error.localizedDescription }
            }
            finding = false
        }
    }

    private func modes(for challenge: PronoteSecurityChallenge) -> [Int] {
        let available = Array(Set(challenge.availableModes)).sorted()
        return available.isEmpty ? [challenge.defaultMode] : available
    }
    private func prepareSecurity(_ challenge: PronoteSecurityChallenge) {
        let available = modes(for: challenge)
        securityMode = available.contains(challenge.defaultMode) ? challenge.defaultMode : available.first ?? 0
    }
    private func modeTitle(_ mode: Int) -> String {
        switch mode { case 0: return "Désactivée"; case 1: return "Sans code PIN"; case 2: return "Avec validation"; case 3: return "Avec saisie du PIN"; default: return "Option PRONOTE \(mode)" }
    }
    private func needsPIN(_ challenge: PronoteSecurityChallenge) -> Bool {
        challenge.shouldEnterPIN || (challenge.shouldCustomDoubleAuth && securityMode == 3)
    }
    private func securityReady(_ challenge: PronoteSecurityChallenge) -> Bool {
        if challenge.shouldCustomDoubleAuth, !modes(for: challenge).contains(securityMode) { return false }
        if needsPIN(challenge), securityPIN.isEmpty || !securityPIN.utf8.allSatisfy({ (48...57).contains($0) }) { return false }
        if challenge.shouldCustomPassword {
            let count = newPassword.utf16.count
            if count < max(1, challenge.passwordMinLength) || newPassword != passwordConfirmation { return false }
            if challenge.passwordMaxLength > 0, count > challenge.passwordMaxLength { return false }
        }
        return !challenge.shouldEnterSource || !securitySource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private func passwordRule(_ challenge: PronoteSecurityChallenge) -> String {
        challenge.passwordMaxLength > 0
            ? "De \(challenge.passwordMinLength) à \(challenge.passwordMaxLength) caractères."
            : "Au moins \(challenge.passwordMinLength) caractères."
    }
    private func clearSecrets() { password = ""; securityPIN = ""; newPassword = ""; passwordConfirmation = "" }
}

private struct SchoolFinderSheet: View {
    let schools: [PronoteSchool]
    let select: (PronoteSchool) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(schools) { school in
                Button {
                    select(school); dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(school.name.isEmpty ? "Établissement" : school.name).font(.headline).foregroundStyle(CadenceColors.ink)
                        if let postalCode = school.postalCode, !postalCode.isEmpty { Text(postalCode).font(.caption).foregroundStyle(.secondary) }
                        Text(URL(string: school.url)?.host ?? school.url).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain).disabled(SchoolLoginValidation.url(school.url) == nil)
                .accessibilityIdentifier("school.find.result." + school.id)
            }
            .cadenceListStyle().navigationTitle("Choisir mon établissement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .accessibilityIdentifier("school.find.results")
    }
}

private enum SchoolLoginValidation {
    static func url(_ input: String) -> String? {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.utf8.count <= 2_048, let components = URLComponents(string: clean),
              components.scheme?.lowercased() == "https", components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(), host.contains("."), !host.contains(":"),
              host.split(separator: ".").last?.contains(where: { $0.isLetter }) == true,
              !["localhost", "local", "internal", "lan", "home", "test", "invalid"].contains(String(host.split(separator: ".").last ?? "")),
              components.fragment == nil, let url = components.url else { return nil }
        return url.absoluteString
    }
}
