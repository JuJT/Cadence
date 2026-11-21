import SwiftUI
import UserNotifications

/// Kept outside the personal backup schema: importing a study backup must not
/// replay an old release tour or silently complete a fresh setup.
enum AppIntroductionMode { case setup, update }

struct AppIntroductionView: View {
    let mode: AppIntroductionMode
    let onComplete: () -> Void
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var notifications = TimetableNotificationService.shared
    @AppStorage("cadence.introduction.notificationChoiceRecorded") private var notificationChoiceRecorded = false
    @State private var page = 0
    @State private var movingForward = true
    @State private var showConnection = false
    @State private var showNotificationStep = false
    @State private var checkingPermission = false
    @State private var requestingPermission = false

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.7.0" }
    static var releaseID: String {
        version + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "8") + ")"
    }
    private var currentPage: IntroductionPage { pages[page] }
    private var lastPage: Bool { page == pages.count - 1 }

    var body: some View {
        NavigationStack {
            ZStack {
                if showNotificationStep {
                    notificationContent
                } else {
                    pageContent.id(page).transition(pageTransition)
                }
            }
            .clipped()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showNotificationStep { notificationFooter } else { footer }
            }
            .navigationTitle(showNotificationStep ? "Notifications" : mode == .setup ? "Bienvenue" : "Nouveautés · " + Self.version)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if page > 0 && !showNotificationStep {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Précédent", systemImage: "chevron.left") { go(to: page - 1) }
                            .accessibilityIdentifier("intro.previous")
                    }
                }
            }
            .sheet(isPresented: $showConnection, onDismiss: {
                // Cancelling or failing authentication leaves setup open. Merely
                // presenting a connection sheet never completes onboarding.
                if mode == .setup && store.schoolSignedIn { go(to: 2) }
            }) { NavigationStack { SchoolConnectionView(isOnboarding: true) } }
            .onChange(of: store.schoolSignedIn) { _, connected in
                if connected && showConnection && mode == .setup {
                    showConnection = false
                    go(to: 2)
                }
            }
        }
        .interactiveDismissDisabled()
        .accessibilityIdentifier(mode == .setup ? "intro.setup" : "intro.update")
    }

    private var pageContent: some View {
        AtelierPage {
            VStack(spacing: 20) {
                Image(systemName: currentPage.symbol)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Atelier.blue)
                    .frame(height: 100)
                    .accessibilityHidden(true)
                Text(currentPage.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("intro.title")
                Text(currentPage.description)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 8)

            AtelierCard {
                ForEach(Array(currentPage.features.enumerated()), id: \.offset) { _, feature in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: feature.symbol)
                            .font(.title2)
                            .foregroundStyle(Atelier.blue)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(feature.title).font(.headline)
                            Text(feature.description).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }

            if mode == .setup && store.schoolSignedIn && page > 0 {
                Label("PRONOTE connecté", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("intro.connected")
            }
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity))
    }

    private func go(to next: Int) {
        guard pages.indices.contains(next), next != page else { return }
        movingForward = next > page
        withAnimation(reduceMotion ? .linear(duration: 0.15) : .easeInOut(duration: 0.32)) { page = next }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle().fill(index == page ? Atelier.blue : Color.secondary.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Étape \(page + 1) sur \(pages.count)")
            .accessibilityIdentifier("intro.progress")

            if mode == .setup && page == 1 && !store.schoolSignedIn {
                ProminentAction(title: "Connecter PRONOTE", symbol: "graduationcap") { showConnection = true }
                    .accessibilityIdentifier("intro.connect")
                Button("Plus tard") { go(to: 2) }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("intro.skip")
            } else {
                ProminentAction(title: lastPage ? (mode == .setup ? "C’est parti" : "Découvrir Cadenza") : "Continuer",
                                symbol: lastPage ? "checkmark" : "arrow.right") {
                    if lastPage { finishTour() } else { go(to: page + 1) }
                }
                .disabled(checkingPermission)
                .accessibilityIdentifier(lastPage ? "intro.finish" : "intro.continue")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var notificationContent: some View {
        AtelierPage {
            VStack(spacing: 16) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Atelier.blue)
                    .accessibilityHidden(true)
                Text("Votre emploi du temps change ?")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Cadenza peut vous prévenir quand PRONOTE annonce une absence ou un cours déplacé, annulé ou modifié.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)

            AtelierCard {
                Label("Vous pouvez modifier votre choix dans Réglages.", systemImage: "gearshape")
                    .font(.subheadline)
                if let message = notifications.message, notifications.authorization == .notDetermined {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var notificationFooter: some View {
        VStack(spacing: 10) {
            if requestingPermission { ProgressView() }
            ProminentAction(title: "Autoriser les notifications", symbol: "bell") { requestNotifications() }
                .disabled(requestingPermission)
                .accessibilityIdentifier("intro.notifications.allow")
            Button("Plus tard") { finishNotifications() }
                .frame(minHeight: 44)
                .disabled(requestingPermission)
                .accessibilityIdentifier("intro.notifications.skip")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func finishTour() {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--uitesting-notifications-intro") {
            showNotificationStep = true
            return
        }
        #endif
        guard !notificationChoiceRecorded else { onComplete(); return }
        checkingPermission = true
        Task {
            await notifications.readPermission()
            checkingPermission = false
            if notifications.authorization == .notDetermined { showNotificationStep = true }
            else { onComplete() }
        }
    }

    private func requestNotifications() {
        requestingPermission = true
        Task {
            await notifications.setEnabled(true)
            requestingPermission = false
            if notifications.authorization != .notDetermined { finishNotifications() }
        }
    }

    private func finishNotifications() {
        notificationChoiceRecorded = true
        onComplete()
    }

    private var pages: [IntroductionPage] {
        if mode == .setup {
            return [
                .init(symbol: "graduationcap", title: "Votre journée,\nen harmonie.",
                      description: "Les cours, les devoirs et les révisions se retrouvent dans un même espace.", features: [
                        .init(symbol: "calendar", title: "Anticipez votre journée", description: "Retrouvez votre emploi du temps et ce qui vous attend."),
                        .init(symbol: "checklist", title: "Avancez simplement", description: "Validez un devoir ou démarrez une révision depuis sa carte."),
                        .init(symbol: "chart.bar", title: "Gardez votre rythme", description: "Suivez vos séances et vos progrès au fil des jours.")
                      ]),
                .init(symbol: "person.badge.key", title: "Votre établissement,\ntout près.",
                      description: "Connectez votre compte PRONOTE pour retrouver les informations de votre scolarité.", features: [
                        .init(symbol: "building.2", title: "Votre compte habituel", description: "Choisissez l’établissement, puis utilisez vos identifiants PRONOTE."),
                        .init(symbol: "books.vertical", title: "Tout à portée de main", description: "Cours, devoirs, notes et informations sont réunis dans Cadenza."),
                        .init(symbol: "lock.shield", title: "Une connexion personnelle", description: "Le mot de passe initial n’est pas conservé. Votre connexion reste protégée sur cet iPhone.")
                      ]),
                .init(symbol: "checkmark.seal", title: "À votre rythme.",
                      description: "Tout est prêt pour vous accompagner, en classe comme pendant vos révisions.", features: [
                        .init(symbol: "timer", title: "Un geste pour commencer", description: "Choisissez une matière ou un devoir et lancez votre séance."),
                        .init(symbol: "wifi.slash", title: "Vos repères, même hors ligne", description: "Les données scolaires déjà synchronisées restent consultables."),
                        .init(symbol: "gearshape", title: "Gardez la main", description: "Connexion, apparence et sauvegardes vous attendent dans Réglages.")
                      ])
            ]
        }
        return [
            .init(symbol: "graduationcap", title: "Votre scolarité au quotidien",
                  description: "Retrouvez les repères de votre journée dès l’accueil.", features: [
                    .init(symbol: "bell", title: "Votre établissement", description: "Informations, messagerie et vie scolaire sont accessibles depuis l’accueil."),
                    .init(symbol: "chart.bar", title: "Notes par matière", description: "Consultez les moyennes et ouvrez une évaluation pour voir ses détails."),
                    .init(symbol: "checklist", title: "Du devoir à la révision", description: "Lancez le chronomètre directement depuis votre devoir.")
                  ]),
            .init(symbol: "calendar", title: "Votre journée de cours",
                  description: "Choisissez un jour pour voir ses horaires, ses salles et les changements annoncés.", features: [
                    .init(symbol: "calendar.day.timeline.left", title: "Des cours faciles à distinguer", description: "Retrouvez chaque matière, l’horaire, la salle et les changements annoncés."),
                    .init(symbol: "bell.badge", title: "Les changements de planning", description: "Choisissez si vous voulez être prévenu des changements de cours."),
                    .init(symbol: "books.vertical", title: "Une année par matière", description: "Retrouvez les contenus de cours depuis la rentrée.")
                  ]),
            .init(symbol: "timer", title: "Gardez le fil de vos révisions",
                  description: "Retrouvez votre séance en cours quel que soit l’onglet.", features: [
                    .init(symbol: "timer", title: "Retour au chronomètre", description: "Touchez le bandeau de la séance pour reprendre là où vous en étiez."),
                    .init(symbol: "chart.bar", title: "Statistiques et historique", description: "Retrouvez votre temps par période et par matière dans Révision."),
                    .init(symbol: "headphones", title: "Musique", description: "Ouvrez vos commandes Apple Music ou Spotify pendant la séance.")
                  ])
        ]
    }
}

private struct IntroductionPage {
    let symbol: String
    let title: String
    let description: String
    let features: [IntroductionFeature]
}

private struct IntroductionFeature {
    let symbol: String
    let title: String
    let description: String
}
