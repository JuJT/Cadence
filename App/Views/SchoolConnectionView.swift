import CadenceCore
import SwiftUI

struct SchoolConnectionView: View {
    let isOnboarding: Bool

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locator = SchoolLocatorService()
    @State private var step: Step = .methods
    @State private var establishmentStep: Step = .address
    @State private var address = ""
    @State private var schoolURL = ""
    @State private var schoolName: String?
    @State private var school: PronoteLoginAddress?
    @State private var username = ""
    @State private var password = ""
    @State private var working = false
    @State private var finding = false
    @State private var discoveryError: String?
    @State private var schools: [PronoteSchool] = []
    @State private var showSchools = false
    @State private var discoveryTask: Task<Void, Never>?
    @State private var showScanner = false
    @State private var pairingCode: PronotePairingCode?
    @State private var pairingPIN = ""
    @State private var entRequest: PronoteENTRequest?
    @State private var pendingENT: PronoteSignIn?
    @State private var authTask: Task<Void, Never>?
    @State private var loginAttempted = false
    @State private var securityPIN = ""
    @State private var newPassword = ""
    @State private var passwordConfirmation = ""
    @State private var securitySource = "Cadenza iPhone"
    @State private var securityMode = 0
    @FocusState private var passwordFocused: Bool

    private enum Step { case methods, directory, address, credentials, pairing }

    init(isOnboarding: Bool = false) { self.isOnboarding = isOnboarding }

    var body: some View {
        AtelierPage {
            if store.schoolSignedIn { accountSection }
            else if let challenge = store.pronoteChallenge { securitySection(challenge) }
            else {
                switch step {
                case .methods: methodsPage
                case .directory: directoryPage
                case .address: addressPage
                case .credentials: credentialsPage
                case .pairing: pairingPage
                }
            }
            if store.schoolSignedIn || store.pronoteChallenge != nil || loginAttempted || working { synchronizationSection }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Connexion PRONOTE")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(step != .methods || working)
        .interactiveDismissDisabled(working || store.pronoteChallenge != nil)
        .toolbar {
            if !store.schoolSignedIn && (step != .methods || store.pronoteChallenge != nil) {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Précédent", systemImage: "chevron.left", action: goBack)
                        .disabled(working).accessibilityIdentifier("school.previous")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Terminé", action: close).disabled(working)
            }
        }
        .sheet(isPresented: $showSchools) {
            SchoolFinderSheet(schools: schools) { found in
                guard let portal = PronoteLoginAddress(found.url) else { return }
                selectSchool(portal, name: found.name, from: .directory)
            }
        }
        .sheet(isPresented: $showScanner) {
            PronoteQRScanner { code in
                pairingCode = code
                pairingPIN = ""
                loginAttempted = false
                step = .pairing
            }
        }
        .sheet(item: $entRequest, onDismiss: submitENT) { request in
            PronoteENTBrowser(request: request) { signIn in
                pendingENT = signIn
                entRequest = nil
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
            cancelDiscovery()
            if !store.schoolSignedIn { authTask?.cancel() }
            clearSecrets()
        }
    }

    private var methodsPage: some View {
        Group {
            pageHeader(symbol: "graduationcap", title: "Votre établissement",
                       subtitle: "Connectez votre espace élève PRONOTE pour retrouver vos cours, vos devoirs et vos notes.")
            AtelierCard {
                method("Scanner un QR code", symbol: "qrcode.viewfinder", id: "school.method.qr") { showScanner = true }
                Divider()
                method("Rechercher par ville", symbol: "magnifyingglass", id: "school.find.city") { step = .directory }
                Divider()
                method("Autour de moi", symbol: "location", id: "school.find.nearby") {
                    step = .directory
                    findSchools(usingLocation: true)
                }
                Divider()
                method("Saisir l’adresse PRONOTE", symbol: "link", id: "school.method.address") { step = .address }
            }
            if isOnboarding {
                Text("Vous pourrez aussi connecter votre compte plus tard dans les réglages.")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var directoryPage: some View {
        Group {
            pageHeader(symbol: "building.2", title: "Trouvez votre établissement",
                       subtitle: "Cherchez avec une ville ou un code postal. La position est facultative.")
            AtelierCard {
                TextField("Ville, code postal ou adresse", text: $address)
                    .textContentType(.addressCity).autocorrectionDisabled()
                    .submitLabel(.search).onSubmit { findSchools(usingLocation: false) }
                    .accessibilityIdentifier("school.find.address")
                if finding { ProgressView("Recherche des établissements…") }
                if let discoveryError { errorLabel(discoveryError) }
            }
            ProminentAction(title: "Rechercher", symbol: "magnifyingglass") { findSchools(usingLocation: false) }
                .disabled(finding || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("school.find.search")
            Button("Saisir l’adresse PRONOTE", systemImage: "link") { cancelDiscovery(); step = .address }
                .frame(minHeight: 44).accessibilityIdentifier("school.find.manual")
        }
    }

    private var addressPage: some View {
        Group {
            pageHeader(symbol: "link", title: "L’adresse de votre PRONOTE",
                       subtitle: "Collez l’adresse affichée dans le navigateur quand votre espace PRONOTE est ouvert.")
            AtelierCard {
                TextField("https://…/pronote/", text: $schoolURL)
                    .textContentType(.URL).keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    .accessibilityIdentifier("school.login.url")
                if !schoolURL.isEmpty && PronoteLoginAddress(schoolURL) == nil {
                    errorLabel("Utilisez l’adresse HTTPS publique de l’espace élève PRONOTE.")
                }
            }
            ProminentAction(title: "Continuer", symbol: "arrow.right") {
                if let portal = PronoteLoginAddress(schoolURL) { selectSchool(portal, name: nil, from: .address) }
            }
            .disabled(PronoteLoginAddress(schoolURL) == nil)
            .accessibilityIdentifier("school.address.continue")
        }
    }

    private var credentialsPage: some View {
        Group {
            pageHeader(symbol: "person.badge.key", title: schoolName ?? school?.base.host ?? "Votre espace élève",
                       subtitle: "Utilisez la même méthode qu’à votre habitude pour ouvrir PRONOTE.")
            if let school {
                ProminentAction(title: "Se connecter avec l’ENT", symbol: "globe") {
                    entRequest = PronoteENTRequest(address: school)
                }.disabled(working).accessibilityIdentifier("school.login.ent")
                Text("Disponible si votre établissement autorise l’ENT pour PRONOTE mobile.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            AtelierCard {
                Label("Identifiants PRONOTE", systemImage: "person.crop.circle").font(.headline)
                TextField("Identifiant PRONOTE", text: $username)
                    .textContentType(.username).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().privacySensitive().accessibilityIdentifier("school.login.username")
                Divider()
                SecureField("Mot de passe PRONOTE", text: $password)
                    .textContentType(.password).focused($passwordFocused).submitLabel(.done)
                    .onSubmit { passwordFocused = false }
                    .privacySensitive().accessibilityIdentifier("school.login.password")
                Button("Me connecter", systemImage: "lock.open") {
                    guard let school else { return }
                    passwordFocused = false
                    let signIn = PronoteSignIn.credentials(address: school,
                        username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                    password = ""
                    connect(signIn)
                }
                .frame(minHeight: 44)
                .disabled(working || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                .accessibilityIdentifier("school.login.connect")
            }
            Button("Utiliser un QR code", systemImage: "qrcode.viewfinder") { showScanner = true }
                .frame(minHeight: 44).disabled(working)
        }
    }

    private var pairingPage: some View {
        Group {
            pageHeader(symbol: "qrcode", title: "Validez le QR code",
                       subtitle: "Saisissez les quatre chiffres choisis lors de la génération du QR code dans PRONOTE.")
            AtelierCard {
                if let pairingCode, let host = PronoteLoginAddress(pairingCode.url)?.base.host {
                    Label(host, systemImage: "building.2").font(.subheadline)
                }
                SecureField("Code à quatre chiffres", text: $pairingPIN)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .privacySensitive().accessibilityIdentifier("school.pair.pin")
            }
            ProminentAction(title: "Connecter PRONOTE", symbol: "checkmark.shield") {
                guard let pairingCode, PronotePairingCode.isValidPIN(pairingPIN) else { return }
                let signIn = PronoteSignIn.pairing(code: pairingCode, pin: pairingPIN)
                pairingPIN = ""
                connect(signIn)
            }
            .disabled(working || !PronotePairingCode.isValidPIN(pairingPIN) || pairingCode == nil)
            .accessibilityIdentifier("school.pair.connect")
            Button(pairingCode == nil ? "Scanner le QR code" : "Scanner un autre QR code", systemImage: "qrcode.viewfinder") {
                showScanner = true
            }.frame(minHeight: 44).disabled(working)
        }
    }

    private var accountSection: some View {
        Group {
            pageHeader(symbol: "checkmark.shield", title: "Votre compte PRONOTE",
                       subtitle: "La connexion est enregistrée sur cet iPhone.")
            AtelierCard {
                if let profile = store.pronoteProfile {
                    Text(profile.displayName).font(.headline).privacySensitive()
                    Text(profile.establishment).font(.subheadline).foregroundStyle(.secondary)
                    if let className = profile.className, !className.isEmpty {
                        Text(className).font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if let name = store.schoolEmail { Text(name).privacySensitive() }
                NavigationLink { PronotePortalView() } label: { Label("Mon espace PRONOTE", systemImage: "graduationcap") }
                    .frame(minHeight: 44).accessibilityIdentifier("school.account.portal")
                Button("Actualiser maintenant", systemImage: "arrow.clockwise") {
                    Task { await store.refreshSchool(force: true) }
                }.frame(minHeight: 44).disabled(store.schoolSyncing || working)
                Button("Déconnecter cet iPhone", role: .destructive) {
                    working = true
                    Task { await store.disconnectSchool(); working = false; clearSecrets(); step = .methods }
                }.frame(minHeight: 44).disabled(working || store.schoolSyncing)
            }
        }
    }

    private func securitySection(_ challenge: PronoteSecurityChallenge) -> some View {
        Group {
            pageHeader(symbol: "lock.shield", title: "Vérifiez la connexion", subtitle: challenge.message)
            AtelierCard {
                if challenge.shouldCustomDoubleAuth {
                    Picker("Protection de la connexion", selection: $securityMode) {
                        ForEach(modes(for: challenge), id: \.self) { mode in Text(modeTitle(mode)).tag(mode) }
                    }.accessibilityIdentifier("school.security.mode")
                }
                if needsPIN(challenge) {
                    SecureField(challenge.shouldEnterPIN ? "Code PIN PRONOTE" : "Choisir un code PIN", text: $securityPIN)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .privacySensitive().accessibilityIdentifier("school.security.pin")
                }
                if challenge.shouldCustomPassword {
                    Text("PRONOTE demande un nouveau mot de passe pour ce compte.")
                        .font(.footnote).foregroundStyle(.secondary)
                    SecureField("Nouveau mot de passe PRONOTE", text: $newPassword).textContentType(.newPassword)
                        .privacySensitive().accessibilityIdentifier("school.security.new-password")
                    SecureField("Confirmer le nouveau mot de passe", text: $passwordConfirmation).textContentType(.newPassword)
                        .privacySensitive()
                    Text(passwordRule(challenge)).font(.caption).foregroundStyle(.secondary)
                }
                if challenge.shouldEnterSource {
                    TextField("Nom de cet appareil", text: $securitySource).textContentType(.nickname)
                        .accessibilityIdentifier("school.security.source")
                }
            }
            ProminentAction(title: "Valider la sécurité", symbol: "checkmark.shield") { completeSecurity(challenge) }
                .disabled(working || !securityReady(challenge)).accessibilityIdentifier("school.security.complete")
        }.onAppear { prepareSecurity(challenge) }
    }

    private var synchronizationSection: some View {
        AtelierCard {
            if store.schoolSyncing || working { ProgressView("Connexion PRONOTE en cours…") }
            if let error = store.schoolError { errorLabel(error) }
            if store.schoolSignedIn || loginAttempted {
                Text(store.schoolStatus).font(.subheadline)
            }
        }
    }

    private func pageHeader(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 54, weight: .light)).foregroundStyle(Atelier.blue)
                .padding(.vertical, 12).accessibilityHidden(true)
            Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 12)
    }

    private func method(_ label: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).foregroundStyle(Atelier.blue).frame(width: 26).accessibilityHidden(true)
                Text(label).font(.body.weight(.semibold))
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.secondary)
    }

    private func selectSchool(_ portal: PronoteLoginAddress, name: String?, from origin: Step) {
        school = portal
        schoolName = name
        establishmentStep = origin
        loginAttempted = false
        step = .credentials
    }

    private func submitENT() {
        guard let signIn = pendingENT else { return }
        pendingENT = nil
        connect(signIn)
    }

    private func connect(_ signIn: PronoteSignIn) {
        guard !working else { return }
        working = true
        loginAttempted = true
        authTask = Task {
            let success = await store.connectPronote(signIn)
            if success || store.pronoteChallenge != nil { clearSecrets() }
            working = false
        }
    }

    private func completeSecurity(_ challenge: PronoteSecurityChallenge) {
        let pin = needsPIN(challenge) ? securityPIN : ""
        let password = challenge.shouldCustomPassword ? newPassword : ""
        let source = challenge.shouldEnterSource ? securitySource.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let mode = challenge.shouldCustomDoubleAuth ? securityMode : nil
        working = true
        clearSecrets()
        authTask = Task {
            _ = await store.completePronoteSecurity(pin: pin, password: password, source: source, mode: mode)
            working = false
        }
    }

    private func goBack() {
        if store.pronoteChallenge != nil { finishChallenge(then: { step = .methods }); return }
        cancelDiscovery()
        clearSecrets()
        loginAttempted = false
        switch step {
        case .credentials: step = establishmentStep
        case .directory, .address, .pairing: step = .methods
        case .methods: break
        }
    }

    private func close() {
        if store.pronoteChallenge != nil { finishChallenge(then: { dismiss() }) }
        else { dismiss() }
    }

    private func finishChallenge(then action: @escaping () -> Void) {
        working = true
        Task {
            await store.cancelPronoteChallenge()
            clearSecrets()
            loginAttempted = false
            working = false
            action()
        }
    }

    private func findSchools(usingLocation: Bool) {
        guard !finding, !working else { return }
        finding = true
        discoveryError = nil
        discoveryTask = Task {
            do {
                let coordinate = usingLocation ? try await locator.currentCoordinates() : try await locator.coordinates(for: address)
                try Task.checkCancellation()
                let result = try await store.findPronoteSchools(latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard !Task.isCancelled else { return }
                schools = result.filter { PronoteLoginAddress($0.url) != nil }
                if schools.isEmpty { discoveryError = "Aucun établissement trouvé ici. Essayez une ville voisine ou saisissez l’adresse PRONOTE." }
                else { showSchools = true }
            } catch {
                if !Task.isCancelled { discoveryError = error.localizedDescription }
            }
            if !Task.isCancelled { finding = false }
        }
    }

    private func cancelDiscovery() {
        discoveryTask?.cancel()
        locator.cancel()
        discoveryTask = nil
        finding = false
        discoveryError = nil
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

    private func clearSecrets() {
        password = ""; securityPIN = ""; newPassword = ""; passwordConfirmation = ""
        pairingCode = nil; pairingPIN = ""; pendingENT = nil
    }
}

private struct SchoolFinderSheet: View {
    let schools: [PronoteSchool]
    let select: (PronoteSchool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(schools) { school in
                Button {
                    select(school)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(school.name.isEmpty ? "Établissement" : school.name).font(.headline).foregroundStyle(CadenceColors.ink)
                        if let postalCode = school.postalCode, !postalCode.isEmpty {
                            Text(postalCode).font(.caption).foregroundStyle(.secondary)
                        }
                        if let host = URL(string: school.url)?.host { Text(host).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("school.find.result." + school.id)
            }
            .cadenceListStyle().navigationTitle("Choisir mon établissement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }.accessibilityIdentifier("school.find.results")
    }
}
