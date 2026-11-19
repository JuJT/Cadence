import SwiftUI

/// Kept outside the personal backup schema: importing a study backup must not
/// replay an old release tour or silently complete a fresh setup.
enum AppIntroductionMode { case setup, update }

struct AppIntroductionView: View {
    let mode: AppIntroductionMode
    let onComplete: () -> Void
    @EnvironmentObject private var store: AppStore
    @State private var page = 0
    @State private var showConnection = false

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.0" }
    static var releaseID: String {
        version + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "6") + ")"
    }
    private var currentPage: IntroductionPage { pages[page] }
    private var lastPage: Bool { page == pages.count - 1 }

    var body: some View {
        NavigationStack {
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
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .navigationTitle(mode == .setup ? "Bienvenue" : "Nouveautés · " + Self.version)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if page > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Précédent", systemImage: "chevron.left") { page -= 1 }
                            .accessibilityIdentifier("intro.previous")
                    }
                }
            }
            .sheet(isPresented: $showConnection, onDismiss: {
                // Cancelling or failing authentication leaves setup open. Merely
                // presenting a connection sheet never completes onboarding.
                if mode == .setup && store.schoolSignedIn { page = 2 }
            }) { NavigationStack { SchoolConnectionView() } }
            .onChange(of: store.schoolSignedIn) { _, connected in
                if connected && showConnection && mode == .setup {
                    showConnection = false
                    page = 2
                }
            }
        }
        .interactiveDismissDisabled()
        .accessibilityIdentifier(mode == .setup ? "intro.setup" : "intro.update")
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
                Button("Plus tard") { page = 2 }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("intro.skip")
            } else {
                ProminentAction(title: lastPage ? (mode == .setup ? "C’est parti" : "Découvrir Cadenza") : "Continuer",
                                symbol: lastPage ? "checkmark" : "arrow.right") {
                    if lastPage { onComplete() } else { page += 1 }
                }
                .accessibilityIdentifier(lastPage ? "intro.finish" : "intro.continue")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
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
            .init(symbol: "books.vertical", title: "Votre scolarité\nau premier plan.",
                  description: "Une organisation plus claire pour retrouver ce qui compte au quotidien.", features: [
                    .init(symbol: "chart.bar.xaxis", title: "Des résultats plus lisibles", description: "Les notes et les moyennes suivent la période sélectionnée."),
                    .init(symbol: "book.closed", title: "Les ressources par matière", description: "Retrouvez les contenus de cours dans un classement familier."),
                    .init(symbol: "person.crop.circle.badge.clock", title: "Une vie scolaire plus claire", description: "Dates, durées et régularisations se lisent d’un coup d’œil.")
                  ]),
            .init(symbol: "checklist", title: "Vos devoirs,\nun geste plus près.",
                  description: "Des cartes utiles et du contenu lisible, dès le premier regard.", features: [
                    .init(symbol: "checkmark.circle", title: "Validez directement", description: "Marquez un devoir terminé depuis sa carte."),
                    .init(symbol: "play.circle", title: "Lancez votre révision", description: "Démarrez une séance sans ouvrir le détail du devoir."),
                    .init(symbol: "text.alignleft", title: "L’essentiel, bien présenté", description: "Les textes PRONOTE sont débarrassés des balises HTML.")
                  ]),
            .init(symbol: "sparkles", title: "Une expérience\nplus fluide.",
                  description: "Les mêmes repères Liquid Glass, avec moins de détours.", features: [
                    .init(symbol: "moon", title: "Des séances sans aller-retour", description: "Cadenza reste à l’écran au démarrage et à la fin d’une séance."),
                    .init(symbol: "play.rectangle", title: "Votre lecteur iOS", description: "Gardez vos commandes média dans le Centre de contrôle, avec le volume et AirPlay ici."),
                    .init(symbol: "hand.wave", title: "Les nouveautés vous accompagnent", description: "À chaque nouvelle version, découvrez les changements avant de reprendre.")
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
